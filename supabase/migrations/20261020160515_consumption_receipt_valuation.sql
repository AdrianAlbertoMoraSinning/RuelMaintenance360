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
 select coalesce((select sum(public.inventory_signed_quantity(transaction_type,quantity)*unit_cost)/nullif(v_onhand,0) from public.inventory_transactions where part_id=p_part_id and location_id=p_location_id),standard_cost,0) into v_cost from public.parts where id=p_part_id and active=true;
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
 select business_unit_id into v_unit from public.work_orders where id=p_work_order_id for update;
 if exists(select 1 from public.work_orders where id=p_work_order_id and status in ('completed','cancelled')) then raise exception 'Closed Work Orders cannot receive stock returns'; end if;
 if v_unit is null then raise exception 'Work order not found.'; end if;
 if not (select private.can_edit_unit(v_unit)) then raise exception 'Not authorized for this business unit.'; end if;
 select business_unit_id into v_loc_unit from public.inventory_locations where id=p_location_id and active=true;
 if v_loc_unit is distinct from v_unit then raise exception 'Stock location must belong to the work order business unit.'; end if;
 select coalesce(sum(case when transaction_type='issue' then abs(quantity) else 0 end),0),coalesce(sum(case when transaction_type='return' then abs(quantity) else 0 end),0) into v_issued,v_returned from public.inventory_transactions where work_order_id=p_work_order_id and part_id=p_part_id;
 if v_returned+p_quantity>v_issued then raise exception 'Return exceeds quantity previously issued to this work order.'; end if;
 select sum(case when transaction_type='issue' then abs(quantity)*unit_cost when transaction_type='return' then -abs(quantity)*unit_cost else 0 end)/nullif(v_issued-v_returned,0) into v_cost from public.inventory_transactions where work_order_id=p_work_order_id and part_id=p_part_id;
 if v_cost is null then raise exception 'No issued value is available for return'; end if;
 insert into public.inventory_transactions(part_id,location_id,work_order_id,request_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by)
 values(p_part_id,p_location_id,p_work_order_id,p_request_id,'return',p_quantity,v_cost,'WO return #'||(select work_order_number from public.work_orders where id=p_work_order_id),p_notes,(select auth.uid())) returning id into v_id;
 if p_request_id is not null then update public.work_order_part_requests set quantity_returned=quantity_returned+p_quantity,updated_at=now() where id=p_request_id; end if;
 return v_id;
end $function$;

