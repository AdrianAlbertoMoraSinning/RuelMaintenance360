-- Private, deduplicated reference photographs. Original files remain unchanged.
create table public.asset_photo_images(
 id uuid primary key default gen_random_uuid(),
 source_name text not null check(length(source_name) between 1 and 250),
 mime_type text not null default 'image/jpeg' check(mime_type='image/jpeg'),
 image_data text not null check(length(image_data) between 4 and 2800000 and image_data ~ '^[A-Za-z0-9+/=]+$'),
 content_hash text not null unique check(content_hash ~ '^[a-f0-9]{64}$'),
 uploaded_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create index asset_photo_image_uploader on public.asset_photo_images(uploaded_by);
create table public.asset_photo_links(
 id uuid primary key default gen_random_uuid(),
 asset_id uuid not null references public.assets(id) on delete cascade,
 image_id uuid not null references public.asset_photo_images(id),
 kind text not null default 'equipment' check(kind in ('equipment','shared_equipment','schematic')),
 caption text not null default '' check(length(caption)<=1500),
 created_at timestamptz not null default now(),
 unique(asset_id,image_id)
);
create index asset_photo_link_image on public.asset_photo_links(image_id);
alter table public.asset_photo_images enable row level security;
alter table public.asset_photo_links enable row level security;
revoke all on public.asset_photo_images,public.asset_photo_links from public,anon,authenticated;
grant select,insert on public.asset_photo_images to authenticated;
grant select,insert,delete on public.asset_photo_links to authenticated;
grant all on public.asset_photo_images,public.asset_photo_links to service_role;
create policy asset_photo_links_read on public.asset_photo_links for select to authenticated using(exists(select 1 from public.assets a where a.id=asset_id));
create policy asset_photo_images_read on public.asset_photo_images for select to authenticated using(uploaded_by=(select auth.uid()) or exists(select 1 from public.asset_photo_links l where l.image_id=asset_photo_images.id));
create policy asset_photo_images_add on public.asset_photo_images for insert to authenticated with check(uploaded_by=(select auth.uid()) and exists(select 1 from public.profiles where id=(select auth.uid()) and active and role in('super_admin','corporate_manager','unit_supervisor','technician')));
create policy asset_photo_links_add on public.asset_photo_links for insert to authenticated with check(exists(select 1 from public.assets a where a.id=asset_id and private.can_edit_unit(a.business_unit_id)) and exists(select 1 from public.asset_photo_images i where i.id=image_id));
create policy asset_photo_links_remove on public.asset_photo_links for delete to authenticated using(exists(select 1 from public.assets a where a.id=asset_id and private.can_edit_unit(a.business_unit_id)));

insert into public.asset_categories(code,name,description,sort_order) values
 ('BLOWER','Industrial Blower','Air-moving units for bulk-material transfer and plant services',240),
 ('STORAGE_TANK','Storage Tank','Water, cement and process-material storage vessels',250),
 ('AGGREGATE_BIN','Aggregate Bin / Storage Bay','Raw-material storage bays and batch feeder bins',260),
 ('PROCESS_HEATER','Process Heater / Heating Distribution','Water heating equipment and aggregate heating distribution',270),
 ('DOSING_SYSTEM','Dosing / Metering Equipment','Admixture dosing stations and water metering equipment',280),
 ('WEIGHING_SYSTEM','Weighing System','Material weigh hoppers and scales',290),
 ('CONTROL_SYSTEM','Control System','Plant batching control hardware and operator station',300),
 ('PROCESS_HOPPER','Process Hopper','Material receiving and loading hoppers',310)
 on conflict(code) do nothing;
