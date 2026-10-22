-- Separate production ledger: no work-order, purchasing or inventory mutation.
create table public.production_customers(id uuid primary key default gen_random_uuid(),business_unit_id uuid not null references public.business_units(id),name text not null check(length(btrim(name)) between 1 and 160),email text not null default '' check(length(email)<=254),phone text not null default '' check(length(phone)<=60),created_at timestamptz not null default now());
create table public.production_sites(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.production_customers(id),name text not null check(length(btrim(name)) between 1 and 160),address text not null check(length(btrim(address)) between 1 and 1000));
create table public.production_products(id uuid primary key default gen_random_uuid(),business_unit_id uuid not null references public.business_units(id),name text not null check(length(btrim(name)) between 1 and 160),unit text not null check(unit in ('m³','t','h','service','load','each')),kind text not null check(kind in ('product','service')),active boolean not null default true);
create table public.production_drivers(user_id uuid primary key references public.profiles(id),fleet_unit_id uuid not null references public.business_units(id),active boolean not null default true);
create table public.production_orders(id uuid primary key default gen_random_uuid(),order_number bigint generated always as identity unique,business_unit_id uuid not null references public.business_units(id),customer_id uuid not null references public.production_customers(id),site_id uuid not null references public.production_sites(id),product_id uuid not null references public.production_products(id),external_number text check(length(btrim(external_number)) between 1 and 100),product_name text not null,unit text not null,quantity numeric not null check(quantity>0 and quantity<=100000000),due_at timestamptz not null,instructions text not null default '' check(length(instructions)<=10000),status text not null default 'confirmed' check(status in ('confirmed','completed','cancelled')),created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create unique index production_order_external_number on public.production_orders(business_unit_id,lower(external_number)) where external_number is not null;
create table public.production_loads(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.production_orders(id),load_number bigint generated always as identity unique,fleet_unit_id uuid not null references public.business_units(id),driver_id uuid not null references public.profiles(id),truck_id uuid not null references public.assets(id),quantity numeric not null check(quantity>0),produced_at timestamptz,status text not null default 'scheduled' check(status in ('scheduled','ready','departed','arrived','completed','cancelled')),departed_at timestamptz,arrived_at timestamptz,completed_at timestamptz,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table public.production_activity(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.production_orders(id),load_id uuid references public.production_loads(id),author_id uuid not null references public.profiles(id),kind text not null check(kind in ('order_created','reference_changed','scheduled','produced','departed','arrived','completed','cancelled','message','attachment')),body text not null default '' check(length(body)<=10000),customer_visible boolean not null default false,captured_at timestamptz not null default now(),received_at timestamptz not null default now(),client_id uuid not null unique,payload jsonb not null default '{}');
create table public.production_media(id uuid primary key default gen_random_uuid(),activity_id uuid not null references public.production_activity(id),object_path text not null unique,mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime','audio/webm','audio/mp4','audio/ogg')),name text not null check(length(name)<=200));
create table private.production_tracking(order_id uuid primary key references public.production_orders(id),token_hash text not null unique,expires_at timestamptz not null,created_by uuid not null references public.profiles(id));
alter table private.production_tracking enable row level security;

create function private.production_manager(p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and ((p.role='super_admin' and p.personnel_category in ('ceo','manager','shareholder','administration')) or (p.personnel_category='manager' and exists(select 1 from public.user_unit_access u where u.user_id=p.id and u.business_unit_id=p_unit and u.can_edit))))
$$;
create function private.production_reader(p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and (private.production_manager(p_unit) or (p.personnel_category in ('ceo','shareholder','manager','supervisor') and (p.role in ('super_admin','corporate_manager') or exists(select 1 from public.user_unit_access u where u.user_id=p.id and u.business_unit_id=p_unit)))))
$$;
create function private.production_load_access(p_load uuid,p_write boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.production_loads l join public.production_orders o on o.id=l.order_id where l.id=p_load and (case when p_write then private.production_manager(o.business_unit_id) or private.production_manager(l.fleet_unit_id) else private.production_reader(o.business_unit_id) or private.production_reader(l.fleet_unit_id) end or exists(select 1 from public.production_drivers d join public.profiles p on p.id=d.user_id where d.user_id=(select auth.uid()) and d.user_id=l.driver_id and d.active and p.active and d.fleet_unit_id=l.fleet_unit_id and exists(select 1 from public.user_unit_access a where a.user_id=p.id and a.business_unit_id=d.fleet_unit_id))))
$$;
create function private.production_order_access(p_order uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.production_orders o where o.id=p_order and (private.production_reader(o.business_unit_id) or exists(select 1 from public.production_loads l where l.order_id=o.id and private.production_load_access(l.id))))
$$;

alter table public.notifications add column production_order_id uuid references public.production_orders(id);
create index notifications_production_order_idx on public.notifications(production_order_id);

-- All mutations use a controlled transaction. Client tables are read-only.
create function private.production_command_impl(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();u uuid;rid uuid;lid uuid;cid uuid;pid uuid;sid uuid;key uuid;at_time timestamptz;body text;visible boolean; old_ref text; o public.production_orders%rowtype;l public.production_loads%rowtype;pr public.production_products%rowtype;ev public.production_activity%rowtype; token text; path text; recipient uuid;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 u:=nullif(p_data->>'business_unit_id','')::uuid;rid:=nullif(p_data->>'order_id','')::uuid;lid:=nullif(p_data->>'load_id','')::uuid;
 if p_action in ('customer','site','product','driver','order') then
 if not private.production_manager(u) then raise exception 'Manager access required for this business unit';end if;
 end if;
 if p_action='customer' then
 insert into public.production_customers(business_unit_id,name,email,phone) values(u,btrim(p_data->>'name'),coalesce(p_data->>'email',''),coalesce(p_data->>'phone','')) returning id into cid;return jsonb_build_object('id',cid);
 elsif p_action='site' then
 cid:=(p_data->>'customer_id')::uuid;
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
 select * into pr from public.production_products where id=(p_data->>'product_id')::uuid and business_unit_id=u and active;
 cid:=(p_data->>'customer_id')::uuid;sid:=(p_data->>'site_id')::uuid;
 if pr.id is null or not exists(select 1 from public.production_customers c join public.production_sites s on s.customer_id=c.id where c.id=cid and c.business_unit_id=u and s.id=sid) then raise exception 'Choose a valid customer, site and product in this unit';end if;
 if nullif(p_data->>'request_id','') is not null then select * into o from public.production_orders where id=(p_data->>'request_id')::uuid;if o.id is not null then if o.created_by<>actor or o.business_unit_id<>u or not exists(select 1 from public.production_activity where order_id=o.id and kind='order_created' and payload=p_data) then raise exception 'Order request identifier already used';end if;return jsonb_build_object('id',o.id);end if;end if;
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
 elsif p_action='completed' and l.status='arrived' and at_time>=l.arrived_at then update public.production_loads set status='completed',completed_at=at_time where id=lid;body:='Driver completed delivery and left the site';
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
 for recipient in select distinct x from unnest(array[o.created_by,l.driver_id]) as t(x) where x is not null and x<>actor loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,rid,case when recipient=l.driver_id then l.fleet_unit_id else o.business_unit_id end,'production_activity','info','Delivery · '||coalesce(o.external_number,'TEMP-'||o.order_number),left(body,500),'production:'||ev.id||':'||recipient);
 end loop;
 return jsonb_build_object('id',coalesce(lid,ev.id));
end $$;
create function public.production_command(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.production_command_impl(p_action,p_data)$$;

create function private.production_workspace_impl() returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object(
 'manage_units',coalesce((select jsonb_agg(id) from public.business_units where private.production_manager(id)),'[]'),
 'read_units',coalesce((select jsonb_agg(id) from public.business_units where private.production_reader(id)),'[]'),
 'driver',exists(select 1 from public.production_drivers d join public.profiles p on p.id=d.user_id where d.user_id=(select auth.uid()) and d.active and p.active and exists(select 1 from public.user_unit_access a where a.user_id=d.user_id and a.business_unit_id=d.fleet_unit_id)),
 'customers',coalesce((select jsonb_agg(c) from public.production_customers c where private.production_reader(c.business_unit_id)),'[]'),
 'sites',coalesce((select jsonb_agg(s) from public.production_sites s join public.production_customers c on c.id=s.customer_id where private.production_reader(c.business_unit_id)),'[]'),
 'products',coalesce((select jsonb_agg(p) from public.production_products p where private.production_reader(p.business_unit_id)),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'fleet_unit_id',d.fleet_unit_id,'active',d.active)) from public.production_drivers d join public.profiles p on p.id=d.user_id where p.active and private.production_reader(d.fleet_unit_id)),'[]'),
 'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'fleet_unit_id',a.business_unit_id)) from public.profiles p join public.user_unit_access a on a.user_id=p.id join public.business_units b on b.id=a.business_unit_id where p.active and b.code='MOBILE-PR' and private.production_manager(b.id)),'[]'),
 'trucks',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.asset_code||' · '||a.name,'fleet_unit_id',a.business_unit_id)) from public.assets a join public.business_units b on b.id=a.business_unit_id where b.code='MOBILE-PR' and a.status='active' and private.production_reader(b.id)),'[]'),
 'orders',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('customer_name',c.name,'customer_email',case when private.production_reader(o.business_unit_id) then c.email else '' end,'site_name',s.name,'site_address',s.address)) from public.production_orders o join public.production_customers c on c.id=o.customer_id join public.production_sites s on s.id=o.site_id where private.production_order_access(o.id)),'[]'),
 'loads',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('driver_name',p.full_name,'truck_name',a.asset_code||' · '||a.name)) from public.production_loads l join public.profiles p on p.id=l.driver_id join public.assets a on a.id=l.truck_id where private.production_load_access(l.id)),'[]'))
