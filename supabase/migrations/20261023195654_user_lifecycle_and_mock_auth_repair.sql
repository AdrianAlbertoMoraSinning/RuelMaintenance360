-- Repair only malformed training identities; preserve existing non-null tokens.
update auth.users u set confirmation_token=coalesce(u.confirmation_token,''),recovery_token=coalesce(u.recovery_token,''),email_change=coalesce(u.email_change,''),email_change_token_new=coalesce(u.email_change_token_new,'')
from public.profiles p where p.id=u.id and (p.full_name like '[MOC]%' or p.email like '%@training.ruel.invalid') and (u.confirmation_token is null or u.recovery_token is null or u.email_change is null or u.email_change_token_new is null);

alter table public.profiles add column removed_at timestamptz;
alter table public.profiles add column removed_by uuid references public.profiles(id);
alter table public.profiles add constraint removed_profile_inactive check(removed_at is null or not active);

-- Service-only entrypoint. The Edge Function authenticates the caller and passes
-- the verified actor id. Both preflight and commit independently check authority.
create or replace function public.admin_user_lifecycle(p_actor_id uuid,p_user_id uuid,p_action text,p_confirmation text default '',p_apply boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor public.profiles; target public.profiles; blockers text;
begin
 if current_user<>'service_role' and current_user<>'postgres' then raise exception 'Service access required';end if;
 select * into actor from public.profiles where id=p_actor_id for update;
 if actor.id is null or not actor.active or actor.removed_at is not null or actor.role not in ('super_admin','it_admin') then raise exception 'Active administrator required';end if;
 if p_action not in ('activate','deactivate','remove') or p_action is null then raise exception 'Invalid account action';end if;
 if p_action='remove' and actor.role<>'super_admin' then raise exception 'Only a Super Admin can remove users';end if;
 select * into target from public.profiles where id=p_user_id for update;
 if target.id is null then raise exception 'User not found';end if;
 if p_actor_id=p_user_id then raise exception 'You cannot change your own account status';end if;
 if target.removed_at is not null and p_action<>'remove' then raise exception 'This user was removed and cannot be activated. Contact a Super Admin';end if;
 if p_action='remove' and btrim(p_confirmation) is distinct from coalesce(nullif(target.full_name,''),target.email,target.id::text) then raise exception 'Type the exact user name to confirm removal';end if;
 if p_action<>'activate' and target.removed_at is null then
  if target.role='super_admin' and not exists(select 1 from public.profiles where role='super_admin' and active and id<>target.id) then raise exception 'The last active Super Admin cannot be disabled';end if;
  select string_agg(full_name,', ' order by full_name) into blockers from public.profiles where corporate_manager_id=target.id and active;
  if blockers is not null then raise exception 'Reassign active direct reports first: %',blockers;end if;
  if exists(select 1 from public.ohs_administration_settings where primary_ohs_admin_user_id=target.id) then raise exception 'Choose another Primary OHS Administrator before disabling this account';end if;
  if exists(select 1 from public.task_governance where ceo_user_id=target.id) then raise exception 'Choose another designated CEO before disabling this account';end if;
  if p_action='remove' then
   select string_agg(a.asset_code,', ' order by a.asset_code) into blockers from public.asset_assignments aa join public.assets a on a.id=aa.asset_id where aa.user_id=target.id and aa.active;
   if blockers is not null then raise exception 'Reassign current asset responsibilities first: %',blockers;end if;
   if exists(select 1 from public.production_loads where driver_id=target.id and status not in ('completed','cancelled')) then raise exception 'Complete or reassign pending deliveries before removing this user';end if;
  end if;
 end if;
 if p_apply then
  if p_action='remove' and target.removed_at is null then
   update public.profiles set active=false,removed_at=now(),removed_by=actor.id where id=target.id;
   update public.production_drivers set active=false where user_id=target.id;
   update public.safety_unit_responsibilities set active=false where user_id=target.id;
   insert into public.admin_security_events(actor_user_id,target_user_id,action) values(actor.id,target.id,'user_removed');
  elsif p_action<>'remove' then
   update public.profiles set active=(p_action='activate') where id=target.id;
   insert into public.admin_security_events(actor_user_id,target_user_id,action) values(actor.id,target.id,case when p_action='activate' then 'user_activated' else 'user_deactivated' end);
  end if;
 end if;
 return jsonb_build_object('active',p_action='activate','removed',p_action='remove','applied',p_apply);
end $$;
revoke all on function public.admin_user_lifecycle(uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.admin_user_lifecycle(uuid,uuid,text,text,boolean) to service_role;
