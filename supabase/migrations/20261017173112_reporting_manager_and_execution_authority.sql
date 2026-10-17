create or replace function private.enforce_profile_governance()
returns trigger language plpgsql security definer
set search_path to 'public','private','auth','pg_temp'
as $function$
declare
  v_manager_role app_role;
  v_manager_active boolean;
  v_cursor uuid;
  v_depth int := 0;
  v_other_superadmins int;
begin
  if tg_op='DELETE' then
    if old.role='super_admin' and old.active then
      select count(*) into v_other_superadmins from public.profiles p
      where p.id<>old.id and p.role='super_admin' and p.active;
      if v_other_superadmins=0 then raise exception 'The last active Super Admin cannot be deleted'; end if;
    end if;
    if exists(select 1 from public.profiles p where p.corporate_manager_id=old.id and p.active) then
      raise exception 'Reassign active direct reports before deleting this profile';
    end if;
    return old;
  end if;

  if tg_op='UPDATE' and old.role='super_admin' and old.active
     and (new.role<>'super_admin' or not new.active) then
    select count(*) into v_other_superadmins from public.profiles p
    where p.id<>old.id and p.role='super_admin' and p.active;
    if v_other_superadmins=0 then raise exception 'The last active Super Admin cannot be deactivated or demoted'; end if;
  end if;

  if tg_op='UPDATE' and old.role in ('super_admin','corporate_manager','unit_supervisor') and old.active
     and (not new.active or new.role not in ('super_admin','corporate_manager','unit_supervisor')) then
    if exists(select 1 from public.profiles p where p.corporate_manager_id=old.id and p.active) then
      raise exception 'Reassign active direct reports before deactivating or changing this reporting manager role';
    end if;
  end if;

  if new.corporate_manager_id is not null then
    if new.corporate_manager_id=new.id then raise exception 'A user cannot be their own Reporting Manager'; end if;
    select role,active into v_manager_role,v_manager_active from public.profiles where id=new.corporate_manager_id;
    if not found or not v_manager_active or v_manager_role not in ('corporate_manager','super_admin','unit_supervisor') then
      raise exception 'Reporting Manager must be an active Supervisor, Corporate Manager, or Super Admin';
    end if;
    v_cursor := new.corporate_manager_id;
    while v_cursor is not null loop
      v_depth := v_depth+1;
      if v_depth>50 then raise exception 'Reporting hierarchy depth exceeds control limit'; end if;
      if v_cursor=new.id then raise exception 'Reporting Manager assignment would create a hierarchy cycle'; end if;
      select corporate_manager_id into v_cursor from public.profiles where id=v_cursor;
    end loop;
  end if;
  return new;
end
$function$;

create or replace function private.resolve_execution_approver(p_assignee uuid)
returns uuid language plpgsql stable security definer
set search_path to 'public','private','auth','pg_temp'
as $function$
declare
  v_cursor uuid;
  v_parent uuid;
  v_active boolean;
  v_role app_role;
  v_seen uuid[] := array[p_assignee];
  v_depth int := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select corporate_manager_id,active into v_cursor,v_active from public.profiles where id=p_assignee;
  if not found or not coalesce(v_active,false) then raise exception 'Assigned user is inactive or missing'; end if;
  while v_cursor is not null loop
    v_depth := v_depth+1;
    if v_depth>50 or v_cursor=any(v_seen) then raise exception 'Invalid or cyclic reporting hierarchy'; end if;
    v_seen := array_append(v_seen,v_cursor);
    select role,active,corporate_manager_id into v_role,v_active,v_parent from public.profiles where id=v_cursor;
    if not found or not coalesce(v_active,false) then raise exception 'Reporting manager is inactive or missing'; end if;
    if v_role in ('corporate_manager','super_admin') then return v_cursor; end if;
    if v_role<>'unit_supervisor' then raise exception 'Invalid reporting manager role'; end if;
    v_cursor := v_parent;
  end loop;
  raise exception 'No active Corporate Manager or Super Admin found above the assigned employee';
end
$function$;
revoke all on function private.resolve_execution_approver(uuid) from public,anon,authenticated;
comment on function private.resolve_execution_approver(uuid) is
'Internal execution authorization routing. Follow the assignee reporting line through Supervisors to the first active Corporate Manager or Super Admin. Reporting to a Supervisor does not grant that Supervisor execution/cost approval authority.';

create or replace function private.request_work_order_execution_approval_impl(p_work_order_id uuid)
returns text language plpgsql security definer
set search_path to 'public','private','auth','pg_temp'
as $function$
declare
  w public.work_orders%rowtype;
  mgr uuid;
  threshold numeric;
begin
  if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then raise exception 'Work order not found'; end if;
  if not (private.can_edit_unit(w.business_unit_id) or w.requested_by=auth.uid() or w.assigned_to=auth.uid()) then
    raise exception 'Not authorized for this work order';
  end if;
  if w.assigned_to is null then raise exception 'Assign the work order before requesting approval'; end if;
  mgr := private.resolve_execution_approver(w.assigned_to);
  select corporate_approval_threshold into threshold from public.maintenance_approval_settings order by updated_at desc limit 1;
  if threshold is null then raise exception 'Corporate approval threshold has not been configured by a Super Admin'; end if;
  update public.work_orders set
    execution_approval_status='pending_manager',execution_requested_at=now(),execution_requested_by=auth.uid(),
    manager_approver_id=mgr,manager_approved_at=null,manager_approved_by=null,
    corporate_approval_required=(estimated_cost>threshold),approval_threshold_snapshot=threshold,
    corporate_approved_at=null,corporate_approved_by=null,execution_approved_at=null,execution_approved_by=null,
    execution_rejection_reason=null,execution_approval_notes=null
  where id=p_work_order_id;
  insert into public.notifications(user_id,business_unit_id,work_order_id,notification_type,severity,title,message,dedupe_key)
  values(mgr,w.business_unit_id,w.id,'approval_required',case when w.priority='critical' then 'critical' else 'high' end,
    'Work order approval required','A work order assigned to your reporting hierarchy requires authorization.','wo-manager-approval-'||w.id::text)
  on conflict (user_id,dedupe_key) where dedupe_key is not null
  do update set read_at=null,created_at=now(),message=excluded.message;
  return 'pending_manager';
end
$function$;
