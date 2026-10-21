-- Chat is append-only evidence, and must not invalidate an unsent progress/review draft.
-- Every non-chat event still participates in optimistic concurrency checks.
create or replace function private.todo_update(p_task uuid,p_message text,p_progress integer,p_status text,p_checks jsonb,p_expected bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();t public.operation_tasks%rowtype;c jsonb;next_status text;next_progress integer;
begin
 perform private.todo_lock_tree(p_task);select * into t from public.operation_tasks where id=p_task for update;
 if not found or not exists(select 1 from public.profiles where id=actor and active) or actor not in (t.assigned_by,t.assigned_to) then raise exception 'You cannot update this task';end if;
 if p_expected is not null and (p_expected>t.last_activity_id or exists(select 1 from public.operation_task_activity e where e.task_id=t.id and e.id>p_expected and e.event_type not in ('comment','linked_comment'))) then raise exception 'This task has a new update. Refresh it before saving.';end if;
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

create or replace function private.todo_review(p_task uuid,p_action text,p_note text,p_expected bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();t public.operation_tasks%rowtype;
begin
 perform private.todo_lock_tree(p_task);select * into t from public.operation_tasks where id=p_task for update;
 if not found or t.assigned_by<>actor or not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Only the task assigner reviews this task';end if;
 if p_expected is not null and (p_expected>t.last_activity_id or exists(select 1 from public.operation_task_activity e where e.task_id=t.id and e.id>p_expected and e.event_type not in ('comment','linked_comment'))) then raise exception 'This task has a new update. Refresh before reviewing.';end if;
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

create or replace function private.todo_link(p_task_id uuid,p_parent_id uuid,p_expected_activity_id bigint) returns void language plpgsql security definer set search_path='' as $$
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
 if p_expected_activity_id is null or p_expected_activity_id>child.last_activity_id or exists(select 1 from public.operation_task_activity e where e.task_id=child.id and e.id>p_expected_activity_id and e.event_type not in ('comment','linked_comment')) then raise exception 'New activity arrived. Reload the task before linking';end if;
 if child.status in('completion_requested','completed','cancelled') or parent.status in('completion_requested','completed','cancelled') then raise exception 'Both tasks must be open';end if;
 if child.parent_task_id=p_parent_id then return;end if;
 if child.parent_task_id is not null then raise exception 'This task is already linked';end if;
 if parent.business_unit_id is not null and child.business_unit_id is distinct from parent.business_unit_id then raise exception 'Linked tasks must belong to the same business unit';end if;
 if exists(with recursive ancestors as (select id,parent_task_id from public.operation_tasks where id=p_parent_id union select t.id,t.parent_task_id from public.operation_tasks t join ancestors a on a.parent_task_id=t.id) select 1 from ancestors where id=p_task_id) then raise exception 'Task linking would create a cycle';end if;
 update public.operation_tasks set parent_task_id=p_parent_id where id=p_task_id;
 perform private.todo_activity(p_task_id,actor,'linked','Linked to TASK-'||parent.task_number||' — '||parent.title);
end $$;

create or replace view public.operation_task_inbox with(security_invoker=true) as
 select t.*,private.todo_person_label(t.id,t.assigned_to) as assignee_name,private.todo_person_label(t.id,t.assigned_by) as assigner_name,b.asset_code,b.name as asset_name,
 exists(select 1 from public.operation_task_activity e where e.task_id=t.id and e.id>coalesce(r.last_seen_activity_id,0) and e.actor_id is distinct from (select auth.uid()) and (e.event_type<>'comment' or e.id>coalesce(r.last_seen_message_id,0))) as has_updates,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id) as child_count,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id and c.status='completed') as children_completed,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id) as check_count,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id and c.done) as checks_done,
 (select coalesce(max(e.id),0) from public.operation_task_activity e where e.task_id=t.id and e.event_type not in ('comment','linked_comment')) as last_state_activity_id
 from public.operation_tasks t left join public.assets b on b.id=t.asset_id left join public.operation_task_reads r on r.task_id=t.id and r.user_id=(select auth.uid());
revoke all on public.operation_task_inbox from public,anon,authenticated;grant select on public.operation_task_inbox to authenticated,service_role;

