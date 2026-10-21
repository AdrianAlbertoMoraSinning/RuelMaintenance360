-- Called only through the existing authenticated administrator Edge Function.
create or replace function public.admin_update_personnel_details(p_actor_id uuid,p_user_id uuid,p_full_name text,p_phone text,p_position_title text)
returns void language plpgsql security invoker set search_path='' as $$
declare v_name text:=btrim(p_full_name);v_phone text:=nullif(btrim(p_phone),'');v_position text:=nullif(btrim(p_position_title),'');
begin
 if not exists(select 1 from public.profiles where id=p_actor_id and active and role in ('super_admin','it_admin')) then raise exception 'Administrator access required';end if;
 if v_name is null or length(v_name)<1 or length(v_name)>200 then raise exception 'Full name is required (maximum 200 characters)';end if;
 if v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'Use an international contact number, such as +17806252210';end if;
 if length(v_position)>200 then raise exception 'Position title must be at most 200 characters';end if;
 update public.profiles set full_name=v_name,phone=v_phone,position_title=v_position where id=p_user_id;
 if not found then raise exception 'Personnel record not found';end if;
 update public.personnel_onboarding set full_name=v_name,phone=v_phone,position_title=v_position where profile_id=p_user_id;
end;
$$;
revoke all on function public.admin_update_personnel_details(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_update_personnel_details(uuid,uuid,text,text,text) to service_role;
