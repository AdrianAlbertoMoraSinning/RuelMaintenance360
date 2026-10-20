-- Client decision 2026-10-20: CAD 500 inclusive, manager then designated CEO.
update public.business_unit_approval_settings set approval_threshold=500,updated_at=now(),updated_by=(select id from public.profiles where email='concrete@ruelconcreteltd.com');
create table public.personnel_onboarding (
 id uuid primary key default gen_random_uuid(), full_name text not null, preferred_name text,
 email text unique, role public.app_role not null default 'operator',
 reporting_manager_id uuid references public.profiles(id), business_unit_id uuid not null references public.business_units(id),
 profile_id uuid unique references public.profiles(id), status text not null default 'pending_contact' check(status in ('pending_contact','pending_invitation','invited','active')),
 invitation_error text, created_at timestamptz not null default now(), unique(full_name,business_unit_id)
);
alter table public.personnel_onboarding enable row level security;
revoke all on public.personnel_onboarding from public,anon,authenticated;
grant select on public.personnel_onboarding to authenticated;
grant all on public.personnel_onboarding to service_role;
create policy onboarding_admin_read on public.personnel_onboarding for select to authenticated using((select private.current_role()) in ('super_admin','it_admin') or reporting_manager_id=(select auth.uid()));
insert into public.personnel_onboarding(full_name,preferred_name,email,role,business_unit_id,status)
select n.full_name,n.nickname,n.email,n.role::public.app_role,b.id,n.status from public.business_units b cross join(values
 ('Don McDonald','Don','don@ruelconcreteltd.com','unit_supervisor','pending_invitation'),
 ('Julies Dawson','DJ',null,'operator','pending_contact'),('Tyrel Jhonson','Tyrel',null,'operator','pending_contact')) n(full_name,nickname,email,role,status) where b.code='CONC-PR';
update public.personnel_onboarding set reporting_manager_id=(select id from public.profiles where email='concrete@ruelconcreteltd.com') where email='don@ruelconcreteltd.com';
-- Preserve the explicit supervisor relationship before operator login contacts are supplied.
alter table public.personnel_onboarding add column supervisor_onboarding_id uuid references public.personnel_onboarding(id);
update public.personnel_onboarding set supervisor_onboarding_id=(select id from public.personnel_onboarding where email='don@ruelconcreteltd.com') where full_name in ('Julies Dawson','Tyrel Jhonson');
create table public.work_order_purchase_plans (
 request_id uuid primary key references public.work_order_part_requests(id) on delete cascade,
 preferred_vendor_id uuid references public.vendors(id), quoted_unit_cost numeric(14,2) check(quoted_unit_cost>=0 and quoted_unit_cost::text not in ('NaN','Infinity','-Infinity')),
 supplier_confirmed boolean not null default false, updated_at timestamptz not null default now()
);
alter table public.work_order_purchase_plans enable row level security;
revoke all on public.work_order_purchase_plans from public,anon,authenticated;
grant select,insert,update on public.work_order_purchase_plans to authenticated;
grant all on public.work_order_purchase_plans to service_role;
create policy purchase_plan_read on public.work_order_purchase_plans for select to authenticated using((select private.current_role()) in ('super_admin','corporate_manager','unit_supervisor') and exists(select 1 from public.work_order_part_requests r join public.work_orders w on w.id=r.work_order_id where r.id=request_id and private.can_access_unit(w.business_unit_id)));
create policy purchase_plan_insert on public.work_order_purchase_plans for insert to authenticated with check((select private.current_role()) in ('super_admin','corporate_manager','unit_supervisor') and exists(select 1 from public.work_order_part_requests r join public.work_orders w on w.id=r.work_order_id where r.id=request_id and private.can_edit_unit(w.business_unit_id) and w.execution_approval_status in ('draft','rejected')));
create policy purchase_plan_update on public.work_order_purchase_plans for update to authenticated using((select private.current_role()) in ('super_admin','corporate_manager','unit_supervisor') and exists(select 1 from public.work_order_part_requests r join public.work_orders w on w.id=r.work_order_id where r.id=request_id and private.can_edit_unit(w.business_unit_id) and w.execution_approval_status in ('draft','rejected'))) with check((select private.current_role()) in ('super_admin','corporate_manager','unit_supervisor') and exists(select 1 from public.work_order_part_requests r join public.work_orders w on w.id=r.work_order_id where r.id=request_id and private.can_edit_unit(w.business_unit_id) and w.execution_approval_status in ('draft','rejected')));
-- Quotes are preparation, invoices represent commitments. Unknown quotes stay NULL.
alter table public.work_orders add column costs_pending boolean not null default false;
CREATE OR REPLACE FUNCTION private.approve_work_order_execution_super_admin_impl(p_work_order_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare w public.work_orders%rowtype;
begin
  if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid() and active and personnel_category='ceo') then raise exception 'Only the designated CEO can approve this stage'; end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then raise exception 'Work order not found'; end if;
  if w.execution_approval_status <> 'pending_super_admin' or w.manager_approved_at is null then raise exception 'Manager approval must be completed first'; end if;
  update public.work_orders set corporate_approved_at=now(),corporate_approved_by=auth.uid(),execution_approval_notes=concat_ws(E'\n',nullif(execution_approval_notes,''),nullif(trim(p_notes),'')),execution_approval_status='approved',execution_approved_at=now(),execution_approved_by=auth.uid() where id=p_work_order_id;
  return 'approved';
