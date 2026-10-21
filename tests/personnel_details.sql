begin;
set local role service_role;
do $$
declare actor uuid; target uuid; before_profile public.profiles%rowtype; before_roster public.personnel_onboarding%rowtype;
begin
 select id into strict actor from public.profiles where active and role in ('super_admin','it_admin') order by id limit 1;
 select * into strict before_roster from public.personnel_onboarding where preferred_name='DJ';target:=before_roster.profile_id;
 select * into strict before_profile from public.profiles where id=target;
 perform public.admin_update_personnel_details(actor,target,'  Transient verification name  ',before_profile.phone,'Transient verification position');
 if not exists(select 1 from public.profiles where id=target and full_name='Transient verification name' and phone is not distinct from before_profile.phone and position_title='Transient verification position' and role=before_profile.role and corporate_manager_id is not distinct from before_profile.corporate_manager_id and active=before_profile.active and avatar_url is not distinct from before_profile.avatar_url) then raise exception 'Details missing or authority/identity changed';end if;
 if not exists(select 1 from public.personnel_onboarding where profile_id=target and full_name='Transient verification name' and position_title='Transient verification position' and preferred_name=before_roster.preferred_name and status=before_roster.status) then raise exception 'Roster not synchronized or activation changed';end if;
 begin perform public.admin_update_personnel_details(actor,target,'','bad-phone',null);raise exception 'Invalid details accepted';exception when others then if sqlerrm='Invalid details accepted' then raise;end if;end;
 begin perform public.admin_update_personnel_details(actor,target,'Valid name','bad-phone',null);raise exception 'Invalid phone accepted';exception when others then if sqlerrm='Invalid phone accepted' then raise;end if;end;
 begin perform public.admin_update_personnel_details(target,target,'Denied edit',null,null);raise exception 'Operator actor accepted';exception when others then if sqlerrm='Operator actor accepted' then raise;end if;end;
 if not exists(select 1 from public.profiles where id=target and full_name='Transient verification name') then raise exception 'Invalid update partially wrote';end if;
 if has_function_privilege('anon','public.admin_update_personnel_details(uuid,uuid,text,text,text)','EXECUTE') or has_function_privilege('authenticated','public.admin_update_personnel_details(uuid,uuid,text,text,text)','EXECUTE') then raise exception 'Direct client access exposed';end if;
end $$;
reset role;
rollback;
select 'PASS: personal name/contact/position edit; roster synchronization; role, supervisor, photo, account and activation preserved; invalid details rejected; administrator-only access. All changes rolled back.' as result;
