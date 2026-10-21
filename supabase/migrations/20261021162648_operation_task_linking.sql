-- Attach existing schedule assignments to the leadership task that they implement.
create function private.todo_link(p_task_id uuid,p_parent_id uuid,p_expected_activity_id bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();child public.operation_tasks%rowtype;parent public.operation_tasks%rowtype;root_id uuid;
begin
 if not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 -- Ordered root locks avoid opposite-order locks across two task trees.
 for root_id in with recursive tree as (
 select id,parent_task_id from public.operation_tasks where id in(p_task_id,p_parent_id)
 union select t.id,t.parent_task_id from public.operation_tasks t join tree x on x.parent_task_id=t.id
 ) select distinct id from tree where parent_task_id is null order by id loop perform private.todo_lock_tree(root_id);end loop;
 select * into child from public.operation_tasks where id=p_task_id for update;
 select * into parent from public.operation_tasks where id=p_parent_id for update;
 if child.id is null or parent.id is null or child.assigned_by<>actor or parent.assigned_to<>actor or not private.todo_can_assign(actor,child.assigned_to) then raise exception 'Only the task assigner can link it to a task assigned to them';end if;
 if child.last_activity_id is distinct from p_expected_activity_id then raise exception 'New activity arrived. Reload the task before linking';end if;
 if child.status in('completion_requested','completed','cancelled') or parent.status in('completion_requested','completed','cancelled') then raise exception 'Both tasks must be open';end if;
 if child.parent_task_id=p_parent_id then return;end if;
 if child.parent_task_id is not null then raise exception 'This task is already linked';end if;
 if parent.business_unit_id is not null and child.business_unit_id is distinct from parent.business_unit_id then raise exception 'Linked tasks must belong to the same business unit';end if;
 if exists(with recursive ancestors as (select id,parent_task_id from public.operation_tasks where id=p_parent_id union select t.id,t.parent_task_id from public.operation_tasks t join ancestors a on a.parent_task_id=t.id) select 1 from ancestors where id=p_task_id) then raise exception 'Task linking would create a cycle';end if;
 update public.operation_tasks set parent_task_id=p_parent_id where id=p_task_id;
 perform private.todo_activity(p_task_id,actor,'linked','Linked to TASK-'||parent.task_number||' — '||parent.title);
end $$;
create function public.link_operation_task(p_task_id uuid,p_parent_id uuid,p_expected_activity_id bigint) returns void language sql security invoker set search_path='' as $$select private.todo_link(p_task_id,p_parent_id,p_expected_activity_id)$$;
revoke all on function private.todo_link(uuid,uuid,bigint),public.link_operation_task(uuid,uuid,bigint) from public,anon;grant execute on function private.todo_link(uuid,uuid,bigint),public.link_operation_task(uuid,uuid,bigint) to authenticated;

create or replace function private.todo_refresh() returns integer language plpgsql security definer set search_path='' as $$
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
 result_id:=private.todo_source(key,r.assigned_to,r.title,coalesce(r.description,'')||E'\nMaintenance follow-up only. Controlled maintenance execution and plan advancement stay in the existing Work Order workflow.',r.business_unit_id,r.asset_id,coalesce((r.next_due_date+time '17:00') at time zone 'America/Edmonton',(select due_at from public.operation_tasks where source_key=key),((now() at time zone 'America/Edmonton')::date+time '17:00') at time zone 'America/Edmonton'),case when r.default_priority='critical' then 'emergency' when r.default_priority='high' then 'high' else 'normal' end,'maintenance',r.id,null,'scheduled',null,r.procedure);
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
 for t in select * from public.operation_tasks where assigned_to=any(scope) and work_order_id is null and source_key like 'plan:%' and status not in ('completed','cancelled') loop
 select * into r from public.maintenance_plans where id=t.maintenance_plan_id;
 key:='plan:'||r.id||':'||r.assigned_to||':'||coalesce(r.next_due_date::text,'-')||':'||coalesce(r.next_due_hours::text,'-')||':'||coalesce(r.next_due_km::text,'-');
 if not coalesce(r.active,false) or r.assigned_to is distinct from t.assigned_to or t.source_key is distinct from key then
 perform private.todo_lock_tree(t.id);
 if t.source_status is distinct from 'assignment_ended' then
 update public.operation_tasks set source_status='assignment_ended',status=case when exists(select 1 from public.operation_tasks c where c.parent_task_id=t.id and c.status not in ('completed','cancelled')) then 'blocked' else 'cancelled' end where id=t.id;
 perform private.todo_activity(t.id,null,'source_closed','The maintenance plan advanced, was deactivated or reassigned. Reconcile delegated tasks with your supervisor.');end if;
 end if;
 end loop;
 return changed;
end $$;
