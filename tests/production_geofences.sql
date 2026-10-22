begin;
-- All fixtures, events and notifications are rolled back.
create function pg_temp.qa_geo_prepare(p_id uuid,p_stage text) returns void language plpgsql security definer set search_path='' as $$begin
 update public.production_loads set produced_at=now()-interval '3 minutes',departed_at=case when p_stage in ('departed','arrived') then now()-interval '2 minutes' else departed_at end,arrived_at=case when p_stage='arrived' then now()-interval '1 minute' else arrived_at end where id=p_id;
 update private.production_geofence_state set last_sample_at=null,candidate=null,candidate_since=null,sample_count=0 where load_id=p_id;
end $$;
create function pg_temp.qa_geo(p_id uuid,p_lat double precision,p_lon double precision,p_seconds integer,p_accuracy double precision default 10) returns jsonb language sql as $$
 select public.production_geofence('sample',jsonb_build_object('actor_id',auth.uid(),'load_id',p_id,'latitude',p_lat,'longitude',p_lon,'accuracy_m',p_accuracy,'sampled_at',now()-make_interval(secs=>p_seconds)))
$$;
create function pg_temp.qa_tracking(p_token text) returns jsonb language sql security definer set search_path='' as $$select public.production_tracking(p_token)$$;
create function pg_temp.qa_geo_notice(p_order uuid,p_user uuid) returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.notifications where user_id=p_user and production_order_id=p_order and message like '%left the jobsite%')$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','ea8946ea-e093-4ad1-a886-954fb91187db',true);
do $$
declare u uuid:='772039c9-622b-430c-90d7-8278adaa42aa';fleet uuid:='8925f6b3-7806-4080-9602-2c2e52da50cf';guy uuid:='ea8946ea-e093-4ad1-a886-954fb91187db';driver uuid:='84c799b3-f64f-402a-9c7e-86907f54e2b8';dj uuid:='b6a1f147-ae25-4b3e-bdb5-f35c5b4addba';c uuid;s uuid;p uuid;o uuid;l uuid;t uuid;token text;failed boolean;r jsonb;old_plant jsonb;
begin
 c:=(public.production_command('customer',jsonb_build_object('business_unit_id',u,'name','TRANSIENT QA geofence customer'))->>'id')::uuid;
 s:=(public.production_command('site',jsonb_build_object('business_unit_id',u,'customer_id',c,'name','TRANSIENT QA geofence site','address','Not a real address'))->>'id')::uuid;
 p:=(public.production_command('product',jsonb_build_object('business_unit_id',u,'name','TRANSIENT QA concrete','unit','m³','kind','product'))->>'id')::uuid;
 perform public.production_geofence('plant_zone',jsonb_build_object('actor_id',guy,'business_unit_id',u,'latitude',56,'longitude',-117,'radius_m',150));
 perform public.production_geofence('site_zone',jsonb_build_object('actor_id',guy,'business_unit_id',u,'site_id',s,'latitude',56.1,'longitude',-117,'radius_m',150));
 failed:=false;begin perform public.production_geofence('plant_zone',jsonb_build_object('actor_id',guy,'business_unit_id',u,'latitude',91,'longitude',-117,'radius_m',150));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Invalid coordinates accepted';end if;
 o:=(public.production_command('order',jsonb_build_object('business_unit_id',u,'customer_id',c,'site_id',s,'product_id',p,'quantity',8,'due_at',now()+interval '1 day'))->>'id')::uuid;
 perform public.production_command('driver',jsonb_build_object('business_unit_id',fleet,'user_id',driver));
 select id into t from public.assets where business_unit_id=fleet and status='active' limit 1;
 l:=(public.production_command('schedule',jsonb_build_object('order_id',o,'fleet_unit_id',fleet,'driver_id',driver,'truck_id',t,'quantity',8))->>'id')::uuid;
 token:=public.production_command('tracking',jsonb_build_object('order_id',o))->>'token';
 perform set_config('request.jwt.claim.sub',driver::text,true);
 r:=pg_temp.qa_geo(l,56.01,-117,0);if r->>'event' is not null then raise exception 'Event before confirmed loading';end if;
 perform set_config('request.jwt.claim.sub',guy::text,true);perform public.production_command('produce',jsonb_build_object('load_id',l));
 select plant_zone into old_plant from public.production_loads where id=l;if old_plant is null then raise exception 'Missing plant snapshot';end if;
 perform public.production_geofence('plant_zone',jsonb_build_object('actor_id',guy,'business_unit_id',u,'latitude',55,'longitude',-117,'radius_m',200));
 if (select plant_zone from public.production_loads where id=l) is distinct from old_plant then raise exception 'Saved plant edits altered a ready load';end if;
 perform pg_temp.qa_geo_prepare(l,'ready');
 perform set_config('request.jwt.claim.sub',driver::text,true);
 -- An outside reading cannot infer departure without observing the truck at the plant.
 perform pg_temp.qa_geo(l,56.01,-117,44);if(select status from public.production_loads where id=l)<>'ready' then raise exception 'Unarmed departure';end if;
 perform pg_temp.qa_geo_prepare(l,'ready');
 perform pg_temp.qa_geo(l,56,-117,44);
 perform pg_temp.qa_geo(l,56.01,-117,35);
 perform pg_temp.qa_geo(l,56.01,-117,20);
 if(select status from public.production_loads where id=l)<>'ready' then raise exception 'Departure before dwell';end if;
 r:=pg_temp.qa_geo(l,56.01,-117,5);if r->>'event' is distinct from 'departed' then raise exception 'Departure not detected: %',r;end if;
 r:=public.production_command('event',jsonb_build_object('load_id',l,'event','departed','client_id',gen_random_uuid()));if not coalesce((r->>'already_recorded')::boolean,false) then raise exception 'Delayed manual departure was not reconciled';end if;
 perform pg_temp.qa_geo(l,56.01,-117,5);if(select count(*) from public.production_activity where load_id=l and kind='departed')<>1 then raise exception 'Duplicate departure';end if;
 failed:=false;begin perform public.production_geofence('refresh_zones',jsonb_build_object('actor_id',driver,'load_id',l));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Driver changed delivery zones';end if;
 perform pg_temp.qa_geo_prepare(l,'departed');
 -- Poor accuracy and a single good reading cannot mark arrival.
 perform pg_temp.qa_geo(l,56.1,-117,44,100);
 perform pg_temp.qa_geo(l,56.1,-117,35);
 perform pg_temp.qa_geo(l,56.1,-117,20);
 if(select status from public.production_loads where id=l)<>'departed' then raise exception 'Arrival before dwell';end if;
 r:=pg_temp.qa_geo(l,56.1,-117,5);if r->>'event' is distinct from 'arrived' then raise exception 'Arrival not detected: %',r;end if;
 r:=public.production_command('event',jsonb_build_object('load_id',l,'event','arrived','client_id',gen_random_uuid()));if not coalesce((r->>'already_recorded')::boolean,false) then raise exception 'Delayed manual arrival was not reconciled';end if;
 if(select count(*) from public.production_activity where load_id=l and kind='arrived')<>1 then raise exception 'Duplicate manual/GPS arrival';end if;
 perform pg_temp.qa_geo_prepare(l,'arrived');
 perform pg_temp.qa_geo(l,56.11,-117,35);perform pg_temp.qa_geo(l,56.11,-117,20);r:=pg_temp.qa_geo(l,56.11,-117,5);
 if r->>'event' is distinct from 'site_left' then raise exception 'Site exit not detected: %',r;end if;
 if(select status from public.production_loads where id=l)<>'arrived' or (select status from public.production_orders where id=o)<>'confirmed' then raise exception 'GPS exit automatically completed delivery';end if;
 if(select left_site_at from public.production_loads where id=l) is null then raise exception 'Missing site exit time';end if;
 r:=pg_temp.qa_tracking(token);
 if r::text not like '%left_site_at%' or r::text like '%latitude%' or r::text like '%longitude%' or r::text like '%accuracy_m%' then raise exception 'Tracking lacks exit or exposes precise coordinates';end if;
 if not pg_temp.qa_geo_notice(o,guy) then raise exception 'Dispatcher did not receive site exit notice';end if;
 perform public.production_command('event',jsonb_build_object('load_id',l,'event','completed'));
 if(select status from public.production_orders where id=o)<>'completed' then raise exception 'Manual completion failed';end if;
 perform set_config('request.jwt.claim.sub',dj::text,true);
 failed:=false;begin perform pg_temp.qa_geo(l,56,-117,0);exception when raise_exception then failed:=true;end;if not failed then raise exception 'Unrelated user sent location';end if;
 failed:=false;begin perform public.production_geofence('plant_zone',jsonb_build_object('actor_id',dj,'business_unit_id',u,'latitude',56,'longitude',-117,'radius_m',150));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Operator edited coordinates';end if;
 failed:=false;begin perform public.production_geofence('sample',jsonb_build_object('actor_id',driver,'load_id',l));exception when raise_exception then failed:=true;end;if not failed then raise exception 'Cross-account GPS accepted';end if;
 if has_table_privilege('authenticated','private.production_geofence_state','select') or has_table_privilege('authenticated','public.production_plant_zones','update') then raise exception 'Direct state/config mutation exposed';end if;
end $$;
set local role anon;
do $$begin if has_function_privilege('anon','public.production_geofence(text,jsonb)','execute') or has_table_privilege('anon','public.production_plant_zones','select') then raise exception 'Anonymous geofence access';end if;end$$;
reset role;
select 'production_geofences_passed' result;
rollback;
