alter table public.personnel_onboarding
 add column phone text,
 add column position_title text,
 add column sms_sent_at timestamptz;
alter table public.personnel_onboarding add constraint onboarding_phone_e164 check(phone is null or phone ~ '^\+[1-9][0-9]{7,14}$');
create unique index personnel_onboarding_phone_unique on public.personnel_onboarding(phone) where phone is not null;

create or replace function private.complete_phone_onboarding_impl() returns void
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from auth.users where id=uid and phone_confirmed_at is not null and coalesce(encrypted_password,'')<>'') then
   raise exception 'Verify your phone and save your password first';
 end if;
 update public.personnel_onboarding set status='active',invitation_error=null
 where profile_id=uid and phone is not null;
end $$;
revoke all on function private.complete_phone_onboarding_impl() from public,anon;
grant execute on function private.complete_phone_onboarding_impl() to authenticated;
create or replace function public.complete_phone_onboarding() returns void
language sql security invoker set search_path='' as $$ select private.complete_phone_onboarding_impl() $$;
revoke all on function public.complete_phone_onboarding() from public,anon;
grant execute on function public.complete_phone_onboarding() to authenticated;