$$;
create function public.production_workspace() returns jsonb language sql stable security invoker set search_path='' as $$select private.production_workspace_impl()$$;

create function private.production_tracking_impl(p_token text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rid uuid;result jsonb;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{48}$' then return null;end if;
 select order_id into rid from private.production_tracking where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and expires_at>now();
 if rid is null then return null;end if;
 select jsonb_build_object('reference',coalesce(o.external_number,'TEMP-'||o.order_number),'status',o.status,'product',o.product_name,'quantity',o.quantity,'unit',o.unit,'due_at',o.due_at,'site',s.name,'loads',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'number',l.load_number,'quantity',l.quantity,'status',l.status,'departed_at',l.departed_at,'arrived_at',l.arrived_at,'completed_at',l.completed_at)) from public.production_loads l where l.order_id=o.id),'[]'),'updates',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'load_id',e.load_id,'kind',e.kind,'body',e.body,'captured_at',e.captured_at,'received_at',e.received_at,'media',coalesce((select jsonb_agg(jsonb_build_object('path',m.object_path,'type',m.mime_type,'name',m.name)) from public.production_media m where m.activity_id=e.id),'[]')) order by e.received_at) from public.production_activity e where e.order_id=o.id and e.customer_visible),'[]')) into result from public.production_orders o join public.production_sites s on s.id=o.site_id where o.id=rid;
 return result;
