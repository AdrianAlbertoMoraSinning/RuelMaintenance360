create or replace function private.can_review_observation(p_observation_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.field_observations o
 where o.id=p_observation_id
 and ((select private.current_role())<>'operator' or o.reported_by=(select auth.uid()))
 and (
 o.reported_by=(select auth.uid()) or o.assigned_manager_id=(select auth.uid())
 or (select private.current_role()) in ('super_admin','corporate_manager')
 or ((select private.current_role())='ohs_admin' and o.observation_type='safety')
 or exists(select 1 from public.safety_unit_responsibilities sr where sr.business_unit_id=o.business_unit_id and sr.user_id=(select auth.uid()) and sr.active)
 or (select private.can_access_unit(o.business_unit_id))
 ));
$$;
revoke all on function private.can_review_observation(uuid) from public,anon;
grant execute on function private.can_review_observation(uuid) to authenticated;
