-- Foreground-only location assistance. No automatic delivery completion.
create table public.production_plant_zones (
 business_unit_id uuid primary key references public.business_units(id),
 latitude double precision not null check(latitude between -90 and 90),
 longitude double precision not null check(longitude between -180 and 180),
 radius_m integer not null default 150 check(radius_m between 75 and 1000),
 updated_at timestamptz not null default now()
);
alter table public.production_plant_zones enable row level security;
revoke all on public.production_plant_zones from public,anon,authenticated;
grant select on public.production_plant_zones to authenticated;
grant all on public.production_plant_zones to service_role;
create policy production_plant_zones_read on public.production_plant_zones for select to authenticated using(private.production_reader(business_unit_id));
alter table public.production_sites add column latitude double precision, add column longitude double precision, add column radius_m integer not null default 150 check(radius_m between 75 and 1000), add constraint production_site_coordinates check((latitude is null and longitude is null) or (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180));
alter table public.production_loads add column plant_zone jsonb, add column site_zone jsonb, add column left_site_at timestamptz;
alter table public.production_activity drop constraint production_activity_kind_check;
alter table public.production_activity add constraint production_activity_kind_check check(kind in ('order_created','reference_changed','scheduled','produced','departed','arrived','completed','site_left','cancelled','message','attachment','geofences_updated'));
create table private.production_geofence_state (
 load_id uuid primary key references public.production_loads(id),
 last_sample_at timestamptz,
 plant_seen boolean not null default false,
 site_seen boolean not null default false,
 candidate text,
 candidate_since timestamptz,
 sample_count integer not null default 0
);
alter table private.production_geofence_state enable row level security;
revoke all on private.production_geofence_state from public,anon,authenticated;
grant all on private.production_geofence_state to service_role;
create policy production_geofence_state_service on private.production_geofence_state to service_role using(true) with check(true);

create function private.production_snapshot_zones() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='ready' and old.status='scheduled' then
 select jsonb_build_object('latitude',z.latitude,'longitude',z.longitude,'radius_m',z.radius_m) into new.plant_zone from public.production_orders o join public.production_plant_zones z on z.business_unit_id=o.business_unit_id where o.id=new.order_id;
 select jsonb_build_object('latitude',s.latitude,'longitude',s.longitude,'radius_m',s.radius_m) into new.site_zone from public.production_orders o join public.production_sites s on s.id=o.site_id where o.id=new.order_id and s.latitude is not null;
 end if;
 return new;
end $$;
revoke all on function private.production_snapshot_zones() from public,anon,authenticated;
create trigger production_snapshot_zones before update of status on public.production_loads for each row execute function private.production_snapshot_zones();

create function private.production_distance_m(lat1 double precision,lon1 double precision,lat2 double precision,lon2 double precision) returns double precision language sql immutable set search_path='' as $$
 select 6371000 * 2 * asin(sqrt(least(1.0,greatest(0.0,power(sin(radians(lat2-lat1)/2),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lon2-lon1)/2),2)))))
$$;
revoke all on function private.production_distance_m(double precision,double precision,double precision,double precision) from public,anon,authenticated;

