-- Each Business Unit has an independent, confidential CAD authorization threshold.
create table public.business_unit_approval_settings (
 business_unit_id uuid primary key references public.business_units(id) on delete cascade,
 approval_threshold numeric(14,2) check(approval_threshold>=0 and approval_threshold::text not in('NaN','Infinity','-Infinity')),
 currency text not null default 'CAD' check(currency='CAD'),
 updated_by uuid references public.profiles(id) on delete set null,
 updated_at timestamptz not null default now()
);
alter table public.business_unit_approval_settings enable row level security;
revoke all on public.business_unit_approval_settings from public,anon,authenticated;
grant select on public.business_unit_approval_settings to authenticated;
grant all on public.business_unit_approval_settings to service_role;
create policy unit_threshold_super_admin_read on public.business_unit_approval_settings for select to authenticated
using((select private.current_role())='super_admin'::public.app_role);
insert into public.business_unit_approval_settings(business_unit_id) select id from public.business_units;
comment on table public.business_unit_approval_settings is 'Confidential per-Business-Unit CAD thresholds. NULL blocks new authorization requests for that unit. Existing WO snapshots remain unchanged.';

create or replace function private.set_business_unit_approval_threshold_impl(p_business_unit_id uuid,p_threshold numeric)
returns void language plpgsql security definer set search_path=pg_catalog,public,private,auth
as $fn$
begin
 if auth.uid() is null or private.current_role() is distinct from 'super_admin'::public.app_role then raise exception 'Super Admin access required'; end if;
 if p_threshold is null or p_threshold::text in('NaN','Infinity','-Infinity') or p_threshold<0 or p_threshold>=1000000000000 or p_threshold<>round(p_threshold,2) then
  raise exception 'Enter a non-negative CAD amount with at most two decimal places'; end if;
 if not exists(select 1 from public.business_units where id=p_business_unit_id) then raise exception 'Business Unit not found'; end if;
 insert into public.business_unit_approval_settings(business_unit_id,approval_threshold,updated_by,updated_at)
 values(p_business_unit_id,p_threshold,auth.uid(),now())
 on conflict(business_unit_id) do update set approval_threshold=excluded.approval_threshold,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
end $fn$;
revoke all on function private.set_business_unit_approval_threshold_impl(uuid,numeric) from public,anon;
grant execute on function private.set_business_unit_approval_threshold_impl(uuid,numeric) to authenticated;
create or replace function public.set_business_unit_approval_threshold(p_business_unit_id uuid,p_threshold numeric)
returns void language sql set search_path=pg_catalog,private
as $fn$ select private.set_business_unit_approval_threshold_impl(p_business_unit_id,p_threshold) $fn$;
revoke all on function public.set_business_unit_approval_threshold(uuid,numeric) from public,anon;
grant execute on function public.set_business_unit_approval_threshold(uuid,numeric) to authenticated;

-- Reject legacy clients instead of silently writing a threshold no longer used.
create or replace function private.set_maintenance_approval_threshold_impl(p_threshold numeric)
returns void language plpgsql security definer set search_path=pg_catalog,public,private,auth
as $fn$ begin
 if auth.uid() is null or private.current_role() is distinct from 'super_admin'::public.app_role then raise exception 'Super Admin access required'; end if;
 raise exception 'Configure a separate threshold for each Business Unit in Administration';
