create function private.todo_configure(p_ceo uuid,p_members jsonb) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();m uuid;
begin
 if not exists(select 1 from public.profiles where id=actor and active and role in ('super_admin','it_admin')) then raise exception 'Administrator access required';end if;
 if not exists(select 1 from public.profiles where id=p_ceo and active and personnel_category='ceo') then raise exception 'Select the active CEO profile';end if;
 if jsonb_typeof(p_members) is distinct from 'array' then raise exception 'Committee members must be an array';end if;
 for m in select value::text::uuid from jsonb_array_elements_text(p_members) loop
 if not exists(select 1 from public.profiles where id=m and active and personnel_category='shareholder') then raise exception 'Committee membership is reserved for active Shareholders';end if;
 end loop;
 if (select count(distinct value) from jsonb_array_elements_text(p_members))<>(select count(*) from public.profiles where active and personnel_category='shareholder') then raise exception 'The committee must include all active Shareholders';end if;
 insert into public.task_governance(singleton,ceo_user_id,updated_by) values(true,p_ceo,actor) on conflict(singleton) do update set ceo_user_id=p_ceo,updated_by=actor,updated_at=now();
 update public.task_committee_members set active=false,updated_at=now(),appointed_by=actor;
 for m in select value::text::uuid from jsonb_array_elements_text(p_members) loop insert into public.task_committee_members(user_id,active,appointed_by) values(m,true,actor) on conflict(user_id) do update set active=true,appointed_by=actor,updated_at=now();end loop;
end $$;
create function public.configure_task_governance(p_ceo_id uuid,p_members jsonb) returns void language sql security invoker set search_path='' as $$select private.todo_configure(p_ceo_id,p_members)$$;
create function public.task_assignment_candidates() returns table(id uuid,full_name text,position_title text,personnel_category text) language sql stable security invoker set search_path='' as $$select p.id,p.full_name,p.position_title,p.personnel_category::text from public.profiles p where private.todo_can_assign((select auth.uid()),p.id) order by p.full_name$$;

