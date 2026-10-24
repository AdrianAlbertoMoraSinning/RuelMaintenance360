begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where active and personnel_category='ceo' limit 1),true);
-- Use an existing disposable training profile inside a rollback transaction; no Auth account or email is created.
do $$
declare target uuid;manager uuid;fleet uuid;ceo uuid:=auth.uid();old_role public.app_role;old_category public.personnel_category;obs uuid;
begin
 select id into strict manager from public.profiles where active and role='unit_supervisor' and full_name='Don McDonald' limit 1;
 select p.id,p.role,p.personnel_category into strict target,old_role,old_category from public.profiles p join public.user_unit_access a on a.user_id=p.id join public.business_units b on b.id=a.business_unit_id where b.code='CONC-PR' and p.active and p.full_name like '[MOC]%' and p.role in ('technician','operator','viewer') and not exists(select 1 from public.profiles child where child.corporate_manager_id=p.id and child.active) limit 1;
 select id into strict fleet from public.business_units where code='CONC-PR';
 update public.profiles set corporate_manager_id=manager,role='driver',position_title=null where id=target;
 if (select personnel_category from public.profiles where id=target)<>'driver' or (select position_title from public.profiles where id=target)<>'Fleet Driver' then raise exception 'Driver identity defaults missing';end if;
 if not exists(select 1 from public.production_drivers where user_id=target and fleet_unit_id=fleet and active) then raise exception 'Driver not auto-enrolled';end if;
 if not exists(select 1 from public.user_unit_access where user_id=target and business_unit_id=fleet and access_role='driver' and not can_edit and not can_approve) then raise exception 'Driver scope missing or elevated maintenance authority granted';end if;
 if not private.todo_can_assign(manager,target) then raise exception 'Supervisor cannot assign a task to driver';end if;
 perform set_config('request.jwt.claim.sub',target::text,true);
 if not (public.production_workspace()->>'driver')::boolean or jsonb_array_length(public.production_workspace()->'manage_units')<>0 then raise exception 'Driver workspace unavailable or privileged';end if;
 obs:=(public.submit_field_observation(gen_random_uuid(),fleet,null,'other','[QA rollback] Driver field report','normal')->>'observation_id')::uuid;
 if (select assigned_manager_id from public.field_observations where id=obs) is distinct from manager then raise exception 'Driver report did not route to manager';end if;
 perform set_config('request.jwt.claim.sub',ceo::text,true);
 update public.profiles set active=false where id=target;
 if exists(select 1 from public.production_drivers where user_id=target and active) then raise exception 'Inactive driver still enrolled';end if;
 update public.profiles set active=true where id=target;
 if not exists(select 1 from public.production_drivers where user_id=target and active) then raise exception 'Reactivated driver not enrolled';end if;
 update public.profiles set role=old_role,personnel_category=old_category where id=target;
 if exists(select 1 from public.production_drivers where user_id=target and active) then raise exception 'Role change away from driver retained enrollment';end if;
end $$;
select 'fleet_driver_role_passed' as result;
rollback;
