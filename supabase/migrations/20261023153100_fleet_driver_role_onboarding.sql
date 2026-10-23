-- A real Driver role gives personal field access and automatic Fleet enrollment.
create function private.driver_profile_defaults() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.role='driver' then
 if new.active and new.corporate_manager_id is null then raise exception 'Assign an active Reporting Manager before enabling the Driver role';end if;
 new.personnel_category:='driver';
 if nullif(btrim(new.position_title),'') is null then new.position_title:='Fleet Driver';end if;
 end if;
 return new;
end $$;
revoke all on function private.driver_profile_defaults() from public,anon,authenticated;
create trigger driver_profile_defaults before insert or update of role,active,corporate_manager_id on public.profiles for each row execute function private.driver_profile_defaults();

create function private.sync_driver_fleet_access() returns trigger language plpgsql security definer set search_path='' as $$
declare unit uuid;
begin
 if new.role='driver' then
 select id into strict unit from public.business_units where code='MOBILE-PR';
 if new.active then
 insert into public.user_unit_access(user_id,business_unit_id,access_role,can_edit,can_approve) values(new.id,unit,'driver',false,false)
 on conflict(user_id,business_unit_id) do update set access_role='driver',can_edit=false,can_approve=false;
 end if;
 insert into public.production_drivers(user_id,fleet_unit_id,active) values(new.id,unit,new.active)
 on conflict(user_id) do update set fleet_unit_id=excluded.fleet_unit_id,active=excluded.active;
 elsif tg_op='UPDATE' and old.role='driver' then
 update public.production_drivers set active=false where user_id=new.id;
 end if;
 return new;
end $$;
revoke all on function private.sync_driver_fleet_access() from public,anon,authenticated;
create trigger sync_driver_fleet_access after insert or update of role,active,corporate_manager_id on public.profiles for each row execute function private.sync_driver_fleet_access();
CREATE OR REPLACE FUNCTION private.todo_can_assign(p_actor uuid, p_target uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.profiles%rowtype;b public.profiles%rowtype;ceo uuid;
begin
 select * into a from public.profiles where id=p_actor and active;select * into b from public.profiles where id=p_target and active;
 if a.id is null or b.id is null or a.id=b.id then return false;end if;
 select ceo_user_id into ceo from public.task_governance where singleton;
 if exists(select 1 from public.task_committee_members where user_id=a.id and active) then return b.id=ceo;end if;
 if a.id=ceo then return b.personnel_category in ('manager','supervisor') or b.role in ('corporate_manager','unit_supervisor');end if;
 if b.corporate_manager_id is distinct from a.id then return false;end if;
 if a.personnel_category='manager' or a.role='corporate_manager' then return b.personnel_category='supervisor' or b.role='unit_supervisor';end if;
 if a.personnel_category='supervisor' or a.role='unit_supervisor' then return b.role in ('operator','technician','driver','viewer') and b.personnel_category not in ('ceo','shareholder','manager','supervisor');end if;
 return false;
end $function$
;
