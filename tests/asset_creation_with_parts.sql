begin;
-- All fixtures and successful asset writes are rolled back.
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='concrete@ruelconcreteltd.com'),true);
select set_config('ruel.test.supervisor',(select id::text from public.profiles where email='don@ruelconcreteltd.com'),true);
select set_config('ruel.test.unit',(select id::text from public.business_units where code='CONC-PR'),true);
select set_config('ruel.test.run',gen_random_uuid()::text,true);
insert into public.parts(part_number,description,unit_of_measure,standard_cost,responsible_user_id)
select 'TRANSIENT-CREATE-'||current_setting('ruel.test.run')||'-'||n,'Transient rollback component','ea',1,current_setting('ruel.test.supervisor')::uuid from generate_series(1,105) n;
set local role authenticated;
do $$
declare payload jsonb; refs jsonb; created uuid; code text; first_part uuid;
begin
 code:='TRANSIENT-CREATE-'||current_setting('ruel.test.run');
 payload:=jsonb_build_object('business_unit_id',current_setting('ruel.test.unit'),'responsible_user_id',current_setting('ruel.test.supervisor'),'asset_code',code,'name','Transient rollback machine','asset_category','BATCH_PLANT','criticality','3');
 select jsonb_agg(jsonb_build_object('part_id',id,'relationship_type','installed','installed_quantity',2,'component_system','Hydraulics','installation_position','Main assembly')) into refs from public.parts_visible where part_number like code||'-%';
 first_part:=(refs->0->>'part_id')::uuid;
 created:=public.create_asset_with_parts(payload,refs);
 if (select count(*) from public.asset_part_compatibility where asset_id=created)<>105 then raise exception 'Not all components saved';end if;
 if not exists(select 1 from public.asset_assignments where asset_id=created and responsibility='primary' and active and user_id=current_setting('ruel.test.supervisor')::uuid) then raise exception 'Primary responsibility missing';end if;
 if not exists(select 1 from public.asset_part_compatibility where asset_id=created and part_id=first_part and installed_quantity=2 and component_system='Hydraulics' and installation_position='Main assembly') then raise exception 'Component metadata missing';end if;
 if exists(select 1 from public.inventory_transactions where part_id=first_part) then raise exception 'Creation moved warehouse stock';end if;
 -- Error occurs after the asset is created inside the function: verify rollback of the whole call.
 begin
   perform public.create_asset_with_parts(payload||jsonb_build_object('asset_code',code||'-INVALID'),jsonb_build_array(jsonb_build_object('part_id',first_part,'installed_quantity',0)));
   raise exception 'Invalid quantity accepted';
 exception when others then if sqlerrm='Invalid quantity accepted' then raise;end if;end;
 if exists(select 1 from public.assets where asset_code=code||'-INVALID') then raise exception 'Failed component left a partial asset';end if;
 begin
   perform public.create_asset_with_parts(payload||jsonb_build_object('asset_code',code||'-DUP'),jsonb_build_array(refs->0,refs->0));
   raise exception 'Duplicate accepted';
 exception when others then if sqlerrm='Duplicate accepted' then raise;end if;end;
 if exists(select 1 from public.assets where asset_code=code||'-DUP') then raise exception 'Duplicate failure left a partial asset';end if;
 perform public.create_asset_with_parts(payload||jsonb_build_object('asset_code',code||'-EMPTY'),'[]');
 perform public.create_asset_with_parts(payload||jsonb_build_object('asset_code',code||'-SPARE'),jsonb_build_array(jsonb_build_object('part_id',first_part,'relationship_type','compatible')));
 if has_function_privilege('anon','public.create_asset_with_parts(jsonb,jsonb)','EXECUTE') then raise exception 'Anonymous creation exposed';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select profile_id::text from public.personnel_onboarding where preferred_name='DJ'),true);
set local role authenticated;
do $$ begin
 begin
 perform public.create_asset_with_parts(jsonb_build_object('business_unit_id',current_setting('ruel.test.unit'),'responsible_user_id',current_setting('ruel.test.supervisor'),'asset_code','TRANSIENT-OPERATOR-DENIED','name','Denied operator creation','asset_category','BATCH_PLANT'),'[]');
 raise exception 'Operator created asset';
 exception when others then if sqlerrm='Operator created asset' then raise;end if;end;
end $$;
reset role;
rollback;
select 'PASS: 105 components saved atomically with responsibility; metadata and shared spares; empty list allowed; invalid/duplicate rollback; no stock movement; operator/anonymous protection. All fixtures rolled back.' as result;
