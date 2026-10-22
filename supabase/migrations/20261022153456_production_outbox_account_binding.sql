-- Bind queued updates to their originating account and notify the actual dispatcher.
create or replace function private.production_command_impl(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();u uuid;rid uuid;lid uuid;cid uuid;pid uuid;sid uuid;key uuid;at_time timestamptz;body text;visible boolean; old_ref text; o public.production_orders%rowtype;l public.production_loads%rowtype;pr public.production_products%rowtype;ev public.production_activity%rowtype; token text; path text; recipient uuid;
begin
 if p_data ? 'actor_id' and (p_data->>'actor_id') is distinct from actor::text then raise exception 'This queued update belongs to another account';end if;
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
 for recipient in select distinct x from unnest(array[o.created_by,l.created_by,l.driver_id]) as t(x) where x is not null and x<>actor loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,rid,case when recipient=l.driver_id then l.fleet_unit_id else o.business_unit_id end,'production_activity','info','Delivery · '||coalesce(o.external_number,'TEMP-'||o.order_number),left(body,500),'production:'||ev.id||':'||recipient);
 end loop;
 return jsonb_build_object('id',coalesce(lid,ev.id));
end $$;
