-- Order discussion exists before any delivery load and follows the permanent order ID.
create function private.production_order_conversation(p_order uuid,p_before uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare anchor public.production_activity%rowtype;result jsonb;
begin
 if not private.production_order_access(p_order) or not exists(select 1 from public.profiles where id=auth.uid() and active) then raise exception 'Order access denied';end if;
 if p_before is not null then
 select * into anchor from public.production_activity where id=p_before and order_id=p_order and load_id is null and kind='message';
 if anchor.id is null then raise exception 'Invalid conversation cursor';end if;end if;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.received_at,e.id),'[]'::jsonb) into result from (
 select a.id,a.order_id,a.author_id,coalesce(nullif(p.full_name,''),'Team member') as author_name,a.body,a.captured_at,a.received_at
 from public.production_activity a join public.profiles p on p.id=a.author_id
 where a.order_id=p_order and a.load_id is null and a.kind='message' and (p_before is null or (a.received_at,a.id)<(anchor.received_at,anchor.id))
 order by a.received_at desc,a.id desc limit 50) e;
 return result;
end $$;
create function public.production_order_conversation(p_order_id uuid,p_before_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.production_order_conversation(p_order_id,p_before_id)$$;
revoke all on function private.production_order_conversation(uuid,uuid),public.production_order_conversation(uuid,uuid) from public,anon,authenticated;
grant execute on function private.production_order_conversation(uuid,uuid),public.production_order_conversation(uuid,uuid) to authenticated;

create function private.production_order_message(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();rid uuid:=nullif(p_data->>'order_id','')::uuid;k uuid:=nullif(p_data->>'client_id','')::uuid;msg text:=btrim(p_data->>'body');at_time timestamptz:=coalesce(nullif(p_data->>'captured_at','')::timestamptz,now());o public.production_orders%rowtype;ev public.production_activity%rowtype;recipient uuid;label text;
begin
 if actor is null or p_data->>'actor_id' is distinct from actor::text or not exists(select 1 from public.profiles where id=actor and active) or not private.production_order_access(rid) then raise exception 'Authorized order access required for this account';end if;
 if k is null or msg is null or length(msg) not between 1 and 10000 or nullif(p_data->>'load_id','') is not null then raise exception 'Enter an order message of 1 to 10000 characters';end if;
 select * into o from public.production_orders where id=rid for update;
 select * into ev from public.production_activity where client_id=k;
 if ev.id is not null then
 if ev.author_id<>actor or ev.order_id<>rid or ev.load_id is not null or ev.kind<>'message' or ev.payload is distinct from p_data then raise exception 'Request identifier already used for different data';end if;return jsonb_build_object('id',ev.id,'replayed',true);end if;
 if at_time>now()+interval '5 minutes' or at_time<o.created_at-interval '5 minutes' then raise exception 'Invalid message time; check device clock';end if;
 select full_name into label from public.profiles where id=actor;
 -- Order discussion is internal, irrespective of a browser-supplied visibility flag.
 insert into public.production_activity(order_id,author_id,kind,body,customer_visible,captured_at,client_id,payload) values(rid,actor,'message',msg,false,at_time,k,p_data) returning * into ev;
 for recipient in
 select distinct p.id from public.profiles p where p.active and p.id<>actor
 and ((p.role='super_admin' and p.personnel_category in ('ceo','manager','shareholder','administration'))
 or (p.personnel_category in ('ceo','shareholder','manager','supervisor') and (p.role in ('super_admin','corporate_manager') or exists(select 1 from public.user_unit_access a where a.user_id=p.id and (a.business_unit_id=o.business_unit_id or exists(select 1 from public.production_loads l where l.order_id=rid and l.fleet_unit_id=a.business_unit_id)))))
 or exists(select 1 from public.production_loads l join public.production_drivers d on d.user_id=l.driver_id join public.user_unit_access a on a.user_id=d.user_id and a.business_unit_id=d.fleet_unit_id where l.order_id=rid and l.driver_id=p.id and d.active and d.fleet_unit_id=l.fleet_unit_id))
 and (
 p.id=o.created_by or exists(select 1 from public.production_activity a where a.order_id=rid and a.load_id is null and a.kind='message' and a.author_id=p.id)
 or exists(select 1 from public.production_loads l join public.production_drivers d on d.user_id=l.driver_id join public.user_unit_access u on u.user_id=d.user_id and u.business_unit_id=d.fleet_unit_id where l.order_id=rid and l.driver_id=p.id and l.status<>'cancelled' and d.active and d.fleet_unit_id=l.fleet_unit_id)
 or (p.personnel_category='manager' and exists(select 1 from public.user_unit_access u where u.user_id=p.id and u.business_unit_id=o.business_unit_id and u.can_edit)))
 loop
 insert into public.notifications(user_id,production_order_id,business_unit_id,notification_type,severity,title,message,dedupe_key) values(recipient,rid,o.business_unit_id,'production_activity','info','New order message · '||coalesce(o.external_number,'TEMP-'||o.order_number),coalesce(label,'Team member')||': '||left(msg,400),'order-chat:'||ev.id||':'||recipient);
 end loop;
 return jsonb_build_object('id',ev.id);
end $$;
create function public.production_order_message(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.production_order_message(p_data)$$;
revoke all on function private.production_order_message(jsonb),public.production_order_message(jsonb) from public,anon,authenticated;
grant execute on function private.production_order_message(jsonb),public.production_order_message(jsonb) to authenticated;
create index production_activity_order_conversation on public.production_activity(order_id,received_at desc,id desc) where load_id is null and kind='message';
