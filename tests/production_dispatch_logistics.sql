begin;
create function pg_temp.qa_plan_tracking(t text) returns jsonb language sql security definer set search_path='' as $$select public.production_tracking(t)$$;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where active and personnel_category='ceo' limit 1),true);
set local role authenticated;
do $$
declare actor uuid:=auth.uid();unit uuid;fleet uuid;driver uuid;truck uuid;cust uuid;site uuid;prod uuid;ord uuid;legacy uuid;loadid uuid;legacyload uuid;s1 uuid:=gen_random_uuid();s2 uuid:=gen_random_uuid();s3 uuid:=gen_random_uuid();plan jsonb;changed jsonb;payload jsonb;response jsonb;token text;key uuid;bad boolean;version integer;
begin
 select id into strict unit from public.business_units where code='CONC-PR';select id into strict fleet from public.business_units where code='MOBILE-PR';
 select p.id into strict driver from public.profiles p join public.user_unit_access a on a.user_id=p.id where p.active and p.full_name like '[MOC]%' and a.business_unit_id=fleet limit 1;
 perform public.production_command('driver',jsonb_build_object('business_unit_id',fleet,'user_id',driver));
 select id into strict truck from public.assets where business_unit_id=fleet and status='active' limit 1;
 cust:=(public.production_command('customer',jsonb_build_object('business_unit_id',unit,'name','[QA rollback] Dispatch logistics customer'))->>'id')::uuid;
 site:=(public.production_command('site',jsonb_build_object('business_unit_id',unit,'customer_id',cust,'name','QA logistics site','address','QA no real delivery'))->>'id')::uuid;
 prod:=(public.production_command('product',jsonb_build_object('business_unit_id',unit,'name','QA mix','unit','m³','kind','product'))->>'id')::uuid;
 plan:=jsonb_build_object('trucks',2,'notes','INTERNAL logistics note','slots',jsonb_build_array(
 jsonb_build_object('id',s1,'quantity',7,'departure_at',now()+interval '1 day','arrival_at',now()+interval '25 hours'),
 jsonb_build_object('id',s2,'quantity',7,'departure_at',now()+interval '24 hours 30 minutes','arrival_at',now()+interval '25 hours 30 minutes'),
 jsonb_build_object('id',s3,'quantity',6,'departure_at',now()+interval '25 hours','arrival_at',now()+interval '26 hours')));
 payload:=jsonb_build_object('request_id',gen_random_uuid(),'business_unit_id',unit,'customer_id',cust,'site_id',site,'product_id',prod,'quantity',20,'due_at',now()+interval '25 hours','dispatch_plan',plan);
 ord:=(public.production_command('order',payload)->>'id')::uuid;
 if (public.production_command('order',payload)->>'id')::uuid<>ord or (select logistics_version from public.production_orders where id=ord)<>1 then raise exception 'Creation retry duplicated or rewrote plan';end if;
 bad:=false;begin perform public.production_command('order',(payload-'customer_id'-'site_id')||jsonb_build_object('request_id',gen_random_uuid(),'new_customer',jsonb_build_object('name','[QA rollback] Invalid-plan inline customer'),'new_site',jsonb_build_object('name','QA invalid-plan site','address','QA'),'dispatch_plan',jsonb_set(plan,'{slots,2,quantity}','5')));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Invalid plan committed new order';end if;
 if exists(select 1 from public.production_customers where business_unit_id=unit and name='[QA rollback] Invalid-plan inline customer') then raise exception 'Invalid plan left an inline customer behind';end if;
 if exists(select 1 from public.production_loads where order_id=ord) then raise exception 'Logistics fabricated an assigned/produced delivery';end if;
 if (select dispatch_plan->>'trucks' from public.production_orders where id=ord)<>'2' then raise exception 'Truck count missing';end if;
 bad:=false;begin perform public.production_dispatch_plan(ord,0,plan,actor,gen_random_uuid());exception when raise_exception then bad:=true;end;if not bad then raise exception 'Stale plan accepted';end if;
 bad:=false;begin perform public.production_dispatch_plan(ord,1,jsonb_set(plan,'{slots,2,quantity}','5'),actor,gen_random_uuid());exception when raise_exception then bad:=true;end;if not bad then raise exception 'Plan total mismatch accepted';end if;
 bad:=false;begin perform public.production_dispatch_plan(ord,1,jsonb_set(plan,'{slots,1,id}',to_jsonb(s1)),actor,gen_random_uuid());exception when raise_exception then bad:=true;end;if not bad then raise exception 'Duplicate slot accepted';end if;
 bad:=false;begin perform public.production_dispatch_plan(ord,1,plan,driver,gen_random_uuid());exception when raise_exception then bad:=true;end;if not bad then raise exception 'Forged plan actor accepted';end if;
 bad:=false;begin perform public.production_command('schedule',jsonb_build_object('order_id',ord,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',7));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Planned order scheduled without a trip';end if;
 bad:=false;begin perform public.production_command('schedule',jsonb_build_object('order_id',ord,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',8,'dispatch_slot_id',s1,'logistics_version',1));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Trip quantity changed on assignment';end if;
 loadid:=(public.production_command('schedule',jsonb_build_object('order_id',ord,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',7,'dispatch_slot_id',s1,'logistics_version',1))->>'id')::uuid;
 if (select planned_departure_at from public.production_loads where id=loadid) is distinct from (plan->'slots'->0->>'departure_at')::timestamptz or (select departed_at from public.production_loads where id=loadid) is not null then raise exception 'Assignment lost plan or inferred actual departure';end if;
 bad:=false;begin perform public.production_command('schedule',jsonb_build_object('order_id',ord,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',7,'dispatch_slot_id',s1,'logistics_version',1));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Trip assigned twice';end if;
 key:=gen_random_uuid();perform public.production_dispatch_plan(ord,1,plan,actor,key);perform public.production_dispatch_plan(ord,1,plan,actor,key);
 if (select logistics_version from public.production_orders where id=ord)<>2 then raise exception 'Plan retry incremented revision twice';end if;
 bad:=false;begin perform public.production_dispatch_plan(ord,1,jsonb_set(plan,'{notes}','"Changed retry"'),actor,key);exception when raise_exception then bad:=true;end;if not bad then raise exception 'Changed retry payload accepted';end if;
 token:=public.production_command('tracking',jsonb_build_object('order_id',ord))->>'token';response:=pg_temp.qa_plan_tracking(token);
 if (response->'loads'->0->>'planned_departure_at')::timestamptz is distinct from (plan->'slots'->0->>'departure_at')::timestamptz or response::text like '%INTERNAL logistics note%' then raise exception 'Customer schedule missing or private plan notes exposed';end if;
 perform public.production_command('produce',jsonb_build_object('load_id',loadid));perform set_config('request.jwt.claim.sub',driver::text,true);
 bad:=false;begin perform public.production_dispatch_plan(ord,2,plan,driver,gen_random_uuid());exception when raise_exception then bad:=true;end;if not bad then raise exception 'Driver edits dispatch logistics';end if;
 perform public.production_command('event',jsonb_build_object('load_id',loadid,'event','departed'));
 perform set_config('request.jwt.claim.sub',actor::text,true);
 changed:=jsonb_set(plan,'{slots,0,departure_at}',to_jsonb(now()+interval '24 hours 10 minutes'));
 bad:=false;begin perform public.production_dispatch_plan(ord,2,changed,actor,gen_random_uuid());exception when raise_exception then bad:=true;end;if not bad then raise exception 'Started trip plan rewritten';end if;
 changed:=jsonb_set(plan,'{slots,1,departure_at}',to_jsonb(now()+interval '24 hours 40 minutes'));
 perform public.production_dispatch_plan(ord,2,changed,actor,gen_random_uuid());
 if (select status from public.production_loads where id=loadid)<>'departed' or (select status from public.production_orders where id=ord)<>'confirmed' then raise exception 'Plan changed actual workflow';end if;
 perform public.production_command('reference',jsonb_build_object('order_id',ord,'external_number','QA-AIMSIO-PLAN'));
 if (select logistics_version from public.production_orders where id=ord)<>3 then raise exception 'Reference edit changed plan history';end if;
 -- Legacy unstarted assignments can adopt rows with their existing load IDs.
 payload:=payload-'dispatch_plan';payload:=jsonb_set(payload,'{request_id}',to_jsonb(gen_random_uuid()));
 legacy:=(public.production_command('order',payload)->>'id')::uuid;
 legacyload:=(public.production_command('schedule',jsonb_build_object('order_id',legacy,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',20))->>'id')::uuid;
 changed:=jsonb_build_object('trucks',1,'notes','','slots',jsonb_build_array(jsonb_build_object('id',legacyload,'quantity',20,'departure_at',now()+interval '2 days','arrival_at',now()+interval '49 hours')));
 perform public.production_dispatch_plan(legacy,0,changed,actor,gen_random_uuid());
 if (select dispatch_slot_id from public.production_loads where id=legacyload) is distinct from legacyload then raise exception 'Legacy assignment was not adopted';end if;
 if (select count(*) from public.production_activity where order_id=ord and kind='logistics_updated')<>3 then raise exception 'Plan audit history missing';end if;
 bad:=false;begin update public.production_orders set dispatch_plan=null where id=ord;exception when insufficient_privilege then bad:=true;end;if not bad then raise exception 'Client bypasses plan API';end if;
end $$;
set local role anon;
do $$begin if has_function_privilege('anon','public.production_dispatch_plan(uuid,integer,jsonb,uuid,uuid)','execute') then raise exception 'Anonymous plan API';end if;end$$;
reset role;
select 'production_dispatch_logistics_passed' as result;
rollback;
