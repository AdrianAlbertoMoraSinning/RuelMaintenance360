-- External customer acknowledgment captured by the assigned driver on their phone.
-- Receipt acceptance is separate from driver completion and GPS departure.
create table public.production_receipts (
 id uuid primary key default gen_random_uuid(),
 load_id uuid not null unique references public.production_loads(id),
 recorded_by uuid not null references public.profiles(id),
 receiver_name text not null check(length(btrim(receiver_name)) between 2 and 160),
 signed_at timestamptz not null default now(),
 strokes jsonb not null,
 snapshot jsonb not null,
 snapshot_hash text not null,
 client_id uuid not null unique
);
create index production_receipts_driver on public.production_receipts(recorded_by);
alter table public.production_receipts enable row level security;
revoke all on public.production_receipts from public,anon,authenticated;
grant select on public.production_receipts to authenticated;
grant all on public.production_receipts to service_role;
create policy production_receipts_read on public.production_receipts for select to authenticated using(private.production_load_access(load_id));

create function private.delivery_receipt_snapshot(p_load uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('load_id',l.id,'load_number',l.load_number,'order_id',o.id,'reference',coalesce(o.external_number,'TEMP-'||o.order_number),'quantity',l.quantity,'unit',o.unit,'product',o.product_name,'customer',c.name,'site',s.name,'address',s.address,'driver_id',l.driver_id,'truck_id',l.truck_id)
 from public.production_loads l join public.production_orders o on o.id=l.order_id join public.production_customers c on c.id=o.customer_id join public.production_sites s on s.id=o.site_id where l.id=p_load
$$;
revoke all on function private.delivery_receipt_snapshot(uuid) from public,anon,authenticated;

create function private.delivery_receipt_context(p_load uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s jsonb;l public.production_loads%rowtype;
begin
 if not private.production_load_access(p_load) then raise exception 'Delivery access denied';end if;
 select * into l from public.production_loads where id=p_load;s:=private.delivery_receipt_snapshot(p_load);
 return jsonb_build_object('snapshot',s,'snapshot_hash',encode(extensions.digest(s::text,'sha256'),'hex'),'can_sign',l.driver_id=auth.uid() and l.status in ('arrived','completed') and private.production_load_access(p_load,true),
 'receipt',(select jsonb_build_object('id',r.id,'receiver_name',r.receiver_name,'signed_at',r.signed_at,'strokes',r.strokes,'snapshot',r.snapshot) from public.production_receipts r where r.load_id=p_load));
end $$;
create function public.delivery_receipt_context(p_load_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.delivery_receipt_context(p_load_id)$$;
revoke all on function private.delivery_receipt_context(uuid),public.delivery_receipt_context(uuid) from public,anon,authenticated;
grant execute on function private.delivery_receipt_context(uuid),public.delivery_receipt_context(uuid) to authenticated;

create function private.add_delivery_receipt(p_load uuid,p_actor uuid,p_hash text,p_name text,p_strokes jsonb,p_client uuid,p_confirm boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();l public.production_loads%rowtype;o public.production_orders%rowtype;s jsonb;h text;r public.production_receipts%rowtype;stroke jsonb;point jsonb;x numeric;y numeric;lo_x numeric:=1;hi_x numeric:=0;lo_y numeric:=1;hi_y numeric:=0;n integer:=0;recipient uuid;
begin
 if actor is null or actor is distinct from p_actor or not private.production_load_access(p_load,true) then raise exception 'Assigned driver access required';end if;
 -- Same lock order as dispatch commands: order, then load.
 select o1.* into o from public.production_orders o1 join public.production_loads l1 on l1.order_id=o1.id where l1.id=p_load for update of o1;
 select * into l from public.production_loads where id=p_load for update;
 if l.id is null or l.driver_id<>actor or not exists(select 1 from public.production_drivers where user_id=actor and active) then raise exception 'Only the assigned active driver can capture customer receipt';end if;
 if p_confirm is distinct from true or p_client is null or p_name is null or length(btrim(p_name)) not between 2 and 160 then raise exception 'Enter the receiver name and confirm customer acceptance';end if;
 select * into r from public.production_receipts where client_id=p_client;
 if r.id is not null then
 if r.load_id<>p_load or r.recorded_by<>actor or r.snapshot_hash is distinct from p_hash or r.receiver_name is distinct from btrim(p_name) or r.strokes is distinct from p_strokes then raise exception 'Receipt request already used for different data';end if;return r.id;end if;
 if l.status not in ('arrived','completed') or l.arrived_at is null or l.arrived_at>now() then raise exception 'Confirm arrival before collecting customer signature';end if;
 if exists(select 1 from public.production_receipts where load_id=p_load) then raise exception 'This delivery already has a signed customer receipt';end if;
 s:=private.delivery_receipt_snapshot(p_load);h:=encode(extensions.digest(s::text,'sha256'),'hex');
 if h is distinct from p_hash then raise exception 'Delivery details changed. Cancel, review the latest delivery and ask the customer to sign again';end if;
 if jsonb_typeof(p_strokes) is distinct from 'array' or octet_length(p_strokes::text)>200000 then raise exception 'Invalid or oversized signature';end if;
 if jsonb_array_length(p_strokes) not between 1 and 100 then raise exception 'Draw the customer signature';end if;
 for stroke in select value from jsonb_array_elements(p_strokes) loop
 if jsonb_typeof(stroke) is distinct from 'array' then raise exception 'Invalid signature stroke';end if;
 if jsonb_array_length(stroke) not between 2 and 4000 then raise exception 'Invalid signature stroke';end if;
 for point in select value from jsonb_array_elements(stroke) loop
 if jsonb_typeof(point) is distinct from 'array' then raise exception 'Invalid signature point';end if;
 if jsonb_array_length(point)<>2 or jsonb_typeof(point->0) is distinct from 'number' or jsonb_typeof(point->1) is distinct from 'number' then raise exception 'Invalid signature point';end if;
 x:=(point->>0)::numeric;y:=(point->>1)::numeric;
 if x not between 0 and 1 or y not between 0 and 1 then raise exception 'Invalid signature coordinates';end if;
 n:=n+1;if n>4000 then raise exception 'Signature too long. Clear and draw again';end if;
 lo_x:=least(lo_x,x);hi_x:=greatest(hi_x,x);lo_y:=least(lo_y,y);hi_y:=greatest(hi_y,y);
 end loop;end loop;
 if n<8 or hi_x-lo_x<0.02 or hi_y-lo_y<0.02 then raise exception 'Draw a visible signature, not a dot';end if;
 insert into public.production_receipts(load_id,recorded_by,receiver_name,strokes,snapshot,snapshot_hash,client_id) values(p_load,actor,btrim(p_name),p_strokes,s,h,p_client) returning * into r;
 insert into public.production_activity(order_id,load_id,author_id,kind,body,customer_visible,client_id,payload) values(o.id,l.id,actor,'message','Received & signed by '||r.receiver_name||' · Load '||l.load_number,true,gen_random_uuid(),jsonb_build_object('receipt_id',r.id,'source','customer_receipt'));
 for recipient in select distinct v from unnest(array[o.created_by,l.created_by]) a(v) where v is not null and v<>actor loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,o.id,o.business_unit_id,'production_activity','info','Customer received & signed','Load '||l.load_number||' received by '||r.receiver_name,'receipt:'||r.id||':'||recipient);
 end loop;
 return r.id;
end $$;
create function public.add_delivery_receipt(p_load_id uuid,p_expected_driver uuid,p_expected_hash text,p_receiver_name text,p_strokes jsonb,p_client_id uuid,p_confirm boolean) returns uuid language sql security invoker set search_path='' as $$select private.add_delivery_receipt(p_load_id,p_expected_driver,p_expected_hash,p_receiver_name,p_strokes,p_client_id,p_confirm)$$;
revoke all on function private.add_delivery_receipt(uuid,uuid,text,text,jsonb,uuid,boolean),public.add_delivery_receipt(uuid,uuid,text,text,jsonb,uuid,boolean) from public,anon,authenticated;
grant execute on function private.add_delivery_receipt(uuid,uuid,text,text,jsonb,uuid,boolean),public.add_delivery_receipt(uuid,uuid,text,text,jsonb,uuid,boolean) to authenticated;
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
 'loads',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('receipt',(select jsonb_build_object('id',r.id,'receiver_name',r.receiver_name,'signed_at',r.signed_at,'strokes',r.strokes,'snapshot',r.snapshot) from public.production_receipts r where r.load_id=l.id),'driver_name',p.full_name,'truck_name',a.asset_code||' · '||a.name)) from public.production_loads l join public.profiles p on p.id=l.driver_id join public.assets a on a.id=l.truck_id where private.production_load_access(l.id)),'[]'))
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
 select jsonb_build_object('reference',coalesce(o.external_number,'TEMP-'||o.order_number),'status',o.status,'product',o.product_name,'quantity',o.quantity,'unit',o.unit,'due_at',o.due_at,'site',s.name,'loads',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'number',l.load_number,'quantity',l.quantity,'status',l.status,'departed_at',l.departed_at,'arrived_at',l.arrived_at,'completed_at',l.completed_at,'left_site_at',l.left_site_at,'receipt',(select jsonb_build_object('receiver_name',r.receiver_name,'signed_at',r.signed_at,'strokes',r.strokes,'snapshot',r.snapshot-'driver_id'-'truck_id'-'order_id'-'load_id') from public.production_receipts r where r.load_id=l.id))) from public.production_loads l where l.order_id=o.id),'[]'),'updates',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'load_id',e.load_id,'kind',e.kind,'body',e.body,'captured_at',e.captured_at,'received_at',e.received_at,'media',coalesce((select jsonb_agg(jsonb_build_object('path',m.object_path,'type',m.mime_type,'name',m.name)) from public.production_media m where m.activity_id=e.id),'[]')) order by e.received_at) from public.production_activity e where e.order_id=o.id and e.customer_visible),'[]')) into result from public.production_orders o join public.production_sites s on s.id=o.site_id where o.id=rid;
 return result;
end $function$
;