end $$;
create function public.production_tracking(p_token text) returns jsonb language sql stable security definer set search_path='' as $$ select private.production_tracking_impl(p_token) $$;

alter table public.production_customers enable row level security;
revoke all on public.production_customers from public,anon,authenticated;grant select on public.production_customers to authenticated;grant all on public.production_customers to service_role;
create policy production_customers_read on public.production_customers for select to authenticated using(private.production_reader(business_unit_id));

alter table public.production_sites enable row level security;
revoke all on public.production_sites from public,anon,authenticated;grant select on public.production_sites to authenticated;grant all on public.production_sites to service_role;
create policy production_sites_read on public.production_sites for select to authenticated using(exists(select 1 from public.production_customers c where c.id=customer_id and private.production_reader(c.business_unit_id)));

alter table public.production_products enable row level security;
revoke all on public.production_products from public,anon,authenticated;grant select on public.production_products to authenticated;grant all on public.production_products to service_role;
create policy production_products_read on public.production_products for select to authenticated using(private.production_reader(business_unit_id));

alter table public.production_drivers enable row level security;
revoke all on public.production_drivers from public,anon,authenticated;grant select on public.production_drivers to authenticated;grant all on public.production_drivers to service_role;
create policy production_drivers_read on public.production_drivers for select to authenticated using(user_id=(select auth.uid()) or private.production_reader(fleet_unit_id));

