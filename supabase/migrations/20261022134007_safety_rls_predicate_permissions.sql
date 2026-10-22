-- RLS policies call these existing identity-scoped predicates as the authenticated role.
-- Restore only the missing EXECUTE privileges; preserve both predicate bodies and row policies.
-- Anonymous callers remain excluded. No table write privileges or business approvals change.
revoke all on function private.can_access_safety_case(uuid), private.can_manage_safety_case(uuid) from public, anon;
grant execute on function private.can_access_safety_case(uuid), private.can_manage_safety_case(uuid) to authenticated;
