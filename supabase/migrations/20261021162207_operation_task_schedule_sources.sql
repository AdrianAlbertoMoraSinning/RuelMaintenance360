-- Materialize actionable calendar/maintenance reminders, without authorizing or completing a WO.
create function private.todo_source(p_key text,p_assignee uuid,p_title text,p_description text,p_unit uuid,p_asset uuid,p_due timestamptz,p_priority text,p_origin text,p_plan uuid,p_wo uuid,p_source_status text,p_approval text,p_procedure jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare owner_id uuid;t public.operation_tasks%rowtype;c jsonb;pos integer:=0;label_text text;steps jsonb;
begin
 select corporate_manager_id into owner_id from public.profiles where id=p_assignee and active;
 if owner_id is null or not private.todo_can_assign(owner_id,p_assignee) or not private.todo_unit_access(p_assignee,p_unit) or not private.todo_unit_access(owner_id,p_unit) then return null;end if;
 select * into t from public.operation_tasks where source_key=p_key;
 if t.id is null and p_wo is not null and p_plan is not null then
 select * into t from public.operation_tasks where maintenance_plan_id=p_plan and assigned_to=p_assignee and work_order_id is null and source_key like 'plan:%' and status not in ('completed','cancelled') order by due_at,created_at limit 1;
 end if;
 if t.id is null then
 insert into public.operation_tasks(title,description,assigned_by,assigned_to,created_by,business_unit_id,asset_id,due_at,priority,origin,maintenance_plan_id,work_order_id,source_key,source_status,source_approval)
 values(left(p_title,200),left(coalesce(p_description,''),10000),owner_id,p_assignee,auth.uid(),p_unit,p_asset,p_due,p_priority,p_origin,p_plan,p_wo,p_key,p_source_status,p_approval)
 on conflict(source_key) do nothing returning * into t;
 if t.id is null then select * into t from public.operation_tasks where source_key=p_key;return t.id;end if;
 steps:=case when jsonb_typeof(p_procedure)='array' then p_procedure when jsonb_typeof(p_procedure->'steps')='array' then p_procedure->'steps' when jsonb_typeof(p_procedure->'checklist')='array' then p_procedure->'checklist' else '[]'::jsonb end;
 for c in select value from jsonb_array_elements(steps) limit 200 loop
 label_text:=case when jsonb_typeof(c)='string' then c#>>'{}' else coalesce(c->>'label',c->>'title',c->>'description',c->>'instruction') end;
 if nullif(btrim(label_text),'') is not null then pos:=pos+1;insert into public.operation_task_checks(task_id,position,label) values(t.id,pos,left(btrim(label_text),1000));end if;
 end loop;
 perform private.todo_activity(t.id,null,'scheduled','Added from the maintenance/calendar schedule. Task progress does not authorize work or replace the Work Order approval workflow.');
 else
 perform private.todo_lock_tree(t.id);select * into t from public.operation_tasks where id=t.id for update;
 if t.work_order_id is distinct from coalesce(p_wo,t.work_order_id) or t.source_status is distinct from p_source_status or t.source_approval is distinct from p_approval or t.due_at is distinct from p_due then
 update public.operation_tasks set work_order_id=coalesce(p_wo,work_order_id),source_status=p_source_status,source_approval=p_approval,due_at=p_due where id=t.id;
 perform private.todo_activity(t.id,null,'schedule_updated','Calendar / source status updated: '||coalesce(p_source_status,'scheduled')||case when p_approval is not null then ' · execution approval: '||p_approval else '' end);
 end if;
 end if;
 return t.id;
end $$;
create function private.todo_refresh() returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();scope uuid[];r record;t public.operation_tasks%rowtype;key text;result_id uuid;changed integer:=0;
begin
 if not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 select array_agg(id) into scope from public.profiles where active and (id=actor or private.todo_can_assign(actor,id));
 -- WOs first: a generated WO absorbs an open reminder for the same plan/assignee.
 for r in select w.*,p.procedure from public.work_orders w left join public.maintenance_plans p on p.id=w.maintenance_plan_id where w.assigned_to=any(scope) and (w.status not in ('completed','cancelled') or exists(select 1 from public.operation_tasks x where x.work_order_id=w.id and x.assigned_to=w.assigned_to)) loop
 result_id:=private.todo_source('wo:'||r.id||':'||r.assigned_to,r.assigned_to,r.title,coalesce(r.problem_description,''),r.business_unit_id,r.asset_id,coalesce(r.scheduled_for,r.maintenance_due_date::timestamp at time zone 'America/Edmonton',r.created_at),case when r.priority='critical' then 'emergency' when r.priority='high' then 'high' else 'normal' end,case when r.maintenance_plan_id is not null then 'maintenance' else 'work_order' end,r.maintenance_plan_id,r.id,r.status::text,r.execution_approval_status,r.procedure);
 if result_id is not null then changed:=changed+1;end if;
 end loop;
 for r in select p.*,a.business_unit_id,a.hour_meter,a.odometer_km from public.maintenance_plans p join public.assets a on a.id=p.asset_id where p.active and p.assigned_to=any(scope) and ((p.next_due_date is not null and p.next_due_date<=((now() at time zone 'America/Edmonton')::date+7)) or (p.next_due_hours is not null and a.hour_meter>=p.next_due_hours) or (p.next_due_km is not null and a.odometer_km>=p.next_due_km)) loop
 key:='plan:'||r.id||':'||r.assigned_to||':'||coalesce(r.next_due_date::text,'-')||':'||coalesce(r.next_due_hours::text,'-')||':'||coalesce(r.next_due_km::text,'-');
 if exists(select 1 from public.work_orders w where w.maintenance_plan_id=r.id and w.assigned_to=r.assigned_to and w.status not in ('completed','cancelled')) then continue;end if;
 result_id:=private.todo_source(key,r.assigned_to,r.title,coalesce(r.description,'')||E'\nMaintenance follow-up only. Controlled maintenance execution and plan advancement stay in the existing Work Order workflow.',r.business_unit_id,r.asset_id,coalesce((r.next_due_date+time '17:00') at time zone 'America/Edmonton',now()),case when r.default_priority='critical' then 'emergency' when r.default_priority='high' then 'high' else 'normal' end,'maintenance',r.id,null,'scheduled',null,r.procedure);
 if result_id is not null then changed:=changed+1;end if;
 end loop;
 -- Reflect source cancellation/reassignment; do not hide open delegated children.
 for t in select * from public.operation_tasks where assigned_to=any(scope) and work_order_id is not null and status not in ('completed','cancelled') loop
 select assigned_to,status into r from public.work_orders where id=t.work_order_id;
 if r.assigned_to is distinct from t.assigned_to or r.status='cancelled' then
 perform private.todo_lock_tree(t.id);
 if t.source_status is distinct from 'assignment_ended' then
 update public.operation_tasks set source_status='assignment_ended',status=case when exists(select 1 from public.operation_tasks c where c.parent_task_id=t.id and c.status not in ('completed','cancelled')) then 'blocked' else 'cancelled' end where id=t.id;
 perform private.todo_activity(t.id,null,'source_closed','The linked Work Order was cancelled or reassigned. Reconcile any delegated tasks with your supervisor.');end if;
 end if;
 end loop;
 return changed;
end $$;
create function public.refresh_operation_task_sources() returns integer language sql security invoker set search_path='' as $$select private.todo_refresh()$$;


revoke all on function private.todo_source(text,uuid,text,text,uuid,uuid,timestamptz,text,text,uuid,uuid,text,text,jsonb),private.todo_refresh() from public,anon,authenticated;
grant execute on function private.todo_refresh() to authenticated;
revoke all on function public.refresh_operation_task_sources() from public,anon;grant execute on function public.refresh_operation_task_sources() to authenticated;