alter table public.production_orders enable row level security;
revoke all on public.production_orders from public,anon,authenticated;grant select on public.production_orders to authenticated;grant all on public.production_orders to service_role;
create policy production_orders_read on public.production_orders for select to authenticated using(private.production_order_access(id));

alter table public.production_loads enable row level security;
revoke all on public.production_loads from public,anon,authenticated;grant select on public.production_loads to authenticated;grant all on public.production_loads to service_role;
create policy production_loads_read on public.production_loads for select to authenticated using(private.production_load_access(id));

alter table public.production_activity enable row level security;
revoke all on public.production_activity from public,anon,authenticated;grant select on public.production_activity to authenticated;grant all on public.production_activity to service_role;
create policy production_activity_read on public.production_activity for select to authenticated using((load_id is not null and private.production_load_access(load_id)) or (load_id is null and private.production_order_access(order_id)));

alter table public.production_media enable row level security;
revoke all on public.production_media from public,anon,authenticated;grant select on public.production_media to authenticated;grant all on public.production_media to service_role;
create policy production_media_read on public.production_media for select to authenticated using(exists(select 1 from public.production_activity e where e.id=activity_id and e.load_id is not null and private.production_load_access(e.load_id)));
create index production_customers_business_unit_id_idx on public.production_customers(business_unit_id);
create index production_sites_customer_id_idx on public.production_sites(customer_id);
create index production_products_business_unit_id_idx on public.production_products(business_unit_id);
create index production_drivers_fleet_unit_id_idx on public.production_drivers(fleet_unit_id);
create index production_orders_business_unit_id_idx on public.production_orders(business_unit_id);
create index production_orders_customer_id_idx on public.production_orders(customer_id);
create index production_orders_site_id_idx on public.production_orders(site_id);
create index production_orders_product_id_idx on public.production_orders(product_id);
create index production_orders_created_by_idx on public.production_orders(created_by);
create index production_loads_order_id_idx on public.production_loads(order_id);
create index production_loads_fleet_unit_id_idx on public.production_loads(fleet_unit_id);
create index production_loads_driver_id_idx on public.production_loads(driver_id);
create index production_loads_truck_id_idx on public.production_loads(truck_id);
create index production_loads_created_by_idx on public.production_loads(created_by);
create index production_activity_order_id_idx on public.production_activity(order_id);
create index production_activity_load_id_idx on public.production_activity(load_id);
create index production_activity_author_id_idx on public.production_activity(author_id);
create index production_media_activity_id_idx on public.production_media(activity_id);

revoke all on private.production_tracking from public,anon,authenticated;
grant all on private.production_tracking to service_role;
grant usage,select on sequence public.production_orders_order_number_seq,public.production_loads_load_number_seq to service_role;
revoke all on function private.production_manager(uuid),private.production_reader(uuid),private.production_load_access(uuid,boolean),private.production_order_access(uuid),private.production_command_impl(text,jsonb),private.production_workspace_impl(),private.production_tracking_impl(text),public.production_command(text,jsonb),public.production_workspace(),public.production_tracking(text) from public,anon,authenticated;
grant execute on function private.production_manager(uuid),private.production_reader(uuid),private.production_load_access(uuid,boolean),private.production_order_access(uuid),private.production_command_impl(text,jsonb),private.production_workspace_impl(),public.production_command(text,jsonb),public.production_workspace() to authenticated;
grant execute on function public.production_tracking(text) to anon,authenticated,service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('production-evidence','production-evidence',false,20971520,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime','audio/webm','audio/mp4','audio/ogg']) on conflict(id) do nothing;
create function private.production_storage_access(p_path text,p_write boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare pieces text[]:=string_to_array(p_path,'/');begin
 if array_length(pieces,1)<>3 or pieces[1] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false;end if;
 if p_write and pieces[2] is distinct from auth.uid()::text then return false;end if;
 return private.production_load_access(pieces[1]::uuid,p_write);end $$;
revoke all on function private.production_storage_access(text,boolean) from public,anon,authenticated;grant execute on function private.production_storage_access(text,boolean) to authenticated;
create policy production_evidence_read on storage.objects for select to authenticated using(bucket_id='production-evidence' and private.production_storage_access(name,false));
create policy production_evidence_insert on storage.objects for insert to authenticated with check(bucket_id='production-evidence' and private.production_storage_access(name,true));
