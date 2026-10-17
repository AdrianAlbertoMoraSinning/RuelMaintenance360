create or replace function private.post_inventory_movement_impl(p_part_id uuid,p_location_id uuid,p_type public.inventory_tx_type,p_quantity numeric,p_unit_cost numeric default null,p_reference text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,private,auth as $fn$
declare u uuid; c numeric; tx uuid;
begin
 if auth.uid() is null or private.current_role() is null then raise exception 'Active authentication required'; end if;
 select business_unit_id into u from public.inventory_locations where id=p_location_id and active;
 if u is null or not coalesce(private.can_edit_unit(u),false) then raise exception 'Not authorized for this stock location'; end if;
 if p_type::text not in ('receipt','adjustment') then raise exception 'Use the controlled Work Order or transfer workflow for this movement'; end if;
 if p_quantity is null or p_quantity=0 or (p_type='receipt' and p_quantity<0) then raise exception 'Invalid movement quantity'; end if;
 select standard_cost into c from public.parts where id=p_part_id and active;
 if not found then raise exception 'Part not found or inactive'; end if;
 if private.current_role()::text in ('super_admin','corporate_manager','unit_supervisor') then c:=coalesce(p_unit_cost,c); end if;
 insert into public.inventory_transactions(part_id,location_id,transaction_type,quantity,unit_cost,reference,notes,recorded_by)
 values(p_part_id,p_location_id,p_type,p_quantity,coalesce(c,0),p_reference,p_notes,auth.uid()) returning id into tx;
 return tx;
end $fn$;
revoke all on function private.post_inventory_movement_impl(uuid,uuid,public.inventory_tx_type,numeric,numeric,text,text) from public,anon;
grant execute on function private.post_inventory_movement_impl(uuid,uuid,public.inventory_tx_type,numeric,numeric,text,text) to authenticated;
create or replace function public.post_inventory_movement(p_part_id uuid,p_location_id uuid,p_type public.inventory_tx_type,p_quantity numeric,p_unit_cost numeric default null,p_reference text default null,p_notes text default null)
returns uuid language sql set search_path=pg_catalog,private as $fn$ select private.post_inventory_movement_impl(p_part_id,p_location_id,p_type,p_quantity,p_unit_cost,p_reference,p_notes) $fn$;
revoke all on function public.post_inventory_movement(uuid,uuid,public.inventory_tx_type,numeric,numeric,text,text) from public,anon;
grant execute on function public.post_inventory_movement(uuid,uuid,public.inventory_tx_type,numeric,numeric,text,text) to authenticated;
