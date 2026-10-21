-- Operators must retain task visibility even when personnel directory RLS hides their supervisor.
-- Expose only names of participants/actors of a task that the current user may read.
create function private.todo_person_label(p_task uuid,p_person uuid) returns text language sql stable security definer set search_path='' as $$
 select p.full_name from public.profiles p where p.id=p_person and private.todo_can_view(p_task,auth.uid()) and (exists(select 1 from public.operation_tasks t where t.id=p_task and p_person in(t.assigned_by,t.assigned_to)) or exists(select 1 from public.operation_task_activity e where e.task_id=p_task and e.actor_id=p_person))
$$;
revoke all on function private.todo_person_label(uuid,uuid) from public,anon;grant execute on function private.todo_person_label(uuid,uuid) to authenticated;
create or replace view public.operation_task_inbox with(security_invoker=true) as
 select t.*,private.todo_person_label(t.id,t.assigned_to) as assignee_name,private.todo_person_label(t.id,t.assigned_by) as assigner_name,b.asset_code,b.name as asset_name,
 exists(select 1 from public.operation_task_activity e where e.task_id=t.id and e.id>coalesce(r.last_seen_activity_id,0) and e.actor_id is distinct from (select auth.uid())) as has_updates,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id) as child_count,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id and c.status='completed') as children_completed,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id) as check_count,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id and c.done) as checks_done
 from public.operation_tasks t left join public.assets b on b.id=t.asset_id left join public.operation_task_reads r on r.task_id=t.id and r.user_id=(select auth.uid());
revoke all on public.operation_task_inbox from public,anon,authenticated;grant select on public.operation_task_inbox to authenticated,service_role;
create view public.operation_task_activity_feed with(security_invoker=true) as select e.*,private.todo_person_label(e.task_id,e.actor_id) as actor_name from public.operation_task_activity e;
revoke all on public.operation_task_activity_feed from public,anon;grant select on public.operation_task_activity_feed to authenticated,service_role;