create function private.production_geofence_impl(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();u uuid;sid uuid;lid uuid;rid uuid;lat double precision;lon double precision;acc double precision;r integer;at_time timestamptz;o public.production_orders%rowtype;l public.production_loads%rowtype;st private.production_geofence_state%rowtype;zone jsonb;distance double precision;target text;ev public.production_activity%rowtype;recipient uuid;result jsonb;body text;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 if p_data->>'actor_id' is distinct from actor::text then raise exception 'Location update belongs to another account';end if;
 if p_action in ('plant_zone','site_zone') then
 u:=(p_data->>'business_unit_id')::uuid;
 if not coalesce(private.production_manager(u),false) then raise exception 'Manager access required for this business unit';end if;
 if p_action='site_zone' then
 sid:=(p_data->>'site_id')::uuid;
 if not exists(select 1 from public.production_sites s join public.production_customers c on c.id=s.customer_id where s.id=sid and c.business_unit_id=u) then raise exception 'Jobsite outside this unit';end if;
 end if;
 if coalesce((p_data->>'clear')::boolean,false) then
 if p_action='plant_zone' then delete from public.production_plant_zones where business_unit_id=u;
 else update public.production_sites set latitude=null,longitude=null where id=sid;end if;
 return jsonb_build_object('ok',true);end if;
 lat:=(p_data->>'latitude')::double precision;lon:=(p_data->>'longitude')::double precision;r:=(p_data->>'radius_m')::integer;
 if lat is null or lon is null or r is null or not(lat between -90 and 90 and lon between -180 and 180 and r between 75 and 1000) then raise exception 'Enter valid latitude, longitude and a radius from 75 to 1000 metres';end if;
 if p_action='plant_zone' then
 insert into public.production_plant_zones(business_unit_id,latitude,longitude,radius_m) values(u,lat,lon,r) on conflict(business_unit_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,radius_m=excluded.radius_m,updated_at=now();
 else update public.production_sites set latitude=lat,longitude=lon,radius_m=r where id=sid;end if;
 return jsonb_build_object('ok',true);
 end if;
 lid:=(p_data->>'load_id')::uuid;
 select order_id into rid from public.production_loads where id=lid;
 -- Match core command lock order to avoid deadlocks with manual driver events.
 select * into o from public.production_orders where id=rid for update;
 select * into l from public.production_loads where id=lid for update;
 if l.id is null or not coalesce(private.production_load_access(lid,true),false) then raise exception 'Delivery access denied';end if;
 if p_action='refresh_zones' then
 if not private.production_manager(o.business_unit_id) or l.status<>'ready' then raise exception 'Only the plant manager can update zones before departure';end if;
 update public.production_loads set plant_zone=(select jsonb_build_object('latitude',z.latitude,'longitude',z.longitude,'radius_m',z.radius_m) from public.production_plant_zones z where z.business_unit_id=o.business_unit_id),site_zone=(select jsonb_build_object('latitude',s.latitude,'longitude',s.longitude,'radius_m',s.radius_m) from public.production_sites s where s.id=o.site_id and s.latitude is not null) where id=lid;
 delete from private.production_geofence_state where load_id=lid;
 insert into public.production_activity(order_id,load_id,author_id,kind,body,client_id,payload) values(rid,lid,actor,'geofences_updated','Delivery zones updated before departure',gen_random_uuid(),jsonb_build_object('source','manager'));
 return jsonb_build_object('ok',true);
 end if;
 if p_action<>'sample' then raise exception 'Unknown location action';end if;
 if l.driver_id<>actor or not exists(select 1 from public.production_drivers d where d.user_id=actor and d.active and d.fleet_unit_id=l.fleet_unit_id) then raise exception 'Only the assigned driver can use location assistance';end if;
 if l.status not in ('ready','departed','arrived','completed') or (l.status='completed' and (l.left_site_at is not null or l.completed_at<now()-interval '12 hours')) then return jsonb_build_object('event',null,'notice','No active location step');end if;
 lat:=(p_data->>'latitude')::double precision;lon:=(p_data->>'longitude')::double precision;acc:=(p_data->>'accuracy_m')::double precision;at_time:=(p_data->>'sampled_at')::timestamptz;
 if lat is null or lon is null or acc is null or at_time is null or not(lat between -90 and 90 and lon between -180 and 180 and acc between 0 and 50) or at_time<clock_timestamp()-interval '45 seconds' or at_time>clock_timestamp()+interval '5 seconds' then return jsonb_build_object('event',null,'notice','Waiting for a fresh, accurate GPS reading');end if;
 if at_time<coalesce(l.arrived_at,l.departed_at,l.produced_at) then return jsonb_build_object('event',null,'notice','Waiting for a current GPS reading');end if;
 insert into private.production_geofence_state(load_id) values(lid) on conflict do nothing;
 select * into st from private.production_geofence_state where load_id=lid for update;
 if st.last_sample_at is not null and at_time<st.last_sample_at+interval '8 seconds' then return jsonb_build_object('event',null,'notice','Location assistance active');end if;
 if st.last_sample_at is not null and at_time>st.last_sample_at+interval '45 seconds' then st.candidate:=null;st.sample_count:=0;end if;
 if l.status='ready' then zone:=l.plant_zone;else zone:=l.site_zone;end if;
 if zone is null then return jsonb_build_object('event',null,'notice','No zone configured for this step. Use the manual button');end if;
 distance:=private.production_distance_m(lat,lon,(zone->>'latitude')::double precision,(zone->>'longitude')::double precision);r:=(zone->>'radius_m')::integer;
 -- Accuracy margin and a 30 m exit buffer prevent GPS jitter crossing a boundary.
 if l.status='ready' then
 if distance+acc<=r then st.plant_seen:=true;end if;
 if st.plant_seen and distance-acc>=r+30 then target:='departed';end if;
 elsif l.status='departed' then
 if distance+acc<=r then target:='arrived';end if;
 else
 if distance+acc<=r then st.site_seen:=true;end if;
 if st.site_seen and l.left_site_at is null and distance-acc>=r+30 then target:='site_left';end if;
 end if;
 if target is null then st.candidate:=null;st.candidate_since:=null;st.sample_count:=0;
 elsif st.candidate is distinct from target then st.candidate:=target;st.candidate_since:=at_time;st.sample_count:=1;
 else st.sample_count:=st.sample_count+1;end if;
 update private.production_geofence_state set last_sample_at=at_time,plant_seen=st.plant_seen,site_seen=st.site_seen,candidate=st.candidate,candidate_since=st.candidate_since,sample_count=st.sample_count where load_id=lid;
 if target is null or st.sample_count<3 or at_time-st.candidate_since<interval '30 seconds' then return jsonb_build_object('event',null,'notice',case when target is null then 'Location assistance active' else 'Confirming zone crossing…' end);end if;
 if target in ('departed','arrived') then
 -- Core state machine still enforces readiness, sequence and active truck/driver exclusivity.
 result:=private.production_command_impl('event',jsonb_build_object('load_id',lid,'event',target,'actor_id',actor,'client_id',gen_random_uuid(),'captured_at',at_time,'source','geofence','latitude',lat,'longitude',lon,'accuracy_m',acc));
 else
 update public.production_loads set left_site_at=at_time where id=lid;
 body:='Driver left the jobsite · detected by location. Delivery completion is confirmed separately';
 insert into public.production_activity(order_id,load_id,author_id,kind,body,customer_visible,captured_at,client_id,payload) values(rid,lid,actor,'site_left',body,true,at_time,gen_random_uuid(),jsonb_build_object('source','geofence','latitude',lat,'longitude',lon,'accuracy_m',acc)) returning * into ev;
 for recipient in select distinct x from unnest(array[o.created_by,l.created_by]) t(x) where x is not null and x<>actor loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,rid,o.business_unit_id,'production_activity','info','Delivery · '||coalesce(o.external_number,'TEMP-'||o.order_number),body,'production:'||ev.id||':'||recipient);
 end loop;
 end if;
 update private.production_geofence_state set candidate=null,candidate_since=null,sample_count=0,site_seen=case when target='arrived' then true else site_seen end where load_id=lid;
 return jsonb_build_object('event',target,'notice',case target when 'departed' then 'Departure recorded automatically' when 'arrived' then 'Arrival recorded automatically' else 'Site departure recorded. Confirm delivery separately' end);
end $$;
create function public.production_geofence(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.production_geofence_impl(p_action,p_data)$$;
revoke all on function private.production_geofence_impl(text,jsonb),public.production_geofence(text,jsonb) from public,anon,authenticated;
grant execute on function private.production_geofence_impl(text,jsonb),public.production_geofence(text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION private.production_workspace_impl()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select jsonb_build_object(
 'manage_units',coalesce((select jsonb_agg(id) from public.business_units where private.production_manager(id)),'[]'),
 'read_units',coalesce((select jsonb_agg(id) from public.business_units where private.production_reader(id)),'[]'),
 'plant_zones',coalesce((select jsonb_agg(z) from public.production_plant_zones z where private.production_reader(z.business_unit_id)),'[]'),
 'driver',exists(select 1 from public.production_drivers d join public.profiles p on p.id=d.user_id where d.user_id=(select auth.uid()) and d.active and p.active and exists(select 1 from public.user_unit_access a where a.user_id=d.user_id and a.business_unit_id=d.fleet_unit_id)),
 'customers',coalesce((select jsonb_agg(c) from public.production_customers c where private.production_reader(c.business_unit_id)),'[]'),
 'sites',coalesce((select jsonb_agg(s) from public.production_sites s join public.production_customers c on c.id=s.customer_id where private.production_reader(c.business_unit_id)),'[]'),
 'products',coalesce((select jsonb_agg(p) from public.production_products p where private.production_reader(p.business_unit_id)),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'fleet_unit_id',d.fleet_unit_id,'active',d.active)) from public.production_drivers d join public.profiles p on p.id=d.user_id where p.active and private.production_reader(d.fleet_unit_id)),'[]'),
 'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'fleet_unit_id',a.business_unit_id)) from public.profiles p join public.user_unit_access a on a.user_id=p.id join public.business_units b on b.id=a.business_unit_id where p.active and b.code='MOBILE-PR' and private.production_manager(b.id)),'[]'),
 'trucks',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.asset_code||' · '||a.name,'fleet_unit_id',a.business_unit_id)) from public.assets a join public.business_units b on b.id=a.business_unit_id where b.code='MOBILE-PR' and a.status='active' and private.production_reader(b.id)),'[]'),
 'orders',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('customer_name',c.name,'customer_email',case when private.production_reader(o.business_unit_id) then c.email else '' end,'site_name',s.name,'site_address',s.address)) from public.production_orders o join public.production_customers c on c.id=o.customer_id join public.production_sites s on s.id=o.site_id where private.production_order_access(o.id)),'[]'),
 'loads',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('driver_name',p.full_name,'truck_name',a.asset_code||' · '||a.name)) from public.production_loads l join public.profiles p on p.id=l.driver_id join public.assets a on a.id=l.truck_id where private.production_load_access(l.id)),'[]'))