end $fn$;
CREATE OR REPLACE FUNCTION private.request_work_order_execution_approval_impl(p_work_order_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'auth', 'pg_temp'
AS $function$
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
  select s.approval_threshold into threshold from public.business_unit_approval_settings s where s.business_unit_id=w.business_unit_id;
  if threshold is null then raise exception 'The Business Unit approval threshold has not been configured by a Super Admin'; end if;
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
CREATE OR REPLACE FUNCTION private.system_readiness_audit_impl()
 RETURNS TABLE(module text, check_code text, severity text, issue_count bigint, description text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'auth', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if private.current_role() not in ('super_admin','corporate_manager','it_admin','ohs_admin') then raise exception 'Corporate readiness audit is restricted to authorized corporate/IT/OHS roles'; end if;
  return query
  select 'Assets','ASSET_PRIMARY_RESPONSIBLE','warning',count(*)::bigint,'Active/standby assets without an active primary responsible person' from public.assets a where a.status in ('active','standby') and not exists(select 1 from public.asset_assignments aa where aa.asset_id=a.id and aa.responsibility='primary' and aa.active=true)
  union all select 'Assets','ASSET_SERIAL_MISSING','info',count(*)::bigint,'Active/standby assets without a serial number; relevant for OEM/diagnostic commissioning' from public.assets a where a.status in ('active','standby') and nullif(btrim(a.serial_number),'') is null
  union all select 'Maintenance','PM_DUE_CONFIGURATION','warning',count(*)::bigint,'Active auto-generated maintenance plans missing the applicable next-due value' from public.maintenance_plans mp where mp.active=true and coalesce(mp.auto_generate,false)=true and ((mp.trigger_basis='calendar' and mp.next_due_date is null) or (mp.trigger_basis='hours' and mp.next_due_hours is null) or (mp.trigger_basis='km' and mp.next_due_km is null) or (mp.trigger_basis='mixed' and mp.next_due_date is null and mp.next_due_hours is null and mp.next_due_km is null))
  union all select 'Work Orders','WO_EXECUTION_WITHOUT_APPROVAL','critical',count(*)::bigint,'Work orders in execution/completion states without approved execution authorization' from public.work_orders w where w.status in ('in_progress','waiting_parts','waiting_vendor','awaiting_approval','completed') and w.execution_approval_status<>'approved'
  union all select 'Work Orders','CRITICAL_CLOSED_WITHOUT_EVIDENCE','critical',count(*)::bigint,'Completed critical work orders without closure evidence' from public.work_orders w where w.priority='critical' and w.status='completed' and not exists(select 1 from public.work_order_evidence e where e.work_order_id=w.id)
  union all select 'Work Orders','CORRECTIVE_CLOSED_WITHOUT_DIAGNOSIS','critical',count(*)::bigint,'Completed corrective work orders missing diagnosis or corrective action' from public.work_orders w where w.type='corrective' and w.status='completed' and (nullif(btrim(w.diagnosis),'') is null or nullif(btrim(w.corrective_action),'') is null)
  union all select 'Inspections','FAILED_INSPECTION_WITHOUT_WO','critical',count(*)::bigint,'Failed inspections without a linked corrective work order' from public.inspections i where i.result='fail' and i.work_order_id is null
  union all select 'Inventory','NEGATIVE_STOCK','critical',count(*)::bigint,'Part/location balances below zero' from public.inventory_on_hand ioh where ioh.quantity_on_hand<0
  union all select 'Inventory','PART_RESPONSIBILITY','warning',count(*)::bigint,'Active parts without an assigned responsible person' from public.parts p where p.active=true and p.responsible_user_id is null
  union all select 'Inventory','WAREHOUSE_RESPONSIBILITY','warning',count(*)::bigint,'Active warehouses without an assigned responsible person' from public.inventory_warehouses w where w.active=true and w.responsible_user_id is null
  union all select 'Inventory','LOCATION_RESPONSIBILITY','warning',count(*)::bigint,'Active storage positions without an assigned responsible person' from public.inventory_locations l where l.active=true and l.responsible_user_id is null
  union all select 'Administration','APPROVAL_THRESHOLD_NOT_CONFIGURED','critical',(select count(*) from public.business_units b left join public.business_unit_approval_settings s on s.business_unit_id=b.id where s.approval_threshold is null)::bigint,'Business Units without a configured maintenance cost authorization threshold'
  union all select 'Administration','OPERATIONAL_USER_WITHOUT_MANAGER','warning',count(*)::bigint,'Active operational users without a Corporate Manager in the approval hierarchy' from public.profiles p where p.active=true and p.role not in ('super_admin','it_admin','corporate_manager','ohs_admin') and p.corporate_manager_id is null
  union all select 'OHS','PRIMARY_OHS_ADMIN_NOT_CONFIGURED','critical',case when private.primary_ohs_admin_user_id() is null then 1 else 0 end::bigint,'A primary OHS Administrator must be configured so every safety observation routes to OHS plus the reporter manager'
  union all select 'OHS','SAFETY_CASE_WITHOUT_OHS_ADMIN','critical',count(*)::bigint,'Open Safety Cases without an assigned OHS Administrator' from public.safety_cases s where s.status<>'closed' and s.assigned_safety_user_id is null
  union all select 'Observations','OBSERVATION_WITHOUT_MANAGER','warning',count(*)::bigint,'Open field observations without the reporter manager/supervisor assigned' from public.field_observations o where o.status not in ('resolved','closed_no_action','rejected') and o.assigned_manager_id is null
  union all select 'Observations','ACTION_WITHOUT_ASSIGNEE','warning',count(*)::bigint,'Open observation actions without an assigned responsible person' from public.field_observation_actions a where a.status<>'completed' and a.assigned_to is null
  union all select 'Safety','IMMEDIATE_DANGER_UNREVIEWED','critical',count(*)::bigint,'Immediate-danger Safety Cases that have not yet been reviewed' from public.safety_cases s where s.immediate_danger=true and s.status<>'closed' and s.reviewed_at is null
  union all select 'Safety','REGULATORY_REVIEW_WITHOUT_DISPOSITION','critical',count(*)::bigint,'Closed Safety Cases marked for regulatory review without documented disposition' from public.safety_cases s where s.status='closed' and s.regulatory_review_required=true and nullif(btrim(s.regulatory_disposition),'') is null
  union all select 'Safety','CLOSED_SAFETY_WITHOUT_SNAPSHOT','critical',count(*)::bigint,'Closed Safety Cases without a retained closure report snapshot' from public.safety_cases s where s.status='closed' and not exists(select 1 from public.safety_case_report_snapshots r where r.safety_case_id=s.id and r.snapshot_type='closure')
  union all select 'Diagnostics','GATEWAY_RESPONSIBILITY','warning',count(*)::bigint,'Active diagnostic gateways without a responsible person' from public.diagnostic_gateways g where g.active=true and g.responsible_user_id is null
  union all select 'Diagnostics','DEVICE_AGENT_PENDING','info',count(*)::bigint,'Active Device Connector agents still awaiting approval/commissioning' from public.diagnostic_device_agents d where d.active=true and d.status='pending';
end $function$;
notify pgrst,'reload schema';
