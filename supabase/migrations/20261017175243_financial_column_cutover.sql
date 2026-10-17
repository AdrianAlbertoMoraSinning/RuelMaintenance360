-- Phase 2: apply only after the client reads *_visible and report email is upgraded.
revoke select on public.work_orders from public,anon,authenticated;
revoke select (labour_cost,parts_cost,vendor_cost,other_cost,estimated_cost,approval_threshold_snapshot) on public.work_orders from public,anon,authenticated;
grant select (id,business_unit_id,asset_id,maintenance_plan_id,work_order_number,type,status,priority,title,problem_description,diagnosis,corrective_action,requested_by,assigned_to,scheduled_for,started_at,completed_at,downtime_hours,labour_hours,meter_km,meter_hours,safety_notes,created_at,updated_at,completion_requested_at,completion_requested_by,approved_at,approved_by,approval_notes,execution_approval_status,execution_requested_at,execution_requested_by,manager_approver_id,manager_approved_at,manager_approved_by,corporate_approval_required,corporate_approved_at,corporate_approved_by,execution_approved_at,execution_approved_by,execution_approval_notes,execution_rejection_reason,planned_labour_hours,planning_class,maintenance_due_date,maintenance_due_hours,maintenance_due_km,maintenance_due_reason,maintenance_generated_at,source_observation_id) on public.work_orders to authenticated;
revoke select on public.maintenance_plans from public,anon,authenticated;
revoke select (estimated_cost) on public.maintenance_plans from public,anon,authenticated;
grant select (id,asset_id,plan_type,title,description,trigger_basis,interval_days,interval_km,interval_hours,procedure,active,next_due_date,next_due_km,next_due_hours,created_at,updated_at,auto_generate,lead_days,default_priority,assigned_to,planned_labour_hours,last_generated_at,last_generated_wo_id,last_completed_at) on public.maintenance_plans to authenticated;
revoke select on public.parts from public,anon,authenticated;
revoke select (standard_cost) on public.parts from public,anon,authenticated;
grant select (id,part_number,description,manufacturer,unit_of_measure,min_stock,critical_spare,active,created_at,updated_at,responsible_user_id,reorder_point,max_stock) on public.parts to authenticated;
revoke select on public.vendors from public,anon,authenticated;
revoke select (hourly_rate) on public.vendors from public,anon,authenticated;
grant select (id,name,contact_name,phone,email,address,specialties,active,rating,notes,created_at,updated_at) on public.vendors to authenticated;
revoke select on public.inventory_transactions from public,anon,authenticated;
revoke select (unit_cost) on public.inventory_transactions from public,anon,authenticated;
grant select (id,part_id,location_id,work_order_id,transaction_type,quantity,reference,notes,recorded_by,recorded_at,transfer_group_id,request_id) on public.inventory_transactions to authenticated;
revoke select on public.inventory_purchase_order_lines from public,anon,authenticated;
revoke select (unit_cost) on public.inventory_purchase_order_lines from public,anon,authenticated;
grant select (id,purchase_order_id,part_id,work_order_part_request_id,destination_location_id,quantity_ordered,quantity_received,notes,created_at,updated_at) on public.inventory_purchase_order_lines to authenticated;
revoke select on public.work_order_vendors from public,anon,authenticated;
revoke select (quoted_amount,invoiced_amount) on public.work_order_vendors from public,anon,authenticated;
grant select (work_order_id,vendor_id,response_hours,completion_rating,notes) on public.work_order_vendors to authenticated;
create or replace view public.inventory_kardex with(security_invoker=true) as  SELECT t.id,
    t.part_id,
    t.location_id,
    l.business_unit_id,
    l.warehouse_id,
    t.work_order_id,
    t.request_id,
    t.transaction_type,
    t.quantity,
    t.unit_cost,
    inventory_signed_quantity(t.transaction_type, t.quantity) AS signed_quantity,
    sum(inventory_signed_quantity(t.transaction_type, t.quantity)) OVER (PARTITION BY t.part_id, t.location_id ORDER BY t.recorded_at, t.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance,
    t.reference,
    t.notes,
    t.recorded_by,
    t.recorded_at,
    t.transfer_group_id
   FROM public.inventory_transactions_visible t
     JOIN inventory_locations l ON l.id = t.location_id;
create or replace view public.pm_forecast with(security_invoker=true) as  SELECT mp.id AS maintenance_plan_id,
    mp.asset_id,
    a.business_unit_id,
    a.asset_code,
    a.name AS asset_name,
    mp.title,
    mp.plan_type::text AS plan_type,
    mp.trigger_basis,
    mp.next_due_date,
    mp.next_due_hours,
    mp.next_due_km,
    mp.lead_days,
    mp.auto_generate,
    mp.planned_labour_hours,
    mp.estimated_cost,
        CASE
            WHEN mp.next_due_date IS NOT NULL THEN mp.next_due_date - (now() AT TIME ZONE 'America/Edmonton'::text)::date
            ELSE NULL::integer
        END AS days_to_due,
    a.hour_meter,
    a.odometer_km,
        CASE
            WHEN mp.next_due_hours IS NOT NULL AND a.hour_meter IS NOT NULL THEN mp.next_due_hours - a.hour_meter
            ELSE NULL::numeric
        END AS hours_to_due,
        CASE
            WHEN mp.next_due_km IS NOT NULL AND a.odometer_km IS NOT NULL THEN mp.next_due_km - a.odometer_km
            ELSE NULL::numeric
        END AS km_to_due
   FROM public.maintenance_plans_visible mp
     JOIN assets a ON a.id = mp.asset_id
  WHERE mp.active;
create or replace view public.inventory_stock_summary with(security_invoker=true) as  SELECT p.id AS part_id,
    p.part_number,
    p.description,
    p.manufacturer,
    p.unit_of_measure,
    p.standard_cost,
    p.min_stock,
    p.reorder_point,
    p.max_stock,
    p.critical_spare,
    p.responsible_user_id,
    l.id AS location_id,
    l.business_unit_id,
    l.warehouse_id,
    l.name AS location_name,
    l.position_code,
    l.aisle,
    l.rack,
    l.shelf,
    l.bin_code,
    l.responsible_user_id AS location_responsible_user_id,
    COALESCE(s.quantity_on_hand, 0::numeric) AS quantity_on_hand,
    COALESCE(r.quantity_reserved, 0::numeric) AS quantity_reserved,
    COALESCE(s.quantity_on_hand, 0::numeric) - COALESCE(r.quantity_reserved, 0::numeric) AS quantity_available,
    COALESCE(o.quantity_on_order, 0::numeric) AS quantity_on_order,
    o.next_expected_at,
    s.last_transaction_at,
        CASE
            WHEN (COALESCE(s.quantity_on_hand, 0::numeric) - COALESCE(r.quantity_reserved, 0::numeric) + COALESCE(o.quantity_on_order, 0::numeric)) <= GREATEST(p.reorder_point, p.min_stock) THEN 'reorder'::text
            ELSE 'ok'::text
        END AS stock_status
   FROM public.parts_visible p
     CROSS JOIN inventory_locations l
     LEFT JOIN inventory_on_hand s ON s.part_id = p.id AND s.location_id = l.id
     LEFT JOIN inventory_reservations r ON r.part_id = p.id AND r.location_id = l.id
     LEFT JOIN inventory_on_order o ON o.part_id = p.id AND o.location_id = l.id
  WHERE p.active = true AND l.active = true;
create or replace view public.inventory_usage_by_work_order with(security_invoker=true) as  SELECT w.id AS work_order_id,
    w.work_order_number,
    w.business_unit_id,
    w.asset_id,
    a.asset_code,
    a.name AS asset_name,
    t.part_id,
    p.part_number,
    p.description,
    sum(
        CASE
            WHEN t.transaction_type = 'issue'::inventory_tx_type THEN abs(t.quantity)
            WHEN t.transaction_type = 'return'::inventory_tx_type THEN - abs(t.quantity)
            ELSE 0::numeric
        END) AS net_quantity_used,
    sum(
        CASE
            WHEN t.transaction_type = 'issue'::inventory_tx_type THEN abs(t.quantity) * t.unit_cost
            WHEN t.transaction_type = 'return'::inventory_tx_type THEN (- abs(t.quantity)) * t.unit_cost
            ELSE 0::numeric
        END) AS net_material_cost,
    min(t.recorded_at) AS first_movement_at,
    max(t.recorded_at) AS last_movement_at
   FROM public.inventory_transactions_visible t
     JOIN public.work_orders_visible w ON w.id = t.work_order_id
     JOIN assets a ON a.id = w.asset_id
     JOIN public.parts_visible p ON p.id = t.part_id
  WHERE t.transaction_type = ANY (ARRAY['issue'::inventory_tx_type, 'return'::inventory_tx_type])
  GROUP BY w.id, w.work_order_number, w.business_unit_id, w.asset_id, a.asset_code, a.name, t.part_id, p.part_number, p.description;
create or replace view public.inventory_replenishment_report with(security_invoker=true) as  SELECT business_unit_id,
    part_id,
    part_number,
    description,
    unit_of_measure,
    sum(quantity_on_hand) AS on_hand,
    sum(quantity_reserved) AS reserved,
    sum(quantity_available) AS available,
    sum(quantity_on_order) AS on_order,
    max(reorder_point) AS reorder_point,
    max(max_stock) AS max_stock,
    max(standard_cost) AS standard_cost,
    sum(quantity_on_hand * standard_cost) AS inventory_value,
        CASE
            WHEN (sum(quantity_available) + sum(quantity_on_order)) <= max(GREATEST(reorder_point, min_stock)) THEN GREATEST(max(max_stock) - (sum(quantity_available) + sum(quantity_on_order)), 0::numeric)
            ELSE 0::numeric
        END AS suggested_order_quantity
   FROM inventory_stock_summary s
  GROUP BY business_unit_id, part_id, part_number, description, unit_of_measure;
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
revoke all on function private.issue_part_to_work_order_financial_impl(uuid,uuid,uuid,numeric,numeric,uuid,text) from public,anon;
grant execute on function private.issue_part_to_work_order_financial_impl(uuid,uuid,uuid,numeric,numeric,uuid,text) to authenticated;
CREATE OR REPLACE FUNCTION public.issue_part_to_work_order(p_work_order_id uuid, p_part_id uuid, p_location_id uuid, p_quantity numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_request_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select private.issue_part_to_work_order_financial_impl(p_work_order_id,p_part_id,p_location_id,p_quantity,p_unit_cost,p_request_id,p_notes) $wrapper$;
CREATE OR REPLACE FUNCTION private.return_part_from_work_order_financial_impl(p_work_order_id uuid, p_part_id uuid, p_location_id uuid, p_quantity numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_request_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_unit uuid;v_loc_unit uuid;v_issued numeric;v_returned numeric;v_cost numeric;v_id uuid;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 if private.current_role()::text not in ('super_admin','corporate_manager','unit_supervisor') then p_unit_cost:=null; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 select business_unit_id into v_unit from public.work_orders where id=p_work_order_id;
 if v_unit is null then raise exception 'Work order not found.'; end if;
 if not (select private.can_edit_unit(v_unit)) then raise exception 'Not authorized for this business unit.'; end if;
 select business_unit_id into v_loc_unit from public.inventory_locations where id=p_location_id and active=true;
 if v_loc_unit is distinct from v_unit then raise exception 'Stock location must belong to the work order business unit.'; end if;
 select coalesce(sum(case when transaction_type='issue' then abs(quantity) else 0 end),0),coalesce(sum(case when transaction_type='return' then abs(quantity) else 0 end),0) into v_issued,v_returned from public.inventory_transactions where work_order_id=p_work_order_id and part_id=p_part_id;
 if v_returned+p_quantity>v_issued then raise exception 'Return exceeds quantity previously issued to this work order.'; end if;
 select coalesce(p_unit_cost,standard_cost,0) into v_cost from public.parts where id=p_part_id and active=true;
 insert into public.inventory_transactions(part_id,location_id,work_order_id,request_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by)
 values(p_part_id,p_location_id,p_work_order_id,p_request_id,'return',p_quantity,v_cost,'WO return #'||(select work_order_number from public.work_orders where id=p_work_order_id),p_notes,(select auth.uid())) returning id into v_id;
 if p_request_id is not null then update public.work_order_part_requests set quantity_returned=quantity_returned+p_quantity,updated_at=now() where id=p_request_id; end if;
 return v_id;
end $function$;
revoke all on function private.return_part_from_work_order_financial_impl(uuid,uuid,uuid,numeric,numeric,uuid,text) from public,anon;
grant execute on function private.return_part_from_work_order_financial_impl(uuid,uuid,uuid,numeric,numeric,uuid,text) to authenticated;
CREATE OR REPLACE FUNCTION public.return_part_from_work_order(p_work_order_id uuid, p_part_id uuid, p_location_id uuid, p_quantity numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_request_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select private.return_part_from_work_order_financial_impl(p_work_order_id,p_part_id,p_location_id,p_quantity,p_unit_cost,p_request_id,p_notes) $wrapper$;
CREATE OR REPLACE FUNCTION private.transfer_inventory_part_financial_impl(p_part_id uuid, p_from_location_id uuid, p_to_location_id uuid, p_quantity numeric, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_from_unit uuid;v_to_unit uuid;v_onhand numeric;v_cost numeric;v_group uuid:=gen_random_uuid();
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 if p_from_location_id=p_to_location_id then raise exception 'Source and destination must be different.'; end if;
 select business_unit_id into v_from_unit from public.inventory_locations where id=p_from_location_id and active=true;
 select business_unit_id into v_to_unit from public.inventory_locations where id=p_to_location_id and active=true;
 if v_from_unit is null or v_to_unit is null then raise exception 'Invalid source or destination.'; end if;
 if not (select private.can_edit_unit(v_from_unit)) or not (select private.can_edit_unit(v_to_unit)) then raise exception 'Not authorized for both inventory locations.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_part_id::text||':'||p_from_location_id::text,0));
 select coalesce(sum(public.inventory_signed_quantity(transaction_type,quantity)),0) into v_onhand from public.inventory_transactions where part_id=p_part_id and location_id=p_from_location_id;
 if v_onhand<p_quantity then raise exception 'Insufficient source stock. Available %, requested %.',v_onhand,p_quantity; end if;
 select standard_cost into v_cost from public.parts where id=p_part_id and active=true;
 insert into public.inventory_transactions(part_id,location_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by,transfer_group_id) values(p_part_id,p_from_location_id,'transfer',-p_quantity,coalesce(v_cost,0),'Transfer out',p_notes,(select auth.uid()),v_group);
 insert into public.inventory_transactions(part_id,location_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by,transfer_group_id) values(p_part_id,p_to_location_id,'transfer',p_quantity,coalesce(v_cost,0),'Transfer in',p_notes,(select auth.uid()),v_group);
 return v_group;
end $function$;
revoke all on function private.transfer_inventory_part_financial_impl(uuid,uuid,uuid,numeric,text) from public,anon;
grant execute on function private.transfer_inventory_part_financial_impl(uuid,uuid,uuid,numeric,text) to authenticated;
CREATE OR REPLACE FUNCTION public.transfer_inventory_part(p_part_id uuid, p_from_location_id uuid, p_to_location_id uuid, p_quantity numeric, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select private.transfer_inventory_part_financial_impl(p_part_id,p_from_location_id,p_to_location_id,p_quantity,p_notes) $wrapper$;
CREATE OR REPLACE FUNCTION private.post_inventory_count_financial_impl(p_count_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.inventory_counts%rowtype;ln record;v_live numeric;v_delta numeric;v_cost numeric;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 select * into c from public.inventory_counts where id=p_count_id for update;
 if not found then raise exception 'Inventory count not found.'; end if;
 if c.status='posted' then raise exception 'Inventory count already posted.'; end if;
 if not (select private.can_edit_unit(c.business_unit_id)) then raise exception 'Not authorized for this business unit.'; end if;
 for ln in select * from public.inventory_count_lines where count_id=p_count_id loop
   if ln.actual_quantity is null then raise exception 'All count lines require an actual quantity before posting.'; end if;
   select coalesce(sum(public.inventory_signed_quantity(transaction_type,quantity)),0) into v_live from public.inventory_transactions where part_id=ln.part_id and location_id=c.location_id;
   v_delta:=ln.actual_quantity-v_live;
   update public.inventory_count_lines set system_quantity=v_live where id=ln.id;
   if v_delta<>0 then
     select standard_cost into v_cost from public.parts where id=ln.part_id;
     insert into public.inventory_transactions(part_id,location_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by) values(ln.part_id,c.location_id,'adjustment',v_delta,coalesce(v_cost,0),c.count_reference,'Physical inventory count adjustment',(select auth.uid()));
   end if;
 end loop;
 update public.inventory_counts set status='posted',approved_by=(select auth.uid()),posted_at=now() where id=p_count_id;
end $function$;
revoke all on function private.post_inventory_count_financial_impl(uuid) from public,anon;
grant execute on function private.post_inventory_count_financial_impl(uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.post_inventory_count(p_count_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select private.post_inventory_count_financial_impl(p_count_id) $wrapper$;
CREATE OR REPLACE FUNCTION private.receive_purchase_order_line_financial_impl(p_line_id uuid, p_quantity numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_line public.inventory_purchase_order_lines%rowtype; v_po public.inventory_purchase_orders%rowtype; v_req public.work_order_part_requests%rowtype; v_tx uuid; v_new_received numeric; v_work_order_id uuid;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 if private.current_role()::text not in ('super_admin','corporate_manager','unit_supervisor') then p_unit_cost:=null; end if;
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Receipt quantity must be greater than zero'; end if;
 select * into v_line from public.inventory_purchase_order_lines where id=p_line_id for update; if not found then raise exception 'Purchase Order line not found'; end if;
 select * into v_po from public.inventory_purchase_orders where id=v_line.purchase_order_id for update;
 if not private.can_edit_unit(v_po.business_unit_id) then raise exception 'No edit access to this business unit'; end if;
 if v_po.status not in ('approved','ordered','partial') then raise exception 'Purchase Order is not released for receiving'; end if;
 v_new_received:=v_line.quantity_received+p_quantity; if v_new_received>v_line.quantity_ordered then raise exception 'Receipt exceeds quantity ordered'; end if;
 if v_line.work_order_part_request_id is not null then select * into v_req from public.work_order_part_requests where id=v_line.work_order_part_request_id for update; v_work_order_id:=v_req.work_order_id; end if;
 insert into public.inventory_transactions(part_id,location_id,work_order_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by,request_id)
 values(v_line.part_id,v_line.destination_location_id,v_work_order_id,'receipt'::inventory_tx_type,p_quantity,coalesce(p_unit_cost,v_line.unit_cost),coalesce(p_reference,v_po.po_number),p_notes,auth.uid(),v_line.work_order_part_request_id) returning id into v_tx;
 update public.inventory_purchase_order_lines set quantity_received=v_new_received,unit_cost=coalesce(p_unit_cost,unit_cost),updated_at=now() where id=p_line_id;
 if v_line.work_order_part_request_id is not null then update public.work_order_part_requests set quantity_to_purchase=greatest(quantity_to_purchase-p_quantity,0),status=case when greatest(quantity_to_purchase-p_quantity,0)=0 then 'received' else 'purchase_required' end,updated_at=now() where id=v_req.id; end if;
 if exists(select 1 from public.inventory_purchase_order_lines where purchase_order_id=v_po.id and id<>p_line_id and quantity_received<quantity_ordered) or v_new_received<v_line.quantity_ordered then update public.inventory_purchase_orders set status='partial',updated_at=now() where id=v_po.id; else update public.inventory_purchase_orders set status='received',received_at=now(),updated_at=now() where id=v_po.id; end if;
 return v_tx;
end $function$;
revoke all on function private.receive_purchase_order_line_financial_impl(uuid,numeric,numeric,text,text) from public,anon;
grant execute on function private.receive_purchase_order_line_financial_impl(uuid,numeric,numeric,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.receive_purchase_order_line(p_line_id uuid, p_quantity numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select private.receive_purchase_order_line_financial_impl(p_line_id,p_quantity,p_unit_cost,p_reference,p_notes) $wrapper$;
CREATE OR REPLACE FUNCTION private.receive_part_for_work_order_request_financial_impl(p_request_id uuid, p_location_id uuid, p_quantity numeric, p_unit_cost numeric, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.work_order_part_requests%rowtype;v_unit uuid;v_loc_unit uuid;v_approval text;v_id uuid;v_remaining numeric;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 if private.current_role()::text not in ('super_admin','corporate_manager','unit_supervisor') then p_unit_cost:=null; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 select * into r from public.work_order_part_requests where id=p_request_id for update;
 if not found then raise exception 'Part request not found.'; end if;
 select business_unit_id,execution_approval_status into v_unit,v_approval from public.work_orders where id=r.work_order_id;
 if not (select private.can_edit_unit(v_unit)) then raise exception 'Not authorized for this business unit.'; end if;
 if v_approval<>'approved' then raise exception 'Work order authorization is required before purchasing/receiving committed parts.'; end if;
 select business_unit_id into v_loc_unit from public.inventory_locations where id=p_location_id and active=true;
 if v_loc_unit is distinct from v_unit then raise exception 'Receiving location must belong to the work order business unit.'; end if;
 insert into public.inventory_transactions(part_id,location_id,work_order_id,request_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by)
 values(r.part_id,p_location_id,r.work_order_id,r.id,'receipt',p_quantity,coalesce(p_unit_cost,(select standard_cost from public.parts where id=r.part_id),0),coalesce(nullif(trim(p_reference),''),'WO purchase receipt'),p_notes,(select auth.uid())) returning id into v_id;
 v_remaining:=greatest(0,r.quantity_to_purchase-p_quantity);
 update public.work_order_part_requests set quantity_to_purchase=v_remaining,status=case when v_remaining=0 then 'approved' else 'purchase_required' end,preferred_location_id=coalesce(preferred_location_id,p_location_id),updated_at=now() where id=r.id;
 return v_id;
end $function$;
revoke all on function private.receive_part_for_work_order_request_financial_impl(uuid,uuid,numeric,numeric,text,text) from public,anon;
grant execute on function private.receive_part_for_work_order_request_financial_impl(uuid,uuid,numeric,numeric,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.receive_part_for_work_order_request(p_request_id uuid, p_location_id uuid, p_quantity numeric, p_unit_cost numeric, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select private.receive_part_for_work_order_request_financial_impl(p_request_id,p_location_id,p_quantity,p_unit_cost,p_reference,p_notes) $wrapper$;
CREATE OR REPLACE FUNCTION private.generate_due_maintenance_work_orders_financial_impl(p_business_unit_id uuid DEFAULT NULL::uuid, p_as_of timestamp with time zone DEFAULT now())
 RETURNS TABLE(maintenance_plan_id uuid, work_order_id uuid, action text, due_reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare rec record;mpp record;v_wo uuid;v_reason text;v_status public.work_order_status;v_type public.work_order_type;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
  for rec in select mp.*,a.business_unit_id,a.asset_code,a.name asset_name from public.maintenance_plans mp join public.assets a on a.id=mp.asset_id where mp.active and mp.auto_generate and (p_business_unit_id is null or a.business_unit_id=p_business_unit_id) and private.can_edit_unit(a.business_unit_id) order by coalesce(mp.next_due_date,'9999-12-31'::date),mp.title
  loop
    v_reason:=public.maintenance_plan_due_reason(rec.id,p_as_of);if v_reason is null then continue;end if;
    select wo.id into v_wo from public.work_orders wo where wo.maintenance_plan_id=rec.id and wo.status not in ('completed','cancelled') order by wo.created_at desc limit 1;
    if v_wo is not null then maintenance_plan_id:=rec.id;work_order_id:=v_wo;action:='existing';due_reason:=v_reason;return next;continue;end if;
    v_status:=case when rec.assigned_to is null then 'open'::public.work_order_status else 'assigned'::public.work_order_status end;
    v_type:=case rec.plan_type::text when 'predictive' then 'predictive'::public.work_order_type when 'inspection' then 'inspection'::public.work_order_type else 'preventive'::public.work_order_type end;
    insert into public.work_orders(business_unit_id,asset_id,maintenance_plan_id,type,status,priority,title,problem_description,requested_by,assigned_to,scheduled_for,estimated_cost,planned_labour_hours,planning_class,maintenance_due_date,maintenance_due_hours,maintenance_due_km,maintenance_due_reason,maintenance_generated_at)
    values(rec.business_unit_id,rec.asset_id,rec.id,v_type,v_status,rec.default_priority,rec.title,concat('Automatically generated from maintenance plan. Due basis: ',v_reason,'. ',coalesce(rec.description,'')),auth.uid(),rec.assigned_to,case when rec.next_due_date is not null then rec.next_due_date::timestamptz else p_as_of end,rec.estimated_cost,rec.planned_labour_hours,'planned',rec.next_due_date,rec.next_due_hours,rec.next_due_km,v_reason,p_as_of) returning id into v_wo;
    for mpp in select planned_part.* from public.maintenance_plan_parts planned_part where planned_part.maintenance_plan_id=rec.id order by planned_part.created_at,planned_part.id loop
      perform public.add_work_order_part_requirement(v_wo,mpp.part_id,mpp.quantity,mpp.preferred_location_id,concat('Auto-planned from maintenance plan. ',coalesce(mpp.notes,'')));
    end loop;
    update public.maintenance_plans set last_generated_at=p_as_of,last_generated_wo_id=v_wo,updated_at=now() where id=rec.id;
    maintenance_plan_id:=rec.id;work_order_id:=v_wo;action:='created';due_reason:=v_reason;return next;
  end loop;
end $function$;
revoke all on function private.generate_due_maintenance_work_orders_financial_impl(uuid,timestamp with time zone) from public,anon;
grant execute on function private.generate_due_maintenance_work_orders_financial_impl(uuid,timestamp with time zone) to authenticated;
CREATE OR REPLACE FUNCTION public.generate_due_maintenance_work_orders(p_business_unit_id uuid DEFAULT NULL::uuid, p_as_of timestamp with time zone DEFAULT now())
 RETURNS TABLE(maintenance_plan_id uuid, work_order_id uuid, action text, due_reason text)
 LANGUAGE sql
 SET search_path=pg_catalog,private
 AS $wrapper$ select * from private.generate_due_maintenance_work_orders_financial_impl(p_business_unit_id,p_as_of) $wrapper$;
CREATE OR REPLACE FUNCTION public.maintenance_plan_due_reason(p_plan_id uuid, p_as_of timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  p record;
  a public.assets%rowtype;
  reasons text[] := array[]::text[];
  due_date date;
begin
  select active,asset_id,lead_days,next_due_date,next_due_hours,next_due_km into p from public.maintenance_plans where id=p_plan_id;
  if not found or not p.active then return null; end if;
  select * into a from public.assets where id=p.asset_id;
  if not found then return null; end if;
  due_date := (p_as_of at time zone 'America/Edmonton')::date + p.lead_days;
  if p.next_due_date is not null and p.next_due_date <= due_date then reasons := array_append(reasons,'calendar'); end if;
  if p.next_due_hours is not null and a.hour_meter is not null and a.hour_meter >= p.next_due_hours then reasons := array_append(reasons,'hours'); end if;
  if p.next_due_km is not null and a.odometer_km is not null and a.odometer_km >= p.next_due_km then reasons := array_append(reasons,'km'); end if;
  if array_length(reasons,1) is null then return null; end if;
  return array_to_string(reasons,',');
end $function$;
CREATE OR REPLACE FUNCTION public.add_work_order_part_requirement(p_work_order_id uuid, p_part_id uuid, p_quantity numeric, p_preferred_location_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_wo record;v_available numeric:=0;v_request_id uuid;v_to_purchase numeric:=0;v_location uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero'; end if;
  select status,business_unit_id,requested_by,assigned_to into v_wo from public.work_orders where id=p_work_order_id for update;
  if not found then raise exception 'Work Order not found'; end if;
  if v_wo.status in ('completed','cancelled') then raise exception 'Parts cannot be added to a completed/cancelled Work Order'; end if;
  if not (private.can_edit_unit(v_wo.business_unit_id) or v_wo.requested_by=auth.uid() or v_wo.assigned_to=auth.uid()) then raise exception 'You are not authorized to add parts to this Work Order'; end if;
  if not exists(select 1 from public.parts where id=p_part_id and active=true) then raise exception 'Part is not active'; end if;
  if p_preferred_location_id is not null and not exists(select 1 from public.inventory_locations where id=p_preferred_location_id and business_unit_id=v_wo.business_unit_id and active=true) then raise exception 'Preferred stock position must belong to the Work Order business unit'; end if;
  perform pg_advisory_xact_lock(hashtext(v_wo.business_unit_id::text||':'||p_part_id::text));
  v_location:=p_preferred_location_id;
  if v_location is null then
    select s.location_id into v_location from public.inventory_stock_summary s where s.business_unit_id=v_wo.business_unit_id and s.part_id=p_part_id order by s.quantity_available desc,s.location_name limit 1;
    if v_location is null then select l.id into v_location from public.inventory_locations l where l.business_unit_id=v_wo.business_unit_id and l.active order by l.name limit 1; end if;
  end if;
  if v_location is not null then select coalesce(sum(quantity_available),0) into v_available from public.inventory_stock_summary where business_unit_id=v_wo.business_unit_id and part_id=p_part_id and location_id=v_location; end if;
  v_to_purchase:=greatest(p_quantity-greatest(v_available,0),0);
  insert into public.work_order_part_requests(work_order_id,part_id,preferred_location_id,quantity_requested,quantity_approved,quantity_to_purchase,status,notes,requested_by,approved_by)
  values(p_work_order_id,p_part_id,v_location,p_quantity,p_quantity,v_to_purchase,case when v_to_purchase>0 then 'purchase_required' else 'approved' end,p_notes,auth.uid(),auth.uid()) returning id into v_request_id;
  return v_request_id;
end $function$;
notify pgrst,'reload schema';