create function private.todo_create(p_input jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();target uuid:=(p_input->>'assigned_to')::uuid;unit_id uuid:=nullif(p_input->>'business_unit_id','')::uuid;asset uuid:=nullif(p_input->>'asset_id','')::uuid;parent uuid:=nullif(p_input->>'parent_task_id','')::uuid;plan uuid:=nullif(p_input->>'maintenance_plan_id','')::uuid;t uuid;par public.operation_tasks%rowtype;ref record;c jsonb;pos integer:=0;kind text:=coalesce(p_input->>'origin','manual');checklist jsonb:=coalesce(p_input->'checklist','[]'::jsonb);
begin
 if not private.todo_can_assign(actor,target) then raise exception 'This assignment is not permitted by the reporting hierarchy';end if;
 if nullif(btrim(p_input->>'title'),'') is null then raise exception 'Enter a task title';end if;
 if (p_input->>'due_at')::timestamptz is null then raise exception 'A scheduled date/time is required';end if;
 if kind not in ('manual','emergency','maintenance') then raise exception 'Invalid task origin';end if;
 if plan is not null then select p.asset_id,a.business_unit_id into ref from public.maintenance_plans p join public.assets a on a.id=p.asset_id where p.id=plan and p.active;if not found then raise exception 'Active maintenance plan not found';end if;if asset is not null and asset<>ref.asset_id then raise exception 'Plan and asset differ';end if;asset:=ref.asset_id;if unit_id is not null and unit_id<>ref.business_unit_id then raise exception 'Plan and unit differ';end if;unit_id:=ref.business_unit_id;kind:='maintenance';end if;
 if asset is not null then select business_unit_id into ref from public.assets where id=asset;if not found then raise exception 'Asset not found';end if;if unit_id is not null and unit_id<>ref.business_unit_id then raise exception 'Asset and unit differ';end if;unit_id:=ref.business_unit_id;end if;
 if not private.todo_unit_access(actor,unit_id) or not private.todo_unit_access(target,unit_id) then raise exception 'Both people need access to the task business unit';end if;
 if parent is not null then perform private.todo_lock_tree(parent);select * into par from public.operation_tasks where id=parent for update;if not found or par.assigned_to<>actor or par.status in ('completion_requested','completed','cancelled') then raise exception 'Delegate only from an open task assigned to you';end if;if par.business_unit_id is not null and par.business_unit_id is distinct from unit_id then raise exception 'Linked tasks must use the parent business unit';end if;end if;
 if jsonb_typeof(checklist) is distinct from 'array' or jsonb_array_length(checklist)>200 then raise exception 'Use at most 200 checklist items';end if;
 insert into public.operation_tasks(title,description,business_unit_id,asset_id,assigned_by,assigned_to,created_by,parent_task_id,origin,maintenance_plan_id,due_at,priority) values(btrim(p_input->>'title'),coalesce(p_input->>'description',''),unit_id,asset,actor,target,actor,parent,kind,plan,(p_input->>'due_at')::timestamptz,case when kind='emergency' then 'emergency' else coalesce(p_input->>'priority','normal') end) returning id into t;
 for c in select value from jsonb_array_elements(checklist) loop pos:=pos+1;insert into public.operation_task_checks(task_id,position,label,required) values(t,pos,btrim(c->>'label'),coalesce((c->>'required')::boolean,true));end loop;
 perform private.todo_activity(t,actor,'assigned','Task assigned.');return t;
end $$;
create function public.create_operation_task(p_input jsonb) returns uuid language sql security invoker set search_path='' as $$select private.todo_create(p_input)$$;

create function private.todo_update(p_task uuid,p_message text,p_progress integer,p_status text,p_checks jsonb,p_expected bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();t public.operation_tasks%rowtype;c jsonb;next_status text;next_progress integer;
begin
 perform private.todo_lock_tree(p_task);select * into t from public.operation_tasks where id=p_task for update;
 if not found or not exists(select 1 from public.profiles where id=actor and active) or actor not in (t.assigned_by,t.assigned_to) then raise exception 'You cannot update this task';end if;
 if p_expected is not null and p_expected<>t.last_activity_id then raise exception 'This task has a new update. Refresh it before saving.';end if;
 if nullif(btrim(p_message),'') is null or length(p_message)>10000 then raise exception 'Add a progress note (maximum 10000 characters)';end if;
 if p_status='note' then perform private.todo_activity(t.id,actor,'comment',btrim(p_message));return;end if;
 if actor<>t.assigned_to then raise exception 'Only the assignee records progress';end if;
 if t.status in ('completed','cancelled','completion_requested') then raise exception 'This task is closed or awaiting review';end if;
 next_status:=coalesce(p_status,'in_progress');next_progress:=coalesce(p_progress,t.progress);
 if next_status not in ('pending','in_progress','blocked','completion_requested') or next_progress not between 0 and 100 then raise exception 'Invalid progress or status';end if;
 if jsonb_typeof(p_checks) is distinct from 'array' then raise exception 'Checklist changes must be an array';end if;
 for c in select value from jsonb_array_elements(p_checks) loop update public.operation_task_checks set done=(c->>'done')::boolean,done_by=case when (c->>'done')::boolean then actor end,done_at=case when (c->>'done')::boolean then now() end where id=(c->>'id')::uuid and task_id=t.id;if not found then raise exception 'Checklist item does not belong to this task';end if;end loop;
 if next_status='completion_requested' then
 if next_progress<>100 or exists(select 1 from public.operation_task_checks where task_id=t.id and required and not done) then raise exception 'Finish the required checklist and set progress to 100 percent';end if;
 if exists(select 1 from public.operation_tasks where parent_task_id=t.id and status not in ('completed','cancelled')) then raise exception 'Linked delegated tasks are still open';end if;
 if t.work_order_id is not null and not exists(select 1 from public.work_orders where id=t.work_order_id and status='completed') then raise exception 'The linked Work Order must complete its controlled approval workflow first';end if;
 elsif next_progress=100 then raise exception 'Use Request completion at 100 percent';end if;
 update public.operation_tasks set progress=next_progress,status=next_status where id=t.id;
 perform private.todo_activity(t.id,actor,case when next_status='completion_requested' then 'completion_requested' else 'progress' end,btrim(p_message));
end $$;
create function public.update_operation_task(p_task_id uuid,p_message text,p_progress integer default null,p_status text default 'in_progress',p_checks jsonb default '[]',p_expected_activity_id bigint default null) returns void language sql security invoker set search_path='' as $$select private.todo_update(p_task_id,p_message,p_progress,p_status,p_checks,p_expected_activity_id)$$;
create function private.todo_review(p_task uuid,p_action text,p_note text,p_expected bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();t public.operation_tasks%rowtype;
begin
 perform private.todo_lock_tree(p_task);select * into t from public.operation_tasks where id=p_task for update;
 if not found or t.assigned_by<>actor or not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Only the task assigner reviews this task';end if;
 if p_expected is not null and p_expected<>t.last_activity_id then raise exception 'This task has a new update. Refresh before reviewing.';end if;
 if nullif(btrim(p_note),'') is null or length(p_note)>10000 then raise exception 'A review note is required';end if;
 if p_action='approve' then
 if t.status<>'completion_requested' then raise exception 'The assignee must request completion first';end if;
 if exists(select 1 from public.operation_tasks where parent_task_id=t.id and status not in ('completed','cancelled')) then raise exception 'Linked delegated tasks remain open';end if;
 if t.work_order_id is not null and not exists(select 1 from public.work_orders where id=t.work_order_id and status='completed') then raise exception 'The linked Work Order is not approved as completed';end if;
 update public.operation_tasks set status='completed',progress=100,completed_at=now(),reviewed_by=actor where id=t.id;
 elsif p_action='return' and t.status='completion_requested' then update public.operation_tasks set status='in_progress',progress=least(progress,99),reviewed_by=actor where id=t.id;
 elsif p_action='cancel' and t.status not in ('completed','cancelled') then
 if exists(select 1 from public.operation_tasks where parent_task_id=t.id and status not in ('completed','cancelled')) then raise exception 'Close linked delegated tasks before cancelling';end if;
 if t.work_order_id is not null and not exists(select 1 from public.work_orders where id=t.work_order_id and (status='cancelled' or assigned_to is distinct from t.assigned_to)) then raise exception 'Cancel the linked Work Order through its own controlled workflow';end if;
 update public.operation_tasks set status='cancelled',reviewed_by=actor where id=t.id;
 else raise exception 'Invalid task review action';end if;
 perform private.todo_activity(t.id,actor,p_action,btrim(p_note));
end $$;
create function public.review_operation_task(p_task_id uuid,p_action text,p_note text,p_expected_activity_id bigint default null) returns void language sql security invoker set search_path='' as $$select private.todo_review(p_task_id,p_action,p_note,p_expected_activity_id)$$;
create function private.todo_seen(p_task uuid,p_through bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();latest bigint;begin
 if not private.todo_can_view(p_task,actor) then raise exception 'Task access denied';end if;
 select last_activity_id into latest from public.operation_tasks where id=p_task;
 insert into public.operation_task_reads(task_id,user_id,last_seen_activity_id) values(p_task,actor,least(coalesce(p_through,0),latest)) on conflict(task_id,user_id) do update set last_seen_activity_id=greatest(public.operation_task_reads.last_seen_activity_id,excluded.last_seen_activity_id);
end $$;
create function public.mark_operation_task_seen(p_task_id uuid,p_through_activity_id bigint) returns void language sql security invoker set search_path='' as $$select private.todo_seen(p_task_id,p_through_activity_id)$$;


revoke all on function private.todo_configure(uuid,jsonb),private.todo_create(jsonb),private.todo_update(uuid,text,integer,text,jsonb,bigint),private.todo_review(uuid,text,text,bigint),private.todo_seen(uuid,bigint) from public,anon,authenticated;
grant execute on function private.todo_configure(uuid,jsonb),private.todo_create(jsonb),private.todo_update(uuid,text,integer,text,jsonb,bigint),private.todo_review(uuid,text,text,bigint),private.todo_seen(uuid,bigint) to authenticated;
revoke all on function public.configure_task_governance(uuid,jsonb),public.task_assignment_candidates(),public.create_operation_task(jsonb),public.update_operation_task(uuid,text,integer,text,jsonb,bigint),public.review_operation_task(uuid,text,text,bigint),public.mark_operation_task_seen(uuid,bigint) from public,anon;
grant execute on function public.configure_task_governance(uuid,jsonb),public.task_assignment_candidates(),public.create_operation_task(jsonb),public.update_operation_task(uuid,text,integer,text,jsonb,bigint),public.review_operation_task(uuid,text,text,bigint),public.mark_operation_task_seen(uuid,bigint) to authenticated;

create function private.todo_sync_committee() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.active and new.personnel_category='shareholder' then
 insert into public.task_committee_members(user_id,active,appointed_by) values(new.id,true,auth.uid()) on conflict(user_id) do update set active=true,updated_at=now(),appointed_by=auth.uid();
 else update public.task_committee_members set active=false,updated_at=now(),appointed_by=auth.uid() where user_id=new.id;end if;
 return new;
end $$;
revoke all on function private.todo_sync_committee() from public,anon,authenticated;
create trigger sync_task_committee after insert or update of active,personnel_category on public.profiles for each row execute function private.todo_sync_committee();
