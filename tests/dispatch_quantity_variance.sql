begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where active and personnel_category='ceo' limit 1),true);
set local role authenticated;
do $$
declare actor uuid:=auth.uid();unit uuid;fleet uuid;driver uuid;truck uuid;cust uuid;site uuid;prod uuid;ord uuid;lid uuid;unused uuid;slot uuid;key uuid;payload jsonb;bad boolean;q numeric;
begin
 select id into strict unit from public.business_units where code='CONC-PR';select id into strict fleet from public.business_units where code='CONC-PR';
 select p.id into strict driver from public.profiles p join public.user_unit_access a on a.user_id=p.id where p.active and p.full_name like '[MOC]%' and a.business_unit_id=fleet and not exists(select 1 from public.production_loads where driver_id=p.id and status in ('departed','arrived')) limit 1;
 perform public.production_command('driver',jsonb_build_object('business_unit_id',fleet,'user_id',driver));
 truck:=public.create_asset_with_parts(jsonb_build_object('business_unit_id',fleet,'responsible_user_id',driver,'asset_code','QA-VARIANCE-'||gen_random_uuid(),'name','QA rollback variance vehicle','asset_category','MIXER_TRUCK'),'[]'::jsonb);
 cust:=(public.production_command('customer',jsonb_build_object('business_unit_id',unit,'name','[QA rollback] Variance customer'))->>'id')::uuid;
 site:=(public.production_command('site',jsonb_build_object('business_unit_id',unit,'customer_id',cust,'name','QA variance','address','QA only'))->>'id')::uuid;
 prod:=(public.production_command('product',jsonb_build_object('business_unit_id',unit,'name','QA variance mix','unit','m³','kind','product'))->>'id')::uuid;
 foreach q in array array[18,22]::numeric[] loop
 slot:=gen_random_uuid();
 ord:=(public.production_command('order',jsonb_build_object('business_unit_id',unit,'customer_id',cust,'site_id',site,'product_id',prod,'quantity',20,'due_at',now()+interval '1 day','request_id',gen_random_uuid(),'dispatch_plan',jsonb_build_object('trucks',1,'notes','','slots',jsonb_build_array(jsonb_build_object('id',slot,'quantity',20,'departure_at',now()+interval '1 day')))))->>'id')::uuid;
 lid:=(public.production_command('schedule',jsonb_build_object('order_id',ord,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',q-1,'dispatch_slot_id',slot,'logistics_version',1))->>'id')::uuid;
 payload:=jsonb_build_object('load_id',lid,'actor_id',actor,'client_id',gen_random_uuid(),'expected_quantity',q-1,'quantity',q,'reason','QA actual batching');
 perform public.production_command('load_quantity',payload);perform public.production_command('load_quantity',payload);
 if (select count(*) from public.production_activity where load_id=lid and kind='quantity_changed')<>1 or (select quantity from public.production_loads where id=lid)<>q then raise exception 'Quantity adjustment/retry failed';end if;
 -- The original plan can still be saved after the actual quantity changes.
 perform public.production_dispatch_plan(ord,1,(select dispatch_plan from public.production_orders where id=ord),actor,gen_random_uuid());
 unused:=(public.production_command('schedule',jsonb_build_object('order_id',ord,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',truck,'quantity',1,'dispatch_slot_id',null,'logistics_version',2))->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',driver::text,true);
 bad:=false;begin perform public.production_command('load_quantity',payload||jsonb_build_object('actor_id',driver,'client_id',gen_random_uuid()));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Driver adjusted quantity';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform public.production_command('produce',jsonb_build_object('load_id',lid));
 bad:=false;begin perform public.production_command('close_order',jsonb_build_object('order_id',ord,'actor_id',actor,'client_id',gen_random_uuid(),'expected_dispatched',0,'expected_delivered',0,'reason','QA'));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Ready load closed';end if;
 perform public.production_command('dispatch_event',jsonb_build_object('load_id',lid,'event','departed','actor_id',actor,'client_id',gen_random_uuid()));
 bad:=false;begin perform public.production_command('load_quantity',payload||jsonb_build_object('client_id',gen_random_uuid(),'expected_quantity',q,'quantity',q+1));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Departed quantity changed';end if;
 perform public.production_command('dispatch_event',jsonb_build_object('load_id',lid,'event','arrived','actor_id',actor,'client_id',gen_random_uuid()));
 perform public.production_command('dispatch_event',jsonb_build_object('load_id',lid,'event','site_left','actor_id',actor,'client_id',gen_random_uuid()));
 perform public.production_command('dispatch_event',jsonb_build_object('load_id',lid,'event','completed','actor_id',actor,'client_id',gen_random_uuid()));
 if (select status from public.production_orders where id=ord)<>'confirmed' then raise exception 'Variance silently closed order';end if;
 payload:=jsonb_build_object('order_id',ord,'actor_id',actor,'client_id',gen_random_uuid(),'expected_dispatched',q,'expected_delivered',q,'reason','QA customer final quantity');
 bad:=false;begin perform public.production_command('close_order',payload||jsonb_build_object('reason',''));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Missing variance reason accepted';end if;
 bad:=false;begin perform public.production_command('close_order',payload||jsonb_build_object('expected_dispatched',q+1));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Stale totals accepted';end if;
 perform set_config('request.jwt.claim.sub',driver::text,true);
 bad:=false;begin perform public.production_command('close_order',payload||jsonb_build_object('actor_id',driver));exception when raise_exception then bad:=true;end;if not bad then raise exception 'Driver closed order';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform public.production_command('close_order',payload);perform public.production_command('close_order',payload);
 if (select quantity from public.production_orders where id=ord)<>20 or (select status from public.production_orders where id=ord)<>'completed' or (select status from public.production_loads where id=unused)<>'cancelled' then raise exception 'Closure changed program or left pending scheduled load';end if;
 if (select count(*) from public.production_activity a where order_id=ord and kind='order_closed' and (a.payload->'audit'->>'variance')::numeric=q-20)<>1 then raise exception 'Closure audit/retry failed';end if;
 if exists(select 1 from public.production_receipts where load_id=lid) then raise exception 'Closure fabricated customer signature';end if;
 end loop;
end $$;
reset role;
select 'dispatch_quantity_variance_passed' as result;
rollback;
