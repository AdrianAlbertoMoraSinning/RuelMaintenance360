-- Actual quantities may differ from programmed totals. Every explicit closure records variance.
alter table public.production_activity drop constraint production_activity_kind_check;
alter table public.production_activity add constraint production_activity_kind_check check(kind in ('order_created','reference_changed','scheduled','produced','departed','arrived','completed','site_left','cancelled','message','attachment','geofences_updated','logistics_updated','quantity_changed','order_closed'));
CREATE OR REPLACE FUNCTION private.set_dispatch_plan(p_order uuid, p_version integer, p_plan jsonb, p_actor uuid, p_client uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();o public.production_orders%rowtype;l public.production_loads%rowtype;ev public.production_activity%rowtype;slot jsonb;clean jsonb:='[]';ids uuid[]:='{}';sid uuid;q numeric;total numeric:=0;dep timestamptz;arr timestamptz;previous timestamptz;trucks integer;canonical jsonb;recipient uuid;planned_driver uuid;driver_label text;assigned_driver uuid;
begin
 if actor is null or actor is distinct from p_actor or p_client is null then raise exception 'Active manager identity and request identifier required';end if;
 select * into o from public.production_orders where id=p_order for update;
 if o.id is null or not private.production_manager(o.business_unit_id) then raise exception 'Order manager access required';end if;
 select * into ev from public.production_activity where client_id=p_client;
 if ev.id is not null then
 if ev.kind<>'logistics_updated' or ev.order_id<>p_order or ev.author_id<>actor or ev.payload->'plan' is distinct from p_plan or (ev.payload->>'expected_version')::integer is distinct from p_version then raise exception 'Plan request already used for different data';end if;
 return jsonb_build_object('version',o.logistics_version,'replayed',true);end if;
 if o.status<>'confirmed' then raise exception 'Only open orders can change dispatch logistics';end if;
 if o.logistics_version is distinct from p_version then raise exception 'The dispatch plan changed. Cancel editing and review the latest plan';end if;
 if jsonb_typeof(p_plan) is distinct from 'object' or octet_length(p_plan::text)>100000 or jsonb_typeof(p_plan->'slots') is distinct from 'array' then raise exception 'Provide dispatch loads';end if;
 if jsonb_array_length(p_plan->'slots') not between 1 and 100 or coalesce(p_plan->>'trucks','') !~ '^[0-9]{1,3}$' or length(coalesce(p_plan->>'notes',''))>2000 then raise exception 'Use 1–100 loads, 1–100 trucks and notes up to 2000 characters';end if;
 trucks:=(p_plan->>'trucks')::integer;if trucks not between 1 and 100 then raise exception 'Enter 1–100 available trucks';end if;
 for slot in select value from jsonb_array_elements(p_plan->'slots') loop
 sid:=(slot->>'id')::uuid;q:=(slot->>'quantity')::numeric;dep:=(slot->>'departure_at')::timestamptz;arr:=nullif(slot->>'arrival_at','')::timestamptz;
 if sid is null or sid=any(ids) or q is null or q::text in ('NaN','Infinity','-Infinity') or q<=0 or q>100000000 or q<>round(q,3) or dep is null or not isfinite(dep) or (arr is not null and (not isfinite(arr) or arr<dep)) or (previous is not null and dep<previous) then raise exception 'Check load identifiers, quantities and chronological departure / arrival times';end if;
 ids:=array_append(ids,sid);total:=total+q;previous:=dep;
 planned_driver:=nullif(slot->>'driver_id','')::uuid;driver_label:=null;
 select driver_id into assigned_driver from public.production_loads where order_id=p_order and status<>'cancelled' and coalesce(dispatch_slot_id,id)=sid;
 if assigned_driver is not null then
 if planned_driver is not null and planned_driver<>assigned_driver then raise exception 'Assigned trips keep their delivery driver';end if;
 planned_driver:=assigned_driver;
 select full_name into driver_label from public.profiles where id=planned_driver;
 elsif planned_driver is not null then
 select p.full_name into driver_label from public.production_drivers d join public.profiles p on p.id=d.user_id join public.business_units b on b.id=d.fleet_unit_id join public.user_unit_access a on a.user_id=d.user_id and a.business_unit_id=d.fleet_unit_id where d.user_id=planned_driver and d.active and p.active and b.code='MOBILE-PR';
 if not found then raise exception 'Choose an enrolled active Mobile Concrete Fleet driver';end if;
 end if;
 clean:=clean||jsonb_build_array(jsonb_build_object('id',sid,'quantity',q,'departure_at',dep,'arrival_at',arr,'driver_id',planned_driver,'driver_name',driver_label));
 end loop;

 if (select count(distinct truck_id) from public.production_loads where order_id=p_order and status<>'cancelled')>trucks then raise exception 'Available truck count is below the vehicles already assigned';end if;
 for l in select * from public.production_loads where order_id=p_order and status<>'cancelled' order by id for update loop
 select value into slot from jsonb_array_elements(clean) where value->>'id'=coalesce(l.dispatch_slot_id,l.id)::text;
 if slot is null or (slot->>'quantity')::numeric is distinct from coalesce((select (old->>'quantity')::numeric from jsonb_array_elements(o.dispatch_plan->'slots') old where old->>'id'=coalesce(l.dispatch_slot_id,l.id)::text),l.quantity) then raise exception 'Keep every assigned load and its original planned quantity in the plan';end if;
 if l.status not in ('scheduled','ready') and (l.dispatch_slot_id is null or l.planned_departure_at is distinct from (slot->>'departure_at')::timestamptz or l.required_arrival_at is distinct from (slot->>'arrival_at')::timestamptz) then raise exception 'Started trips keep their saved plan. Configure logistics before departure';end if;
 update public.production_loads set dispatch_slot_id=(slot->>'id')::uuid,planned_departure_at=(slot->>'departure_at')::timestamptz,required_arrival_at=(slot->>'arrival_at')::timestamptz where id=l.id;
 end loop;
 canonical:=jsonb_build_object('trucks',trucks,'notes',coalesce(p_plan->>'notes',''),'slots',clean);
 update public.production_orders set dispatch_plan=canonical,logistics_version=logistics_version+1 where id=p_order;
 insert into public.production_activity(order_id,author_id,kind,body,client_id,payload) values(p_order,actor,'logistics_updated','Dispatch logistics saved · '||jsonb_array_length(clean)||' loads / trips · '||trucks||' available trucks',p_client,jsonb_build_object('plan',p_plan,'expected_version',p_version,'saved_plan',canonical));
 for recipient in select distinct x from (select o.created_by x union select driver_id from public.production_loads where order_id=p_order and status in ('scheduled','ready')) a join public.profiles p on p.id=a.x and p.active where x<>actor loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,p_order,o.business_unit_id,'production_activity','info','Dispatch logistics updated','Review the planned departure and arrival times for order '||coalesce(o.external_number,'TEMP-'||o.order_number),'logistics:'||p_client||':'||recipient);
 end loop;
 return jsonb_build_object('version',o.logistics_version+1);