end $function$;

CREATE OR REPLACE FUNCTION private.reject_work_order_execution_approval_impl(p_work_order_id uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare w public.work_orders%rowtype; allowed boolean:=false;
begin
  if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Rejection reason is required'; end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then raise exception 'Work order not found'; end if;
  if w.execution_approval_status='pending_manager' and w.manager_approver_id=auth.uid() then allowed:=true; end if;
  if w.execution_approval_status='pending_super_admin' and exists(select 1 from public.profiles where id=auth.uid() and active and personnel_category='ceo') then allowed:=true; end if;
  if not allowed then raise exception 'You are not the current approver'; end if;
  update public.work_orders set execution_approval_status='rejected',execution_rejection_reason=trim(p_reason),execution_approved_at=null,execution_approved_by=null where id=p_work_order_id;
  return 'rejected';
end $function$;

CREATE OR REPLACE FUNCTION private.approve_work_order_execution_manager_impl(p_work_order_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare w public.work_orders%rowtype; super_row record;
begin
  if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then raise exception 'Work order not found'; end if;
  if w.execution_approval_status <> 'pending_manager' then raise exception 'Work order is not awaiting manager approval'; end if;
  if w.manager_approver_id <> auth.uid() then raise exception 'Only the assigned employee manager can approve this stage'; end if;
  if w.corporate_approval_required then
    update public.work_orders set manager_approved_at=now(),manager_approved_by=auth.uid(),execution_approval_notes=nullif(trim(p_notes),''),execution_approval_status='pending_super_admin' where id=p_work_order_id;
    for super_row in select id from public.profiles where personnel_category='ceo' and active=true loop
      insert into public.notifications(user_id,business_unit_id,work_order_id,notification_type,severity,title,message,dedupe_key)
      values(super_row.id,w.business_unit_id,w.id,'corporate_approval_required',case when w.priority='critical' then 'critical' else 'high' end,'CEO approval required','Manager approval is complete. Estimated cost exceeds the confidential corporate authorization threshold.','wo-super-approval-'||w.id::text)
      on conflict (user_id,dedupe_key) where dedupe_key is not null do update set read_at=null,created_at=now(),message=excluded.message;
    end loop;
    return 'pending_super_admin';
  end if;
  update public.work_orders set manager_approved_at=now(),manager_approved_by=auth.uid(),execution_approval_notes=nullif(trim(p_notes),''),execution_approval_status='approved',execution_approved_at=now(),execution_approved_by=auth.uid() where id=p_work_order_id;
  return 'approved';
end $function$;

CREATE OR REPLACE FUNCTION private.submit_field_observation(p_client_draft_id uuid, p_business_unit_id uuid, p_asset_id uuid, p_observation_type text, p_description text, p_immediate_concern text DEFAULT 'normal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'private'
AS $function$
declare v_uid uuid:=(select auth.uid()); v_manager uuid; v_obs public.field_observations; v_case public.safety_cases; v_asset_unit uuid; v_ohs uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not (select private.can_access_unit(p_business_unit_id)) then raise exception 'No access to selected business unit'; end if;
  if private.current_role() is null then raise exception 'Active authentication required'; end if;
  if nullif(btrim(p_description),'') is null then raise exception 'Describe the observation'; end if;
  if p_immediate_concern in ('equipment_unsafe','immediate_safety') then p_observation_type:='safety'; end if;
  if p_observation_type not in ('equipment','safety','process','facility','other') then raise exception 'Invalid observation type'; end if;
  if p_immediate_concern not in ('normal','equipment_unsafe','immediate_safety') then raise exception 'Invalid immediate concern'; end if;
  if p_observation_type='equipment' and p_asset_id is null then raise exception 'Equipment observations require an asset'; end if;
  if p_asset_id is not null then select business_unit_id into v_asset_unit from public.assets where id=p_asset_id; if v_asset_unit is null or v_asset_unit<>p_business_unit_id then raise exception 'Asset does not belong to selected business unit'; end if; end if;
  if p_client_draft_id is not null then select * into v_obs from public.field_observations where client_draft_id=p_client_draft_id and reported_by=v_uid; if found then return jsonb_build_object('observation_id',v_obs.id,'safety_case_id',v_obs.safety_case_id,'idempotent',true); end if; end if;
  select corporate_manager_id into v_manager from public.profiles where id=v_uid and active;
  if v_manager is null then select supervisor_user_id into v_manager from public.business_units where id=p_business_unit_id; end if;
  insert into public.field_observations(client_draft_id,business_unit_id,asset_id,observation_type,description,immediate_concern,status,reported_by,assigned_manager_id)
  values(p_client_draft_id,p_business_unit_id,p_asset_id,p_observation_type,btrim(p_description),p_immediate_concern,'submitted',v_uid,v_manager) returning * into v_obs;
  insert into public.field_observation_history(observation_id,event_type,actor_id,to_status,details) values(v_obs.id,'submitted',v_uid,'submitted',jsonb_build_object('observation_type',p_observation_type,'immediate_concern',p_immediate_concern));
  if p_observation_type='safety' then
    v_ohs:=private.primary_ohs_admin_user_id();
    insert into public.safety_cases(observation_id,business_unit_id,asset_id,status,immediate_danger,regulatory_review_required,assigned_safety_user_id)
    values(v_obs.id,p_business_unit_id,p_asset_id,'triage',p_immediate_concern='immediate_safety',false,v_ohs) returning * into v_case;
    update public.field_observations set safety_case_id=v_case.id,status='under_review',updated_at=now() where id=v_obs.id returning * into v_obs;
    insert into public.field_observation_history(observation_id,event_type,actor_id,from_status,to_status,details) values(v_obs.id,'safety_case_created',v_uid,'submitted','under_review',jsonb_build_object('safety_case_id',v_case.id,'immediate_danger',v_case.immediate_danger,'ohs_admin_user_id',v_ohs));
  end if;
  perform private.notify_observation_recipients(v_obs.id,case when p_observation_type='safety' then 'New Safety Observation' else 'New Field Observation' end,case when p_observation_type='safety' then 'A field safety concern requires review by the reporting manager and OHS Administrator.' else 'A field observation requires manager triage.' end,case when p_immediate_concern='immediate_safety' then 'critical' when p_immediate_concern='equipment_unsafe' then 'warning' else 'info' end);
  return jsonb_build_object('observation_id',v_obs.id,'safety_case_id',v_obs.safety_case_id,'idempotent',false);
end $function$;

CREATE OR REPLACE FUNCTION private.request_observation_information(p_observation_id uuid, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'private'
AS $function$
declare v_old text; v_reporter uuid; v_unit uuid;
begin
  if nullif(btrim(p_message),'') is null then raise exception 'A message is required'; end if;
  if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  if not (select private.can_manage_observation(p_observation_id)) then raise exception 'Not authorized to review this observation'; end if;
  select status,reported_by,business_unit_id into v_old,v_reporter,v_unit from public.field_observations where id=p_observation_id for update;
  if exists(select 1 from public.field_observations where id=p_observation_id and resulting_work_order_id is not null) then raise exception 'Follow up on the linked Work Order'; end if;
  if v_old in ('resolved','closed_no_action','rejected') then raise exception 'Observation is already closed'; end if;
  update public.field_observations set status='information_requested',first_reviewed_at=coalesce(first_reviewed_at,now()),manager_disposition='information_requested',updated_at=now() where id=p_observation_id;
  insert into public.field_observation_comments(observation_id,author_id,comment_type,body) values(p_observation_id,(select auth.uid()),'information_request',btrim(p_message));
  insert into public.field_observation_history(observation_id,event_type,actor_id,from_status,to_status,details) values(p_observation_id,'information_requested',(select auth.uid()),v_old,'information_requested',jsonb_build_object('message',p_message));
  if exists(select 1 from public.notifications where user_id=v_reporter and dedupe_key='observation-reporter:'||p_observation_id::text) then
    update public.notifications set title='More information requested',message=p_message,severity='info',read_at=null,created_at=now() where user_id=v_reporter and dedupe_key='observation-reporter:'||p_observation_id::text;
  else
    insert into public.notifications(user_id,business_unit_id,observation_id,notification_type,severity,title,message,dedupe_key) values(v_reporter,v_unit,p_observation_id,'observation_information_requested','info','More information requested',p_message,'observation-reporter:'||p_observation_id::text);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION private.respond_to_observation_request(p_observation_id uuid, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'private'
AS $function$
declare v_obs public.field_observations;
begin
  if nullif(btrim(p_message),'') is null then raise exception 'A message is required'; end if;
  if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  select * into v_obs from public.field_observations where id=p_observation_id for update;
  if v_obs.status <> 'information_requested' then raise exception 'Observation is not awaiting reporter information'; end if;
  if v_obs.reported_by<>(select auth.uid()) then raise exception 'Only the reporter can respond'; end if;
  insert into public.field_observation_comments(observation_id,author_id,comment_type,body) values(p_observation_id,(select auth.uid()),'response',btrim(p_message));
  update public.field_observations set status='submitted',updated_at=now() where id=p_observation_id;
  insert into public.field_observation_history(observation_id,event_type,actor_id,from_status,to_status,details) values(p_observation_id,'reporter_response',(select auth.uid()),v_obs.status,'submitted',jsonb_build_object('message',p_message));
  perform private.notify_observation_recipients(p_observation_id,'Observation updated','The reporter added information and returned the observation for review.','info');
end $function$;

CREATE OR REPLACE FUNCTION private.issue_part_to_work_order_financial_impl(p_work_order_id uuid, p_part_id uuid, p_location_id uuid, p_quantity numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_request_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_unit uuid;v_loc_unit uuid;v_approval text;v_onhand numeric;v_cost numeric;v_id uuid;v_req public.work_order_part_requests%rowtype;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 if private.current_role()::text not in ('super_admin','corporate_manager','unit_supervisor') then p_unit_cost:=null; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 select business_unit_id,execution_approval_status into v_unit,v_approval from public.work_orders where id=p_work_order_id;
 if v_unit is null then raise exception 'Work order not found.'; end if;
 if not (select private.can_edit_unit(v_unit)) then raise exception 'Not authorized for this business unit.'; end if;
 if not exists(select 1 from public.work_orders where id=p_work_order_id and status='in_progress') then raise exception 'Start or resume the Work Order before consuming parts'; end if;
 if v_approval<>'approved' then raise exception 'Work order execution approval is required before issuing parts.'; end if;
 select business_unit_id into v_loc_unit from public.inventory_locations where id=p_location_id and active=true;
 if v_loc_unit is distinct from v_unit then raise exception 'Stock location must belong to the work order business unit.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_part_id::text||':'||p_location_id::text,0));
 select coalesce(sum(public.inventory_signed_quantity(transaction_type,quantity)),0) into v_onhand from public.inventory_transactions where part_id=p_part_id and location_id=p_location_id;
 if v_onhand<p_quantity then raise exception 'Insufficient inventory. Available %, requested %.',v_onhand,p_quantity; end if;
 select coalesce(p_unit_cost,standard_cost,0) into v_cost from public.parts where id=p_part_id and active=true;
 if v_cost is null then raise exception 'Part not found or inactive.'; end if;
 if p_request_id is not null then
   select * into v_req from public.work_order_part_requests where id=p_request_id and work_order_id=p_work_order_id and part_id=p_part_id for update;
   if not found then raise exception 'Part request does not match work order/part.'; end if;
 end if;
 insert into public.inventory_transactions(part_id,location_id,work_order_id,request_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by)
 values(p_part_id,p_location_id,p_work_order_id,p_request_id,'issue',p_quantity,v_cost,'WO #'||(select work_order_number from public.work_orders where id=p_work_order_id),p_notes,(select auth.uid())) returning id into v_id;
 if p_request_id is not null then
   update public.work_order_part_requests set quantity_issued=quantity_issued+p_quantity,status=case when quantity_issued+p_quantity>=greatest(quantity_approved,quantity_requested) then 'issued' when quantity_issued+p_quantity>0 then 'partially_issued' else status end,updated_at=now() where id=p_request_id;
 end if;
 return v_id;
end $function$;

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
  if w.costs_pending then raise exception 'Complete pending cost estimates before requesting authorization'; end if;
  if exists(select 1 from public.work_order_part_requests r left join public.work_order_purchase_plans q on q.request_id=r.id where r.work_order_id=w.id and r.quantity_to_purchase>0 and (q.preferred_vendor_id is null or q.quoted_unit_cost is null or not q.supplier_confirmed or r.preferred_location_id is null)) then raise exception 'Confirm supplier, price and destination for purchase needs before requesting approval'; end if;
  if w.estimated_cost < coalesce((select sum(r.quantity_requested*coalesce(q.quoted_unit_cost,p.standard_cost)) from public.work_order_part_requests r join public.parts p on p.id=r.part_id left join public.work_order_purchase_plans q on q.request_id=r.id where r.work_order_id=w.id),0)+coalesce((select sum(quoted_amount) from public.work_order_vendors where work_order_id=w.id),0) then raise exception 'WO estimate must cover planned parts and vendor quotes'; end if;
  mgr := private.resolve_execution_approver(coalesce((select assigned_manager_id from public.field_observations where id=w.source_observation_id),w.assigned_to));
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
CREATE OR REPLACE FUNCTION public.guard_work_order_resource_spend()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare wid uuid; approval text;
begin
  wid:=case when tg_op='DELETE' then old.work_order_id else new.work_order_id end;
  if wid is null then return case when tg_op='DELETE' then old else new end; end if;
  select execution_approval_status into approval from public.work_orders where id=wid;
  if tg_table_name='work_order_vendors' and tg_op<>'DELETE' then
    if approval not in ('draft','rejected') and tg_op='UPDATE' and new.quoted_amount is distinct from old.quoted_amount then raise exception 'Return the WO for revision before changing an authorized quote'; end if;
    if new.invoiced_amount is null then return new; end if;
  end if;
  if approval <> 'approved' then raise exception 'Parts/vendor commitments are blocked until work order authorization is approved'; end if;
  return case when tg_op='DELETE' then old else new end;
end $function$;


create or replace function private.workflow_notifications() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private,auth as $$
declare recipient uuid; req record; po uuid;
begin
 if new.execution_approval_status is distinct from old.execution_approval_status and new.execution_approval_status in ('rejected','approved') then
  for recipient in select distinct x from unnest(array[new.execution_requested_by,new.assigned_to,(select assigned_manager_id from public.field_observations where id=new.source_observation_id)]) x where x is not null loop
   insert into public.notifications(user_id,business_unit_id,work_order_id,notification_type,severity,title,message)
   values(recipient,new.business_unit_id,new.id,'approval_update','info',case when new.execution_approval_status='rejected' then 'WO returned for correction' else 'WO execution authorized' end,coalesce(new.execution_rejection_reason,'Authorization complete. Review materials and purchasing before execution.'));
  end loop;
 end if;
 if new.execution_approval_status='approved' and old.execution_approval_status is distinct from 'approved' then
  for req in select r.*, q.preferred_vendor_id,q.quoted_unit_cost,q.supplier_confirmed, greatest(r.quantity_to_purchase-coalesce((select sum(l.quantity_ordered-l.quantity_received) from public.inventory_purchase_order_lines l join public.inventory_purchase_orders p on p.id=l.purchase_order_id where l.work_order_part_request_id=r.id and p.status<>'cancelled'),0),0) outstanding from public.work_order_part_requests r left join public.work_order_purchase_plans q on q.request_id=r.id where r.work_order_id=new.id and r.quantity_to_purchase>0 loop
   if req.outstanding>0 and req.preferred_vendor_id is not null and req.quoted_unit_cost is not null and req.preferred_location_id is not null and req.supplier_confirmed then
    po:=gen_random_uuid();
    insert into public.inventory_purchase_orders(id,business_unit_id,vendor_id,po_number,created_by,notes) values(po,new.business_unit_id,req.preferred_vendor_id,'WO-'||new.work_order_number||'-'||substr(po::text,1,8),auth.uid(),'Auto-prepared after WO approval. Confirm dispatch before release.');
    insert into public.inventory_purchase_order_lines(purchase_order_id,part_id,work_order_part_request_id,destination_location_id,quantity_ordered,unit_cost) values(po,req.part_id,req.id,req.preferred_location_id,req.outstanding,req.quoted_unit_cost);
   end if;
  end loop;
 end if;
 if new.status='completed' and old.status is distinct from 'completed' then
  for recipient in select distinct x from unnest(array[new.requested_by,new.assigned_to,new.execution_requested_by,new.manager_approved_by,new.corporate_approved_by,new.approved_by,(select assigned_manager_id from public.field_observations where id=new.source_observation_id)]) x where x is not null loop
   insert into public.notifications(user_id,business_unit_id,work_order_id,notification_type,severity,title,message,dedupe_key) values(recipient,new.business_unit_id,new.id,'wo_completed','info','Work Order completed','WO #'||new.work_order_number||' has been completed. Review the retained work history.','wo-completed-'||new.id) on conflict(user_id,dedupe_key) where dedupe_key is not null do update set read_at=null,created_at=now();
  end loop;
  -- Safety stays open until the independent OHS investigation/verification closes it.
  update public.field_observations set status='resolved',resolved_at=now(),resolved_by=auth.uid(),resolution_notes='Linked Work Order completed' where id=new.source_observation_id and safety_case_id is null;
 end if;
 return new;
end $$;
revoke all on function private.workflow_notifications() from public,anon,authenticated;
create trigger workflow_notifications after update on public.work_orders for each row execute function private.workflow_notifications();
create or replace function private.receive_po_at_location(p_line_id uuid,p_quantity numeric,p_location_id uuid) returns uuid language plpgsql security definer set search_path=pg_catalog,public,private,auth as $$
declare l public.inventory_purchase_order_lines; u uuid; tx uuid;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 select * into strict l from public.inventory_purchase_order_lines where id=p_line_id for update;
 select business_unit_id into u from public.inventory_purchase_orders where id=l.purchase_order_id;
 if not private.can_edit_unit(u) then raise exception 'No edit access'; end if;
 if not exists(select 1 from public.inventory_locations where id=p_location_id and business_unit_id=u and active) then raise exception 'Choose an active storage position in this unit'; end if;
 update public.inventory_purchase_order_lines set destination_location_id=p_location_id where id=l.id;
 tx:=private.receive_purchase_order_line_financial_impl(p_line_id,p_quantity,null,null,'Physical placement confirmed by receiver');
 return tx;
end $$;
revoke all on function private.receive_po_at_location(uuid,numeric,uuid) from public,anon;
grant execute on function private.receive_po_at_location(uuid,numeric,uuid) to authenticated;
create function public.receive_po_at_location(p_line_id uuid,p_quantity numeric,p_location_id uuid) returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.receive_po_at_location(p_line_id,p_quantity,p_location_id)$$;
revoke all on function public.receive_po_at_location(uuid,numeric,uuid) from public,anon;
grant execute on function public.receive_po_at_location(uuid,numeric,uuid) to authenticated;
notify pgrst,'reload schema';

grant select(costs_pending),update(costs_pending) on public.work_orders to authenticated;
create or replace view public.work_orders_visible with(security_invoker=true,security_barrier=true) as
select t.id,
 t.business_unit_id,
 t.asset_id,
 t.maintenance_plan_id,
 t.work_order_number,
 t.type,
 t.status,
 t.priority,
 t.title,
 t.problem_description,
 t.diagnosis,
 t.corrective_action,
 t.requested_by,
 t.assigned_to,
 t.scheduled_for,
 t.started_at,
 t.completed_at,
 t.downtime_hours,
 t.labour_hours,
 (f.data->>'labour_cost')::numeric(12,2) as labour_cost,
 (f.data->>'parts_cost')::numeric(12,2) as parts_cost,
 (f.data->>'vendor_cost')::numeric(12,2) as vendor_cost,
 (f.data->>'other_cost')::numeric(12,2) as other_cost,
 t.meter_km,
 t.meter_hours,
 t.safety_notes,
 t.created_at,
 t.updated_at,
 t.completion_requested_at,
 t.completion_requested_by,
 t.approved_at,
 t.approved_by,
 t.approval_notes,
 (f.data->>'estimated_cost')::numeric(14,2) as estimated_cost,
 t.execution_approval_status,
 t.execution_requested_at,
 t.execution_requested_by,
 t.manager_approver_id,
 t.manager_approved_at,
 t.manager_approved_by,
 t.corporate_approval_required,
 (f.data->>'approval_threshold_snapshot')::numeric(14,2) as approval_threshold_snapshot,
 t.corporate_approved_at,
 t.corporate_approved_by,
 t.execution_approved_at,
 t.execution_approved_by,
 t.execution_approval_notes,
 t.execution_rejection_reason,
 t.planned_labour_hours,
 t.planning_class,
 t.maintenance_due_date,
 t.maintenance_due_hours,
 t.maintenance_due_km,
 t.maintenance_due_reason,
 t.maintenance_generated_at,
 t.source_observation_id,
 t.costs_pending
from public.work_orders t left join lateral (select private.financial_fields('work_orders',t.id) data offset 0) f on true;
revoke all on public.work_orders_visible from public,anon,authenticated;
grant select on public.work_orders_visible to authenticated,service_role;

create function public.guard_operator_work_order_write() returns trigger language plpgsql set search_path=pg_catalog,public,private as $$begin
 if (select private.current_role())='operator' then raise exception 'Operators submit observations; supervisors prepare Work Orders'; end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function public.guard_operator_work_order_write() from public,anon,authenticated;
create trigger guard_operator_work_order_write before insert or update or delete on public.work_orders for each row execute function public.guard_operator_work_order_write();
notify pgrst,'reload schema';

CREATE OR REPLACE FUNCTION public.reset_work_order_execution_approval_on_scope_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if old.execution_approval_status <> 'draft' and (
    new.assigned_to is distinct from old.assigned_to or new.business_unit_id is distinct from old.business_unit_id or new.asset_id is distinct from old.asset_id or
    new.type is distinct from old.type or new.priority is distinct from old.priority or new.title is distinct from old.title or new.problem_description is distinct from old.problem_description or
    new.estimated_cost is distinct from old.estimated_cost or new.costs_pending is distinct from old.costs_pending
  ) then
    new.execution_approval_status:='draft'; new.execution_requested_at:=null; new.execution_requested_by:=null; new.manager_approver_id:=null;
    new.manager_approved_at:=null; new.manager_approved_by:=null; new.corporate_approval_required:=false; new.approval_threshold_snapshot:=null;
    new.corporate_approved_at:=null; new.corporate_approved_by:=null; new.execution_approved_at:=null; new.execution_approved_by:=null; new.execution_rejection_reason:=null;
  end if;
  return new;
end $function$;


create function public.guard_part_requirement_revision() returns trigger language plpgsql set search_path=pg_catalog,public,private as $$
declare a text;
begin
 select execution_approval_status into a from public.work_orders where id=case when tg_op='DELETE' then old.work_order_id else new.work_order_id end for update;
 if a not in ('draft','rejected') then
  if tg_op in ('INSERT','DELETE') then raise exception 'Revise and reauthorize the WO before changing part requirements'; end if;
  if new.quantity_requested is distinct from old.quantity_requested or new.part_id is distinct from old.part_id or new.work_order_id is distinct from old.work_order_id then raise exception 'Revise and reauthorize the WO before changing part requirements'; end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function public.guard_part_requirement_revision() from public,anon,authenticated;
create trigger guard_part_requirement_revision before insert or update or delete on public.work_order_part_requests for each row execute function public.guard_part_requirement_revision();
