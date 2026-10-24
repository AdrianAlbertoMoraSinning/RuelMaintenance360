begin;
do $$
declare actor uuid;target uuid;blocked boolean;
begin
 select id into strict actor from public.profiles where active and personnel_category='ceo' limit 1;
 select p.id into strict target from public.profiles p where p.full_name like '[MOC]%' and p.active and p.role='technician' and not exists(select 1 from public.profiles r where r.corporate_manager_id=p.id and r.active) limit 1;
 perform public.admin_user_lifecycle(actor,target,'deactivate','',false);
 if not (select active from public.profiles where id=target) then raise exception 'Preflight mutated account';end if;
 perform public.admin_user_lifecycle(actor,target,'deactivate','',true);
 if (select active from public.profiles where id=target) then raise exception 'Deactivation did not apply';end if;
 perform public.admin_user_lifecycle(actor,target,'activate','',true);
 if not (select active from public.profiles where id=target) then raise exception 'Activation did not apply';end if;
 blocked:=false;begin perform public.admin_user_lifecycle(actor,actor,'deactivate','',false);exception when raise_exception then blocked:=true;end;if not blocked then raise exception 'Self deactivation accepted';end if;
 blocked:=false;begin perform public.admin_user_lifecycle(actor,target,'remove','wrong name',false);exception when raise_exception then blocked:=true;end;if not blocked then raise exception 'Removal accepted without exact confirmation';end if;
 if has_function_privilege('authenticated','public.admin_user_lifecycle(uuid,uuid,text,text,boolean)','execute') or has_function_privilege('anon','public.admin_user_lifecycle(uuid,uuid,text,text,boolean)','execute') then raise exception 'Lifecycle RPC exposed to client';end if;
end $$;
select 'user_lifecycle_passed' as result;
rollback;
