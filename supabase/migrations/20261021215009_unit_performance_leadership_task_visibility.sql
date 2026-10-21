-- Leadership can inspect unit task activity; assignment, messaging and approval commands retain their participant checks.
create or replace function private.todo_can_view(p_task uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 with recursive chain as(
  select id,parent_task_id,assigned_by,assigned_to from public.operation_tasks where id=p_task
  union all select t.id,t.parent_task_id,t.assigned_by,t.assigned_to from public.operation_tasks t join chain c on t.id=c.parent_task_id
 )
 select exists(select 1 from public.profiles p where p.id=p_user and p.active) and (
  exists(select 1 from chain where assigned_by=p_user or assigned_to=p_user)
  or exists(select 1 from public.operation_tasks t join public.profiles p on p.id=p_user and p.active where t.id=p_task and t.business_unit_id is not null and (
   p.role in ('super_admin','corporate_manager')
   or (p.role='unit_supervisor' and exists(select 1 from public.user_unit_access ua where ua.user_id=p_user and ua.business_unit_id=t.business_unit_id and ua.access_role='unit_supervisor'))
  ))
 )
$$;
revoke all on function private.todo_can_view(uuid,uuid) from public,anon;
grant execute on function private.todo_can_view(uuid,uuid) to authenticated,service_role;