$function$
;
CREATE OR REPLACE FUNCTION private.production_tracking_impl(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rid uuid;result jsonb;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{48}$' then return null;end if;
 select order_id into rid from private.production_tracking where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and expires_at>now();
 if rid is null then return null;end if;
 select jsonb_build_object('reference',coalesce(o.external_number,'TEMP-'||o.order_number),'status',o.status,'product',o.product_name,'quantity',o.quantity,'unit',o.unit,'due_at',o.due_at,'site',s.name,'loads',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'number',l.load_number,'quantity',l.quantity,'status',l.status,'departed_at',l.departed_at,'arrived_at',l.arrived_at,'completed_at',l.completed_at,'left_site_at',l.left_site_at)) from public.production_loads l where l.order_id=o.id),'[]'),'updates',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'load_id',e.load_id,'kind',e.kind,'body',e.body,'captured_at',e.captured_at,'received_at',e.received_at,'media',coalesce((select jsonb_agg(jsonb_build_object('path',m.object_path,'type',m.mime_type,'name',m.name)) from public.production_media m where m.activity_id=e.id),'[]')) order by e.received_at) from public.production_activity e where e.order_id=o.id and e.customer_visible),'[]')) into result from public.production_orders o join public.production_sites s on s.id=o.site_id where o.id=rid;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.production_command_impl(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();u uuid;rid uuid;lid uuid;cid uuid;pid uuid;sid uuid;key uuid;at_time timestamptz;body text;visible boolean; old_ref text; o public.production_orders%rowtype;l public.production_loads%rowtype;pr public.production_products%rowtype;ev public.production_activity%rowtype; token text; path text; recipient uuid;
begin
 if p_data ? 'actor_id' and (p_data->>'actor_id') is distinct from actor::text then raise exception 'This queued update belongs to another account';end if;
 if actor is null or not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 u:=nullif(p_data->>'business_unit_id','')::uuid;rid:=nullif(p_data->>'order_id','')::uuid;lid:=nullif(p_data->>'load_id','')::uuid;
 if p_action in ('customer','site','product','driver','order') then
 if not private.production_manager(u) then raise exception 'Manager access required for this business unit';end if;
 end if;
 if p_action='customer' then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text,364));
 if exists(select 1 from public.production_customers where business_unit_id=u and lower(regexp_replace(btrim(name),'\s+',' ','g'))=lower(regexp_replace(btrim(p_data->>'name'),'\s+',' ','g'))) then raise exception 'This customer already exists. Select the existing customer';end if;
 insert into public.production_customers(business_unit_id,name,email,phone) values(u,btrim(p_data->>'name'),coalesce(p_data->>'email',''),coalesce(p_data->>'phone','')) returning id into cid;return jsonb_build_object('id',cid);
 elsif p_action='site' then
 cid:=(p_data->>'customer_id')::uuid;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(cid::text,365));
 if exists(select 1 from public.production_sites where customer_id=cid and lower(regexp_replace(btrim(name),'\s+',' ','g'))=lower(regexp_replace(btrim(p_data->>'name'),'\s+',' ','g')) and lower(regexp_replace(btrim(address),'\s+',' ','g'))=lower(regexp_replace(btrim(p_data->>'address'),'\s+',' ','g'))) then raise exception 'This jobsite already exists. Select the existing jobsite';end if;
 if not exists(select 1 from public.production_customers where id=cid and business_unit_id=u) then raise exception 'Customer outside this unit';end if;
 insert into public.production_sites(customer_id,name,address) values(cid,btrim(p_data->>'name'),btrim(p_data->>'address')) returning id into sid;return jsonb_build_object('id',sid);
 elsif p_action='product' then
 insert into public.production_products(business_unit_id,name,unit,kind) values(u,btrim(p_data->>'name'),p_data->>'unit',p_data->>'kind') returning id into pid;return jsonb_build_object('id',pid);
 elsif p_action='driver' then
 cid:=(p_data->>'user_id')::uuid;
 if not exists(select 1 from public.business_units where id=u and code='MOBILE-PR') or not exists(select 1 from public.profiles p join public.user_unit_access a on a.user_id=p.id where p.id=cid and p.active and a.business_unit_id=u) then raise exception 'Driver must be active and authorized in Peace River Mobile Concrete Fleet';end if;
 insert into public.production_drivers(user_id,fleet_unit_id,active) values(cid,u,coalesce((p_data->>'active')::boolean,true)) on conflict(user_id) do update set active=excluded.active;
 return jsonb_build_object('id',cid);
 elsif p_action='order' then
 -- Serialize the request before creating catalogue records, so a retry cannot duplicate them.
 if nullif(p_data->>'request_id','') is not null then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_data->>'request_id',363));
 select * into o from public.production_orders where id=(p_data->>'request_id')::uuid;
 if o.id is not null then
 if o.created_by<>actor or o.business_unit_id<>u or not exists(select 1 from public.production_activity where order_id=o.id and kind='order_created' and payload=p_data) then raise exception 'Order request identifier already used';end if;
 return jsonb_build_object('id',o.id);end if;end if;
 select * into pr from public.production_products where id=nullif(p_data->>'product_id','')::uuid and business_unit_id=u and active;
 if pr.id is null then raise exception 'Select an existing active product or service in this unit';end if;
 if jsonb_typeof(p_data->'new_customer')='object' then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text,364));
 body:=regexp_replace(btrim(p_data->'new_customer'->>'name'),'\s+',' ','g');
 if exists(select 1 from public.production_customers where business_unit_id=u and lower(regexp_replace(btrim(name),'\s+',' ','g'))=lower(body)) then raise exception 'This customer already exists. Select the existing customer';end if;
 insert into public.production_customers(business_unit_id,name,email,phone) values(u,body,coalesce(p_data->'new_customer'->>'email',''),coalesce(p_data->'new_customer'->>'phone','')) returning id into cid;
 else
 cid:=nullif(p_data->>'customer_id','')::uuid;
 if not exists(select 1 from public.production_customers where id=cid and business_unit_id=u) then raise exception 'Select a customer in this unit or add a new customer';end if;
 end if;
 if jsonb_typeof(p_data->'new_site')='object' then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(cid::text,365));
 body:=regexp_replace(btrim(p_data->'new_site'->>'name'),'\s+',' ','g');
 if exists(select 1 from public.production_sites where customer_id=cid and lower(regexp_replace(btrim(name),'\s+',' ','g'))=lower(body) and lower(regexp_replace(btrim(address),'\s+',' ','g'))=lower(regexp_replace(btrim(p_data->'new_site'->>'address'),'\s+',' ','g'))) then raise exception 'This jobsite already exists. Select the existing jobsite';end if;
 insert into public.production_sites(customer_id,name,address) values(cid,body,regexp_replace(btrim(p_data->'new_site'->>'address'),'\s+',' ','g')) returning id into sid;
 else
 sid:=nullif(p_data->>'site_id','')::uuid;
 if not exists(select 1 from public.production_sites where id=sid and customer_id=cid) then raise exception 'Select a jobsite for this customer or add a new jobsite';end if;
 end if;
 insert into public.production_orders(id,business_unit_id,customer_id,site_id,product_id,external_number,product_name,unit,quantity,due_at,instructions,created_by) values(coalesce(nullif(p_data->>'request_id','')::uuid,gen_random_uuid()),u,cid,sid,pr.id,nullif(btrim(p_data->>'external_number'),''),pr.name,pr.unit,(p_data->>'quantity')::numeric,(p_data->>'due_at')::timestamptz,coalesce(p_data->>'instructions',''),actor) returning * into o;
 insert into public.production_activity(order_id,author_id,kind,body,customer_visible,client_id,payload) values(o.id,actor,'order_created','Order confirmed',true,gen_random_uuid(),p_data);return jsonb_build_object('id',o.id);
 end if;
 if lid is not null then select * into l from public.production_loads where id=lid;rid:=l.order_id;end if;
 select * into o from public.production_orders where id=rid for update;
 if o.id is null then raise exception 'Order not found';end if;
 if p_action in ('reference','schedule','produce','tracking','cancel_order') and not private.production_manager(o.business_unit_id) then raise exception 'Manager access required';end if;
 if lid is not null then select * into l from public.production_loads where id=lid for update;if not private.production_load_access(lid,true) then raise exception 'Service access denied';end if;end if;
 key:=coalesce(nullif(p_data->>'client_id','')::uuid,gen_random_uuid());
 select * into ev from public.production_activity where client_id=key;
 if ev.id is not null then
 if ev.author_id<>actor or ev.order_id<>rid or ev.payload->>'load_id' is distinct from p_data->>'load_id' or ev.payload is distinct from p_data then raise exception 'Request identifier already used for different data';end if;
 return jsonb_build_object('id',ev.id,'replayed',true);end if;
 at_time:=coalesce(nullif(p_data->>'captured_at','')::timestamptz,now());
 if at_time>now()+interval '5 minutes' or at_time<o.created_at-interval '5 minutes' then raise exception 'Invalid event time; check device clock';end if;
 body:=coalesce(p_data->>'body','');visible:=coalesce((p_data->>'customer_visible')::boolean,false);
 if p_action='reference' then
 old_ref:=coalesce(o.external_number,'TEMP-'||o.order_number);
 update public.production_orders set external_number=nullif(btrim(p_data->>'external_number'),'') where id=rid;
 body:=old_ref||' → '||coalesce(nullif(btrim(p_data->>'external_number'),''),'TEMP-'||o.order_number);p_action:='reference_changed';
 elsif p_action='schedule' then
 if o.status<>'confirmed' then raise exception 'Order is not open';end if;
 u:=(p_data->>'fleet_unit_id')::uuid;
 if not exists(select 1 from public.production_drivers d join public.profiles p on p.id=d.user_id join public.user_unit_access a on a.user_id=p.id and a.business_unit_id=d.fleet_unit_id where d.user_id=(p_data->>'driver_id')::uuid and d.fleet_unit_id=u and d.active and p.active) then raise exception 'Choose an enrolled active fleet driver';end if;
 if not exists(select 1 from public.assets where id=(p_data->>'truck_id')::uuid and business_unit_id=u and status='active') then raise exception 'Choose an active fleet vehicle';end if;
 if (p_data->>'quantity')::numeric+coalesce((select sum(quantity) from public.production_loads where order_id=rid and status<>'cancelled'),0)>o.quantity then raise exception 'Load exceeds remaining order quantity';end if;
 insert into public.production_loads(order_id,fleet_unit_id,driver_id,truck_id,quantity,created_by) values(rid,u,(p_data->>'driver_id')::uuid,(p_data->>'truck_id')::uuid,(p_data->>'quantity')::numeric,actor) returning * into l;
 lid:=l.id;p_action:='scheduled';body:='Delivery assigned';
 elsif p_action='produce' then
 if l.id is null or l.status<>'scheduled' then raise exception 'Load must be scheduled';end if;
 update public.production_loads set produced_at=now(),status='ready' where id=lid;p_action:='produced';body:='Production confirmed · '||l.quantity||' '||o.unit;
 elsif p_action='event' then
 if l.id is null then raise exception 'Select a delivery';end if;
 if not exists(select 1 from public.production_drivers d where d.user_id=actor and d.user_id=l.driver_id and d.active) then raise exception 'Only the assigned driver can record delivery events';end if;
 p_action:=p_data->>'event';visible:=true;
 if p_action='departed' and l.status='ready' then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text,360));perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(l.truck_id::text,361));
 if exists(select 1 from public.production_loads where (driver_id=actor or truck_id=l.truck_id) and status in ('departed','arrived')) then raise exception 'Complete your current delivery first';end if;
 update public.production_loads set status='departed',departed_at=at_time where id=lid;body:='Delivery departed the plant';
 elsif p_action='arrived' and l.status='departed' and at_time>=l.departed_at then update public.production_loads set status='arrived',arrived_at=at_time where id=lid;body:='Driver arrived at the jobsite';
 elsif p_action='completed' and l.status='arrived' and at_time>=l.arrived_at then update public.production_loads set status='completed',completed_at=at_time where id=lid;body:='Driver confirmed delivery complete';
 if coalesce((select sum(quantity) from public.production_loads where order_id=rid and status='completed'),0)>=o.quantity then update public.production_orders set status='completed' where id=rid;end if;
 else raise exception 'Delivery status changed or event time is out of sequence. Refresh and review';end if;
 elsif p_action='message' then
 if lid is null or length(btrim(body))=0 then raise exception 'Select a delivery and enter a message';end if;
 -- Only a dispatcher decides what the customer can see.
 if not private.production_manager(o.business_unit_id) then visible:=false;end if;
 elsif p_action='attachment' then
 if lid is null then raise exception 'Select a delivery';end if;
 path:=p_data->>'object_path';
 if split_part(path,'/',1)<>lid::text or split_part(path,'/',2)<>actor::text or not exists(select 1 from storage.objects where bucket_id='production-evidence' and name=path) then raise exception 'Upload the attachment first';end if;
 if not private.production_manager(o.business_unit_id) then visible:=false;end if;
 elsif p_action='publish' then
 if not private.production_manager(o.business_unit_id) then raise exception 'Manager access required';end if;
 update public.production_activity set customer_visible=coalesce((p_data->>'visible')::boolean,false) where id=(p_data->>'activity_id')::uuid and order_id=rid and kind in ('message','attachment');return jsonb_build_object('ok',true);
 elsif p_action='tracking' then
 token:=encode(extensions.gen_random_bytes(24),'hex');
 insert into private.production_tracking(order_id,token_hash,expires_at,created_by) values(rid,encode(extensions.digest(token,'sha256'),'hex'),now()+interval '90 days',actor) on conflict(order_id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,created_by=actor;
 return jsonb_build_object('token',token,'expires_days',90);
 elsif p_action='cancel_order' then
 if exists(select 1 from public.production_loads where order_id=rid and status in ('departed','arrived','completed')) then raise exception 'Started deliveries cannot be cancelled';end if;
 update public.production_orders set status='cancelled' where id=rid;update public.production_loads set status='cancelled' where order_id=rid;p_action:='cancelled';body:='Order cancelled';visible:=true;
 else raise exception 'Unknown production action';end if;
 insert into public.production_activity(order_id,load_id,author_id,kind,body,customer_visible,captured_at,client_id,payload) values(rid,lid,actor,p_action,body,visible,at_time,key,p_data) returning * into ev;
 if p_action='attachment' then insert into public.production_media(activity_id,object_path,mime_type,name) values(ev.id,path,p_data->>'mime_type',left(p_data->>'name',200));end if;
 for recipient in select distinct x from unnest(array[o.created_by,l.created_by,l.driver_id]) as t(x) where x is not null and x<>actor loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,rid,case when recipient=l.driver_id then l.fleet_unit_id else o.business_unit_id end,'production_activity','info','Delivery · '||coalesce(o.external_number,'TEMP-'||o.order_number),left(body,500),'production:'||ev.id||':'||recipient);
 end loop;
 return jsonb_build_object('id',coalesce(lid,ev.id));
end $function$
;
