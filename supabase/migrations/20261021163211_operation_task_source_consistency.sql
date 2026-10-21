-- Materialize actionable calendar/maintenance reminders, without authorizing or completing a WO.
create or replace function private.todo_source(p_key text,p_assignee uuid,p_title text,p_description text,p_unit uuid,p_asset uuid,p_due timestamptz,p_priority text,p_origin text,p_plan uuid,p_wo uuid,p_source_status text,p_approval text,p_procedure jsonb) returns uuid language plpgsql security definer set search_path='' as $$
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
 if t.source_key is distinct from p_key or t.work_order_id is distinct from coalesce(p_wo,t.work_order_id) or t.source_status is distinct from p_source_status or t.source_approval is distinct from p_approval or t.due_at is distinct from p_due then
 update public.operation_tasks set source_key=p_key,work_order_id=coalesce(p_wo,work_order_id),source_status=p_source_status,source_approval=p_approval,due_at=p_due where id=t.id;
 perform private.todo_activity(t.id,null,'schedule_updated','Calendar / source status updated: '||coalesce(p_source_status,'scheduled')||case when p_approval is not null then ' · execution approval: '||p_approval else '' end);
 end if;
 end if;
 return t.id;
end $$;
