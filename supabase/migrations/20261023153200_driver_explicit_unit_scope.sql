CREATE OR REPLACE FUNCTION private.validate_user_unit_access_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_role app_role;
  v_category personnel_category;
begin
  select role, personnel_category into v_role, v_category
  from public.profiles
  where id = new.user_id;

  if v_role is null then
    raise exception 'User profile not found for business-unit access.';
  end if;

  -- Shareholders are a deliberate exception: they may hold a global role
  -- (including super_admin) and also carry an explicit operational assignment
  -- to one or more Business Units.
  if v_category <> 'shareholder'::personnel_category
     and v_role not in ('unit_supervisor'::app_role,'technician'::app_role,'operator'::app_role,'driver'::app_role,'viewer'::app_role) then
    raise exception 'Role % uses corporate/global visibility and must not receive explicit business-unit access unless the profile is a shareholder.', v_role;
  end if;

  if new.access_role::text not in ('unit_supervisor','technician','operator','driver','viewer') then
    raise exception 'Invalid unit role % for business-unit access.', new.access_role;
  end if;

  return new;
end;
$function$
;
