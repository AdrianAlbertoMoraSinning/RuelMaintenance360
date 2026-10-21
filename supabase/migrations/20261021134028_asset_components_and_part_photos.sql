alter table public.asset_part_compatibility
 add column installed_quantity numeric not null default 0 check(installed_quantity>=0 and installed_quantity<1000000000),
 add column relationship_type text not null default 'compatible' check(relationship_type in ('installed','compatible')),
 add column component_system text,
 add column installation_position text,
 add constraint installed_component_positive_quantity check(relationship_type<>'installed' or installed_quantity>0);

create view public.asset_part_availability with (security_invoker=true) as
select c.asset_id,a.business_unit_id,c.part_id,c.relationship_type,c.installed_quantity,c.component_system,c.installation_position,c.preferred,c.notes,
 p.part_number,p.description,p.manufacturer,p.unit_of_measure,p.critical_spare,
 coalesce(s.on_hand,0) as quantity_on_hand,coalesce(s.reserved,0) as quantity_reserved,
 coalesce(s.available,0) as quantity_available,coalesce(s.on_order,0) as quantity_on_order,s.expected_at as next_expected_at,
 coalesce(s.positions,'[]'::jsonb) as positions
from public.asset_part_compatibility c join public.assets a on a.id=c.asset_id join public.parts_visible p on p.id=c.part_id
left join lateral (
 select sum(x.quantity_on_hand) as on_hand,sum(x.quantity_reserved) as reserved,sum(x.quantity_available) as available,sum(x.quantity_on_order) as on_order,min(x.next_expected_at) as expected_at,
 jsonb_agg(jsonb_build_object('location_id',x.location_id,'location_name',x.location_name,'position_code',x.position_code,'available',x.quantity_available,'on_hand',x.quantity_on_hand,'reserved',x.quantity_reserved,'on_order',x.quantity_on_order,'expected_at',x.next_expected_at) order by x.location_name) as positions
 from public.inventory_stock_summary x where x.business_unit_id=a.business_unit_id and x.part_id=c.part_id
) s on true where p.active;
revoke all on public.asset_part_availability from public,anon;
grant select on public.asset_part_availability to authenticated,service_role;

create function public.add_asset_parts_to_plan(p_plan_id uuid,p_items jsonb) returns integer language plpgsql security invoker set search_path='' as $$
declare plan_asset uuid; unit_id uuid; item jsonb; part uuid; qty numeric; added integer:=0;
begin
 if (select auth.uid()) is null then raise exception 'Authentication required';end if;
 select p.asset_id,a.business_unit_id into plan_asset,unit_id from public.maintenance_plans p join public.assets a on a.id=p.asset_id where p.id=p_plan_id and p.active for update of p;
 if not found or not private.can_edit_unit(unit_id) then raise exception 'Plan editing permission required';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>100 then raise exception 'Select between 1 and 100 asset parts';end if;
 if (select count(*)<>count(distinct v->>'part_id') from jsonb_array_elements(p_items) v) then raise exception 'Select each part only once';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  part:=(item->>'part_id')::uuid;qty:=(item->>'quantity')::numeric;
  if qty is null or qty<=0 or not(qty<1000000000) then raise exception 'Required quantity must be positive and finite';end if;
  if not exists(select 1 from public.asset_part_compatibility c join public.parts p on p.id=c.part_id where c.asset_id=plan_asset and c.part_id=part and p.active) then raise exception 'Part is not linked to this asset';end if;
  if exists(select 1 from public.maintenance_plan_parts where maintenance_plan_id=p_plan_id and part_id=part) then raise exception 'Part already exists in this plan; edit its existing requirement';end if;
  if nullif(item->>'location_id','') is not null and not exists(select 1 from public.inventory_locations where id=(item->>'location_id')::uuid and business_unit_id=unit_id and active) then raise exception 'Stock position must belong to the asset unit';end if;
  insert into public.maintenance_plan_parts(maintenance_plan_id,part_id,quantity,preferred_location_id,notes) values(p_plan_id,part,qty,nullif(item->>'location_id','')::uuid,'Selected from the asset component list; required quantity confirmed for this maintenance.');
  added:=added+1;
 end loop;
 return added;
end $$;
revoke all on function public.add_asset_parts_to_plan(uuid,jsonb) from public,anon;
grant execute on function public.add_asset_parts_to_plan(uuid,jsonb) to authenticated;

create table public.part_photos (
 id uuid primary key default gen_random_uuid(),
 part_id uuid not null references public.parts(id) on delete cascade,
 storage_path text not null unique,
 caption text not null default '' check(length(caption)<=500),
 uploaded_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 check(split_part(storage_path,'/',1)=part_id::text),
 check(storage_path ~ '^[a-f0-9-]{36}/[a-f0-9-]{36}\.(jpg|png|webp)$')
);
create index part_photos_part on public.part_photos(part_id,created_at);
alter table public.part_photos enable row level security;
revoke all on public.part_photos from public,anon,authenticated;
grant select,insert,delete on public.part_photos to authenticated;
grant all on public.part_photos to service_role;
create policy part_photos_read on public.part_photos for select to authenticated using(exists(select 1 from public.profiles where id=(select auth.uid()) and active) and exists(select 1 from public.parts where id=part_id and active));
create policy part_photos_add on public.part_photos for insert to authenticated with check(uploaded_by=(select auth.uid()) and exists(select 1 from public.profiles where id=(select auth.uid()) and active and role in ('super_admin','corporate_manager','unit_supervisor','technician')) and exists(select 1 from public.parts where id=part_id and active));
create policy part_photos_remove on public.part_photos for delete to authenticated using(exists(select 1 from public.profiles where id=(select auth.uid()) and active and role in ('super_admin','corporate_manager','unit_supervisor','technician')));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('ruel-part-photos','ruel-part-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy part_photo_storage_read on storage.objects for select to authenticated using(bucket_id='ruel-part-photos' and exists(select 1 from public.profiles where id=(select auth.uid()) and active) and exists(select 1 from public.parts where id::text=split_part(objects.name,'/',1) and active));
create policy part_photo_storage_upload on storage.objects for insert to authenticated with check(bucket_id='ruel-part-photos' and exists(select 1 from public.profiles where id=(select auth.uid()) and active and role in ('super_admin','corporate_manager','unit_supervisor','technician')) and exists(select 1 from public.parts where id::text=split_part(objects.name,'/',1) and active));
create policy part_photo_storage_delete on storage.objects for delete to authenticated using(bucket_id='ruel-part-photos' and exists(select 1 from public.profiles where id=(select auth.uid()) and active and role in ('super_admin','corporate_manager','unit_supervisor','technician')));