end $function$;
CREATE OR REPLACE FUNCTION private.production_command_impl(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();u uuid;rid uuid;lid uuid;cid uuid;pid uuid;sid uuid;key uuid;at_time timestamptz;body text;visible boolean; old_ref text; o public.production_orders%rowtype;l public.production_loads%rowtype;pr public.production_products%rowtype;ev public.production_activity%rowtype; token text; path text; recipient uuid;dispatch_slot jsonb;slot_id uuid;actual_q numeric;total_dispatched numeric;total_delivered numeric;difference numeric;cancelled_count integer;audit_extra jsonb:='{}';dispatcher boolean:=p_action in ('dispatch','dispatch_event');
begin
 if dispatcher then
 if p_action='dispatch' then p_data:=p_data||jsonb_build_object('event','departed');end if;
 if p_data->>'event' is null or p_data->>'event' not in ('departed','arrived','site_left','completed') then raise exception 'Choose a valid delivery milestone';end if;
 p_data:=p_data||jsonb_build_object('source','dispatcher');end if;
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
 insert into public.production_products(business_unit_id,name,unit,kind,reference_code,catalogue_description) values(u,case when nullif(btrim(p_data->>'reference_code'),'') is not null then btrim(p_data->>'reference_code')||' — '||btrim(p_data->>'name') else btrim(p_data->>'name') end,p_data->>'unit',p_data->>'kind',nullif(btrim(p_data->>'reference_code'),''),btrim(p_data->>'name')) returning id into pid;return jsonb_build_object('id',pid);
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
 insert into public.production_activity(order_id,author_id,kind,body,customer_visible,client_id,payload) values(o.id,actor,'order_created','Order confirmed',true,gen_random_uuid(),p_data);if p_data ? 'dispatch_plan' then perform private.set_dispatch_plan(o.id,0,p_data->'dispatch_plan',actor,gen_random_uuid());end if;return jsonb_build_object('id',o.id);
 end if;
 if lid is not null then select * into l from public.production_loads where id=lid;rid:=l.order_id;end if;
 select * into o from public.production_orders where id=rid for update;
 if o.id is null then raise exception 'Order not found';end if;
 if p_action in ('reference','schedule','produce','dispatch','dispatch_event','tracking','cancel_order','load_quantity','close_order') and not private.production_manager(o.business_unit_id) then raise exception 'Manager access required';end if;
 if lid is not null then select * into l from public.production_loads where id=lid for update;if not private.production_load_access(lid,true) then raise exception 'Service access denied';end if;end if;
 key:=coalesce(nullif(p_data->>'client_id','')::uuid,gen_random_uuid());
 select * into ev from public.production_activity where client_id=key;
 if ev.id is not null then
 if ev.author_id<>actor or ev.order_id<>rid or ev.payload->>'load_id' is distinct from p_data->>'load_id' or (ev.payload-'audit') is distinct from p_data then raise exception 'Request identifier already used for different data';end if;
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
 if o.dispatch_plan is not null then
 if coalesce((p_data->>'logistics_version')::integer,-1)<>o.logistics_version then raise exception 'Dispatch plan changed. Refresh before assigning a trip';end if;
 slot_id:=nullif(p_data->>'dispatch_slot_id','')::uuid;
 if slot_id is null and not (p_data ? 'dispatch_slot_id') then raise exception 'Choose a planned trip or explicitly select an additional delivery';end if;
 select value into dispatch_slot from jsonb_array_elements(o.dispatch_plan->'slots') where value->>'id'=slot_id::text;
 if slot_id is not null and dispatch_slot is null then raise exception 'Select an unassigned planned trip or an additional delivery';end if;
 if nullif(dispatch_slot->>'driver_id','') is not null and (dispatch_slot->>'driver_id')::uuid is distinct from (p_data->>'driver_id')::uuid then raise exception 'Use the driver selected in dispatch logistics, or edit the plan first';end if;
 if exists(select 1 from public.production_loads where order_id=rid and dispatch_slot_id=slot_id and status<>'cancelled') then raise exception 'This planned trip is already assigned';end if;
 if (select count(distinct truck_id) from (select truck_id from public.production_loads where order_id=rid and status<>'cancelled' union select (p_data->>'truck_id')::uuid) t)>(o.dispatch_plan->>'trucks')::integer then raise exception 'Assignment exceeds the planned available truck count';end if;
 end if;
 u:=(p_data->>'fleet_unit_id')::uuid;
 if not exists(select 1 from public.production_drivers d join public.profiles p on p.id=d.user_id join public.user_unit_access a on a.user_id=p.id and a.business_unit_id=d.fleet_unit_id where d.user_id=(p_data->>'driver_id')::uuid and d.fleet_unit_id=u and d.active and p.active) then raise exception 'Choose an enrolled active fleet driver';end if;
 if not exists(select 1 from public.assets where id=(p_data->>'truck_id')::uuid and business_unit_id=u and status='active') then raise exception 'Choose an active fleet vehicle';end if;
 actual_q:=nullif(p_data->>'quantity','')::numeric;
 if actual_q is null or actual_q::text in ('NaN','Infinity','-Infinity') or actual_q<=0 or actual_q>100000000 or actual_q<>round(actual_q,3) then raise exception 'Enter a positive load quantity with up to three decimals';end if;
 insert into public.production_loads(order_id,fleet_unit_id,driver_id,truck_id,quantity,created_by) values(rid,u,(p_data->>'driver_id')::uuid,(p_data->>'truck_id')::uuid,(p_data->>'quantity')::numeric,actor) returning * into l;
 if dispatch_slot is not null then update public.production_loads set dispatch_slot_id=slot_id,planned_departure_at=(dispatch_slot->>'departure_at')::timestamptz,required_arrival_at=(dispatch_slot->>'arrival_at')::timestamptz where id=l.id;end if;
 lid:=l.id;p_action:='scheduled';body:='Delivery assigned';
 elsif p_action='load_quantity' then
 if o.status<>'confirmed' or l.id is null or l.status not in ('scheduled','ready') or l.departed_at is not null then raise exception 'Adjust quantities only on open orders before departure';end if;
 if nullif(p_data->>'client_id','') is null then raise exception 'Request identifier required';end if;
 if l.quantity is distinct from (p_data->>'expected_quantity')::numeric then raise exception 'Load quantity changed. Refresh and review';end if;
 actual_q:=nullif(p_data->>'quantity','')::numeric;
 if actual_q is null or actual_q::text in ('NaN','Infinity','-Infinity') or actual_q<=0 or actual_q>100000000 or actual_q<>round(actual_q,3) then raise exception 'Enter a positive load quantity with up to three decimals';end if;
 if length(btrim(coalesce(p_data->>'reason',''))) not between 1 and 2000 then raise exception 'Enter a reason for the quantity adjustment';end if;
 audit_extra:=jsonb_build_object('previous_quantity',l.quantity);
 update public.production_loads set quantity=actual_q where id=lid;
 body:='Load quantity adjusted · '||l.quantity||' → '||actual_q||' '||o.unit||' · '||btrim(p_data->>'reason');p_action:='quantity_changed';visible:=true;
 elsif p_action='close_order' then
 if o.status<>'confirmed' then raise exception 'Only open orders can be closed';end if;
 if lid is not null or nullif(p_data->>'client_id','') is null then raise exception 'Order and request identifier required';end if;
 if exists(select 1 from public.production_loads where order_id=rid and status in ('ready','departed','arrived')) or not exists(select 1 from public.production_loads where order_id=rid and status='completed') then raise exception 'Complete deliveries and finish every produced or travelling load before closure';end if;
 select coalesce(sum(quantity) filter(where departed_at is not null),0),coalesce(sum(quantity) filter(where status='completed'),0) into total_dispatched,total_delivered from public.production_loads where order_id=rid and status<>'cancelled';
 if total_dispatched is distinct from (p_data->>'expected_dispatched')::numeric or total_delivered is distinct from (p_data->>'expected_delivered')::numeric then raise exception 'Dispatch totals changed. Refresh and review before closing';end if;
 difference:=total_dispatched-o.quantity;
 if length(coalesce(p_data->>'reason',''))>2000 or (difference<>0 and length(btrim(coalesce(p_data->>'reason','')))=0) then raise exception 'Enter a closure reason for the quantity difference';end if;
 update public.production_loads set status='cancelled' where order_id=rid and status='scheduled';get diagnostics cancelled_count=row_count;
 update public.production_orders set status='completed' where id=rid;
 body:='Dispatch order closed · programmed '||o.quantity||' '||o.unit||' · dispatched '||total_dispatched||' · delivered '||total_delivered||' · difference '||difference||' · '||coalesce(p_data->>'reason','');
 audit_extra:=jsonb_build_object('programmed_quantity',o.quantity,'dispatched_quantity',total_dispatched,'delivered_quantity',total_delivered,'variance',difference,'cancelled_unproduced_loads',cancelled_count);p_action:='order_closed';visible:=true;
 elsif p_action='produce' then
 if o.status<>'confirmed' or l.id is null or l.status<>'scheduled' then raise exception 'Load must be scheduled';end if;
 update public.production_loads set produced_at=now(),status='ready' where id=lid;p_action:='produced';body:='Production confirmed · '||l.quantity||' '||o.unit;
 elsif p_action in ('event','dispatch','dispatch_event') then
 if l.id is null then raise exception 'Select a delivery';end if;
 if not dispatcher and not exists(select 1 from public.production_drivers d where d.user_id=actor and d.user_id=l.driver_id and d.active) then raise exception 'Only the assigned driver can record delivery events';end if;
 -- A delayed manual/offline click acknowledges the GPS milestone already recorded.
 -- Completion is never inferred, and the assigned-driver/access checks still apply.
 if p_data->>'event' in ('departed','arrived','site_left','completed') and exists(select 1 from public.production_activity where load_id=lid and kind=p_data->>'event' and payload->>'source' in ('geofence','dispatcher')) then
 return jsonb_build_object('id',lid,'already_recorded',true);end if;
 p_action:=p_data->>'event';visible:=true;
 if p_action='site_left' and not dispatcher then raise exception 'Only an order manager can record manual jobsite departure';end if;
 if dispatcher and p_action='completed' and l.left_site_at is null then raise exception 'Confirm jobsite departure before manually completing this delivery';end if;
 if p_action='departed' and l.status='ready' and o.status='confirmed' then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(l.driver_id::text,360));perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(l.truck_id::text,361));
 if exists(select 1 from public.production_loads where (driver_id=l.driver_id or truck_id=l.truck_id) and status in ('departed','arrived')) then raise exception 'Complete your current delivery first';end if;
 update public.production_loads set status='departed',departed_at=at_time where id=lid;body:=case when dispatcher then 'Dispatcher confirmed departure from plant' else 'Delivery departed the plant' end;
 elsif p_action='arrived' and l.status='departed' and at_time>=l.departed_at then update public.production_loads set status='arrived',arrived_at=at_time where id=lid;body:=case when dispatcher then 'Dispatcher confirmed arrival at jobsite' else 'Driver arrived at the jobsite' end;
 elsif p_action='site_left' and dispatcher and l.status in ('arrived','completed') and l.left_site_at is null and at_time>=coalesce(l.completed_at,l.arrived_at) then
 update public.production_loads set left_site_at=at_time where id=lid;body:='Dispatcher confirmed vehicle left jobsite';
 elsif p_action='completed' and l.status='arrived' and at_time>=(case when dispatcher then coalesce(l.left_site_at,l.arrived_at) else l.arrived_at end) then update public.production_loads set status='completed',completed_at=at_time where id=lid;body:=case when dispatcher then 'Dispatcher confirmed delivery complete' else 'Driver confirmed delivery complete' end;
 if coalesce((select sum(quantity) from public.production_loads where order_id=rid and status='completed'),0)=o.quantity and not exists(select 1 from public.production_loads where order_id=rid and status not in ('completed','cancelled')) and (o.dispatch_plan is null or not exists(select 1 from jsonb_array_elements(o.dispatch_plan->'slots') s where not exists(select 1 from public.production_loads where order_id=rid and dispatch_slot_id=(s->>'id')::uuid and status='completed'))) then update public.production_orders set status='completed' where id=rid;end if;
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
 insert into private.production_tracking(order_id,token_hash,expires_at,created_by,recoverable_token) values(rid,encode(extensions.digest(token,'sha256'),'hex'),now()+interval '90 days',actor,token) on conflict(order_id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,created_by=actor,recoverable_token=excluded.recoverable_token,last_request_id=null;
 return jsonb_build_object('token',token,'expires_days',90);
 elsif p_action='cancel_order' then
 if exists(select 1 from public.production_loads where order_id=rid and status in ('departed','arrived','completed')) then raise exception 'Started deliveries cannot be cancelled';end if;
 update public.production_orders set status='cancelled' where id=rid;update public.production_loads set status='cancelled' where order_id=rid;p_action:='cancelled';body:='Order cancelled';visible:=true;
 else raise exception 'Unknown production action';end if;
 insert into public.production_activity(order_id,load_id,author_id,kind,body,customer_visible,captured_at,client_id,payload) values(rid,lid,actor,p_action,body,visible,at_time,key,case when audit_extra='{}'::jsonb then p_data else p_data||jsonb_build_object('audit',audit_extra) end) returning * into ev;
 if p_action='attachment' then insert into public.production_media(activity_id,object_path,mime_type,name) values(ev.id,path,p_data->>'mime_type',left(p_data->>'name',200));end if;
 for recipient in select distinct x from unnest(array[o.created_by,l.created_by,l.driver_id]) as t(x) where x is not null and (x<>actor or (p_action in ('departed','arrived','site_left','completed') and x=o.created_by)) loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,rid,case when recipient=l.driver_id then l.fleet_unit_id else o.business_unit_id end,'production_activity','info','Delivery · '||coalesce(o.external_number,'TEMP-'||o.order_number),left(body,500),'production:'||ev.id||':'||recipient);
 end loop;
 return jsonb_build_object('id',coalesce(lid,ev.id));
end $function$;
