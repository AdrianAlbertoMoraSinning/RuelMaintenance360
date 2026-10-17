-- Phase 1: additive read API. Raw-table grants are cut over only after the client deploy.
create or replace function private.financial_fields(p_table text,p_id uuid,p_other_id uuid default null)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,private,auth as $fn$
declare r public.app_role; u uuid; data jsonb;
begin
 if auth.uid() is null then return '{}'::jsonb; end if;
 r:=private.current_role();
 if r is null or r::text not in ('super_admin','corporate_manager','unit_supervisor') then return '{}'::jsonb; end if;
 case p_table
 when 'work_orders' then
 select t.business_unit_id,jsonb_build_object('labour_cost',t.labour_cost,'parts_cost',t.parts_cost,'vendor_cost',t.vendor_cost,'other_cost',t.other_cost,'estimated_cost',t.estimated_cost,'approval_threshold_snapshot',case when r='super_admin' then t.approval_threshold_snapshot else null end) into u,data from public.work_orders t  where t.id=p_id;
 when 'maintenance_plans' then
 select a.business_unit_id,jsonb_build_object('estimated_cost',t.estimated_cost) into u,data from public.maintenance_plans t join public.assets a on a.id=t.asset_id where t.id=p_id;
 when 'parts' then
 select null::uuid,jsonb_build_object('standard_cost',t.standard_cost) into u,data from public.parts t  where t.id=p_id;
 when 'vendors' then
 select null::uuid,jsonb_build_object('hourly_rate',t.hourly_rate) into u,data from public.vendors t  where t.id=p_id;
 when 'inventory_transactions' then
 select l.business_unit_id,jsonb_build_object('unit_cost',t.unit_cost) into u,data from public.inventory_transactions t join public.inventory_locations l on l.id=t.location_id where t.id=p_id;
 when 'inventory_purchase_order_lines' then
 select po.business_unit_id,jsonb_build_object('unit_cost',t.unit_cost) into u,data from public.inventory_purchase_order_lines t join public.inventory_purchase_orders po on po.id=t.purchase_order_id where t.id=p_id;
 when 'work_order_vendors' then
 select w.business_unit_id,jsonb_build_object('quoted_amount',t.quoted_amount,'invoiced_amount',t.invoiced_amount) into u,data from public.work_order_vendors t join public.work_orders w on w.id=t.work_order_id where t.work_order_id=p_id and t.vendor_id=p_other_id;
 else return '{}'::jsonb;
 end case;
 if data is null then return '{}'::jsonb; end if;
 if p_table in ('parts','vendors') then
  if r='unit_supervisor' and not exists(select 1 from public.user_unit_access where user_id=auth.uid()) then return '{}'::jsonb; end if;
 elsif u is null or not coalesce(private.can_access_unit(u),false) then return '{}'::jsonb;
 end if;
 return data;
end $fn$;
revoke all on function private.financial_fields(text,uuid,uuid) from public,anon;
grant execute on function private.financial_fields(text,uuid,uuid) to authenticated,service_role;
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
 t.source_observation_id
from public.work_orders t left join lateral (select private.financial_fields('work_orders',t.id) data offset 0) f on true;
revoke all on public.work_orders_visible from public,anon,authenticated;
grant select on public.work_orders_visible to authenticated,service_role;
create or replace view public.maintenance_plans_visible with(security_invoker=true,security_barrier=true) as
select t.id,
 t.asset_id,
 t.plan_type,
 t.title,
 t.description,
 t.trigger_basis,
 t.interval_days,
 t.interval_km,
 t.interval_hours,
 t.procedure,
 t.active,
 t.next_due_date,
 t.next_due_km,
 t.next_due_hours,
 t.created_at,
 t.updated_at,
 t.auto_generate,
 t.lead_days,
 t.default_priority,
 t.assigned_to,
 (f.data->>'estimated_cost')::numeric as estimated_cost,
 t.planned_labour_hours,
 t.last_generated_at,
 t.last_generated_wo_id,
 t.last_completed_at
from public.maintenance_plans t left join lateral (select private.financial_fields('maintenance_plans',t.id) data offset 0) f on true;
revoke all on public.maintenance_plans_visible from public,anon,authenticated;
grant select on public.maintenance_plans_visible to authenticated,service_role;
create or replace view public.parts_visible with(security_invoker=true,security_barrier=true) as
select t.id,
 t.part_number,
 t.description,
 t.manufacturer,
 t.unit_of_measure,
 (f.data->>'standard_cost')::numeric(12,2) as standard_cost,
 t.min_stock,
 t.critical_spare,
 t.active,
 t.created_at,
 t.updated_at,
 t.responsible_user_id,
 t.reorder_point,
 t.max_stock
from public.parts t left join lateral (select private.financial_fields('parts',t.id) data offset 0) f on true;
revoke all on public.parts_visible from public,anon,authenticated;
grant select on public.parts_visible to authenticated,service_role;
create or replace view public.vendors_visible with(security_invoker=true,security_barrier=true) as
select t.id,
 t.name,
 t.contact_name,
 t.phone,
 t.email,
 t.address,
 t.specialties,
 (f.data->>'hourly_rate')::numeric(12,2) as hourly_rate,
 t.active,
 t.rating,
 t.notes,
 t.created_at,
 t.updated_at
from public.vendors t left join lateral (select private.financial_fields('vendors',t.id) data offset 0) f on true;
revoke all on public.vendors_visible from public,anon,authenticated;
grant select on public.vendors_visible to authenticated,service_role;
create or replace view public.inventory_transactions_visible with(security_invoker=true,security_barrier=true) as
select t.id,
 t.part_id,
 t.location_id,
 t.work_order_id,
 t.transaction_type,
 t.quantity,
 (f.data->>'unit_cost')::numeric(12,2) as unit_cost,
 t.reference,
 t.notes,
 t.recorded_by,
 t.recorded_at,
 t.transfer_group_id,
 t.request_id
from public.inventory_transactions t left join lateral (select private.financial_fields('inventory_transactions',t.id) data offset 0) f on true;
revoke all on public.inventory_transactions_visible from public,anon,authenticated;
grant select on public.inventory_transactions_visible to authenticated,service_role;
create or replace view public.inventory_purchase_order_lines_visible with(security_invoker=true,security_barrier=true) as
select t.id,
 t.purchase_order_id,
 t.part_id,
 t.work_order_part_request_id,
 t.destination_location_id,
 t.quantity_ordered,
 t.quantity_received,
 (f.data->>'unit_cost')::numeric as unit_cost,
 t.notes,
 t.created_at,
 t.updated_at
from public.inventory_purchase_order_lines t left join lateral (select private.financial_fields('inventory_purchase_order_lines',t.id) data offset 0) f on true;
revoke all on public.inventory_purchase_order_lines_visible from public,anon,authenticated;
grant select on public.inventory_purchase_order_lines_visible to authenticated,service_role;
create or replace view public.work_order_vendors_visible with(security_invoker=true,security_barrier=true) as
select t.work_order_id,
 t.vendor_id,
 (f.data->>'quoted_amount')::numeric(12,2) as quoted_amount,
 (f.data->>'invoiced_amount')::numeric(12,2) as invoiced_amount,
 t.response_hours,
 t.completion_rating,
 t.notes
from public.work_order_vendors t left join lateral (select private.financial_fields('work_order_vendors',t.work_order_id,t.vendor_id) data offset 0) f on true;
revoke all on public.work_order_vendors_visible from public,anon,authenticated;
grant select on public.work_order_vendors_visible to authenticated,service_role;
