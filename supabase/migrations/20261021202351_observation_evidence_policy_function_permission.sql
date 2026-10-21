-- Storage policies invoke this existing, identity-scoped boolean helper as authenticated.
-- Keep it private and retain all observation and bucket RLS checks.
grant execute on function private.can_manage_observation(uuid) to authenticated;
