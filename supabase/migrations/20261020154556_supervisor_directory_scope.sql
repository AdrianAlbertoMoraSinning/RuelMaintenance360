-- Supervisors need the names of direct reports and their own manager, without a global directory grant.
create function private.supervisor_directory_visible(p_target uuid) returns boolean language sql stable security definer set search_path=pg_catalog,public,private,auth as $$
 select auth.uid() is not null and private.current_role()='unit_supervisor' and exists(
 select 1 from public.profiles p where p.id=p_target and p.active and (
 p.corporate_manager_id=auth.uid() or p.id=(select corporate_manager_id from public.profiles where id=auth.uid()) or exists(
 select 1 from public.user_unit_access mine join public.user_unit_access theirs using(business_unit_id) where mine.user_id=auth.uid() and theirs.user_id=p_target)))
$$;
revoke all on function private.supervisor_directory_visible(uuid) from public,anon;
grant execute on function private.supervisor_directory_visible(uuid) to authenticated;
create policy supervisor_directory_read on public.profiles for select to authenticated using((select private.supervisor_directory_visible(id)));
notify pgrst,'reload schema';
