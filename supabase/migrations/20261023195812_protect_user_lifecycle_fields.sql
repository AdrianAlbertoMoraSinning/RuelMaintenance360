create or replace function private.guard_profile_lifecycle()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if (new.active is distinct from old.active or new.removed_at is distinct from old.removed_at or new.removed_by is distinct from old.removed_by) and current_user not in ('postgres','service_role','supabase_auth_admin') then
  raise exception 'Use the protected administrator account action';
 end if;
 if old.removed_at is not null and (new.active or new.removed_at is distinct from old.removed_at or new.removed_by is distinct from old.removed_by) then raise exception 'Removed accounts cannot be reactivated';end if;
 return new;
end $$;
revoke all on function private.guard_profile_lifecycle() from public,anon,authenticated;
create trigger guard_profile_lifecycle before update on public.profiles for each row execute function private.guard_profile_lifecycle();
