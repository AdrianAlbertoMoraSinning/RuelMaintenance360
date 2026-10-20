-- Scoped commissioning cleanup. User authorized removal of CONC-PR MOCK only.
-- Run transactionally; replace the final ROLLBACK with COMMIT only after preview.
-- Private archive retains exact original rows; shared masters and real personnel stay.
begin isolation level repeatable read;
set local lock_timeout='5s';
set local statement_timeout='45s';
create temporary table cleanup_target(source_table text not null,row_key jsonb not null,row_data jsonb not null,primary key(source_table,row_key)) on commit drop;
create temporary table cleanup_meta(batch_id uuid,unit_id uuid,unit_code text) on commit drop;
insert into cleanup_meta select gen_random_uuid(),id,code from public.business_units where code='CONC-PR' and name='Peace River Concrete Plant';
create function pg_temp.cleanup_key(table_oid regclass,data jsonb) returns jsonb language sql stable as $$
 select coalesce(jsonb_object_agg(a.attname,data->a.attname),data)
 from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey)
 where i.indrelid=table_oid and i.indisprimary;
$$;
create function pg_temp.cleanup_add(table_name text,predicate text) returns bigint language plpgsql as $$
declare n bigint;
begin
 execute format('insert into cleanup_target select %L,pg_temp.cleanup_key(%L::regclass,to_jsonb(x)),to_jsonb(x) from %s x where %s on conflict do nothing',table_name,table_name,table_name,predicate);
 get diagnostics n=row_count;return n;
end $$;
do $$
declare u uuid; t record; join_clause text; added bigint; n bigint;
begin
 select unit_id into strict u from cleanup_meta;
 if exists(select 1 from public.assets where business_unit_id=u and asset_code not like 'MOC-%') then raise exception 'Real assets now exist: review scope again';end if;
 if exists(select 1 from public.work_orders where business_unit_id=u and title not like '[MOC]%') then raise exception 'Real work orders now exist: review scope again';end if;
 if exists(select 1 from public.field_observations where business_unit_id=u) then raise exception 'Observations now exist: review them before cleanup';end if;
 if exists(select 1 from public.inventory_transactions tx join public.inventory_locations l on l.id=tx.location_id where l.business_unit_id=u and coalesce(tx.reference,'') not like 'MOC-%' and coalesce(tx.notes,'') not like '[MOC%') then raise exception 'Real inventory transactions exist: review scope again';end if;
 perform pg_temp.cleanup_add('public.assets',format('x.business_unit_id=%L and x.asset_code like ''MOC-%%''',u));
 perform pg_temp.cleanup_add('public.work_orders',format('x.business_unit_id=%L and x.title like ''[MOC]%%''',u));
 perform pg_temp.cleanup_add('public.documents',format('x.business_unit_id=%L and (x.title like ''[MOC]%%'' or x.metadata->>''mock_only''=''true'')',u));
 perform pg_temp.cleanup_add('public.inventory_transactions',format('x.location_id in (select id from public.inventory_locations where business_unit_id=%L) and (x.reference like ''MOC-%%'' or x.notes like ''[MOC%%'')',u));
 perform pg_temp.cleanup_add('public.user_unit_access',format('x.business_unit_id=%L and x.user_id in (select id from public.profiles where full_name like ''[MOC]%%'')',u));
 -- Expand every FK dependency, including SET NULL references, so no detached mock history survives.
 loop
  added:=0;
  for t in select c.oid,c.conrelid,c.confrelid,c.conkey,c.confkey from pg_constraint c join pg_namespace ns on ns.oid=c.connamespace where c.contype='f' and ns.nspname='public' and c.confrelid::regclass::text in (select distinct source_table from cleanup_target union select replace(source_table,'public.','') from cleanup_target) loop
   select string_agg(format('to_jsonb(x)->%L=p.row_data->%L',ca.attname,pa.attname),' and ') into join_clause
   from unnest(t.conkey,t.confkey) k(child_col,parent_col)
   join pg_attribute ca on ca.attrelid=t.conrelid and ca.attnum=k.child_col
   join pg_attribute pa on pa.attrelid=t.confrelid and pa.attnum=k.parent_col;
   execute format('insert into cleanup_target select %L,pg_temp.cleanup_key(%L::regclass,to_jsonb(x)),to_jsonb(x) from %s x where exists(select 1 from cleanup_target p where p.source_table=%L and %s) on conflict do nothing','public.'||(select relname from pg_class where oid=t.conrelid),t.conrelid::regclass::text,t.conrelid::regclass::text,'public.'||(select relname from pg_class where oid=t.confrelid),join_clause);
   get diagnostics n=row_count;added:=added+n;
  end loop;
  exit when added=0;
 end loop;
 if exists(select 1 from cleanup_target where row_data ? 'business_unit_id' and row_data->>'business_unit_id' is not null and row_data->>'business_unit_id'<>u::text) then raise exception 'Cross-unit dependency found: nothing may be deleted';end if;
 if exists(select 1 from cleanup_target c join public.inventory_locations l on l.id::text=c.row_data->>'location_id' where l.business_unit_id<>u) then raise exception 'Cross-unit inventory dependency found';end if;
 if exists(select 1 from cleanup_target where source_table not in ('public.assets','public.work_orders','public.documents','public.inventory_transactions','public.user_unit_access','public.asset_assignments','public.diagnostic_asset_identities','public.maintenance_plans','public.inspections','public.work_order_vendors','public.document_chunks','public.notifications','public.maintenance_plan_parts','public.work_order_part_requests','public.work_order_purchase_plans','public.work_order_evidence','public.inspection_evidence','public.asset_part_compatibility','public.asset_condition_alerts','public.asset_condition_rules','public.asset_condition_readings','public.meter_readings','public.failure_events','public.technical_assistant_queries','public.diagnostic_ingestion_log','public.diagnostic_signal_mappings','public.diagnostic_fault_events')) then raise exception 'Unexpected dependency: review delete order';end if;
end $$;
-- All non-target public rows must remain byte-for-byte equal except technical audit
-- and the plant warehouse/location responsibility reset from training staff to unassigned.
create temporary table cleanup_unchanged(table_name text primary key,fingerprint text) on commit drop;
do $$ declare t record; sig text; u uuid; begin
 select unit_id into u from cleanup_meta;
 for t in select c.oid,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname not in ('audit_log','inventory_responsibility_history') loop
 execute format('select md5(coalesce(string_agg(to_jsonb(x)::text,E''\\n'' order by to_jsonb(x)::text),'''')) from public.%I x where not exists(select 1 from cleanup_target c where c.source_table=%L and c.row_key=pg_temp.cleanup_key(%L::regclass,to_jsonb(x))) and not (%L in (''inventory_warehouses'',''inventory_locations'') and to_jsonb(x)->>''business_unit_id''=%L)',t.relname,'public.'||t.relname,'public.'||t.relname,t.relname,u::text) into sig;
 insert into cleanup_unchanged values(t.relname,sig);
 end loop;
end $$;
insert into private.unit_mock_cleanup_batches(id,business_unit_id,unit_code) select batch_id,unit_id,unit_code from cleanup_meta;
insert into private.unit_mock_cleanup_archive(batch_id,source_table,row_key,row_data) select m.batch_id,c.source_table,c.row_key,c.row_data from cleanup_target c cross join cleanup_meta m;
-- Preserve the original plant location setup before removing training responsibility.
insert into private.unit_mock_cleanup_archive(batch_id,source_table,row_key,row_data)
select m.batch_id,'public.inventory_locations',pg_temp.cleanup_key('public.inventory_locations',to_jsonb(l)),to_jsonb(l) from public.inventory_locations l join cleanup_meta m on l.business_unit_id=m.unit_id
union all
select m.batch_id,'public.inventory_warehouses',pg_temp.cleanup_key('public.inventory_warehouses',to_jsonb(w)),to_jsonb(w) from public.inventory_warehouses w join cleanup_meta m on w.business_unit_id=m.unit_id;
-- Training registry is private metadata, never delete another unit's entity references.
insert into private.unit_mock_cleanup_archive(batch_id,source_table,row_key,row_data)
select m.batch_id,'private.training_dataset_entities',to_jsonb(e),to_jsonb(e) from private.training_dataset_entities e cross join cleanup_meta m where exists(select 1 from cleanup_target c where c.row_data->>'id'=e.entity_id::text);
delete from private.training_dataset_entities e where exists(select 1 from cleanup_target c where c.row_data->>'id'=e.entity_id::text);
do $$
declare table_name text;
begin
 foreach table_name in array array['inventory_transactions','work_order_purchase_plans','work_order_part_requests','work_order_vendors','work_order_evidence','inspection_evidence','notifications','document_chunks','documents','inspections','diagnostic_ingestion_log','technical_assistant_queries','diagnostic_fault_events','diagnostic_signal_mappings','asset_condition_alerts','asset_condition_readings','asset_condition_rules','meter_readings','failure_events','work_orders','maintenance_plan_parts','maintenance_plans','asset_part_compatibility','diagnostic_asset_identities','asset_assignments','assets','user_unit_access'] loop
 execute format('delete from public.%I x using cleanup_target c where c.source_table=%L and c.row_key=pg_temp.cleanup_key(%L::regclass,to_jsonb(x))',table_name,'public.'||table_name,'public.'||table_name);
 end loop;
end $$;
update public.inventory_locations set responsible_user_id=null where business_unit_id=(select unit_id from cleanup_meta) and responsible_user_id in (select id from public.profiles where full_name like '[MOC]%');
update public.inventory_warehouses set responsible_user_id=null where business_unit_id=(select unit_id from cleanup_meta) and responsible_user_id in (select id from public.profiles where full_name like '[MOC]%');
do $$ declare t record; sig text; u uuid; remaining bigint; begin
 select unit_id into u from cleanup_meta;
 for t in select * from cleanup_unchanged loop
 execute format('select md5(coalesce(string_agg(to_jsonb(x)::text,E''\\n'' order by to_jsonb(x)::text),'''')) from public.%I x where not exists(select 1 from cleanup_target c where c.source_table=%L and c.row_key=pg_temp.cleanup_key(%L::regclass,to_jsonb(x))) and not (%L in (''inventory_warehouses'',''inventory_locations'') and to_jsonb(x)->>''business_unit_id''=%L)',t.table_name,'public.'||t.table_name,'public.'||t.table_name,t.table_name,u::text) into sig;
 if sig<>t.fingerprint then raise exception 'Unrelated records changed in %: transaction must roll back',t.table_name;end if;
 end loop;
 for t in select distinct source_table from cleanup_target loop
 execute format('select count(*) from %s x join cleanup_target c on c.source_table=%L and c.row_key=pg_temp.cleanup_key(%L::regclass,to_jsonb(x))',t.source_table,t.source_table,t.source_table) into remaining;
 if remaining<>0 then raise exception 'Cleanup targets still exist in %',t.source_table;end if;
 end loop;
 if exists(select 1 from public.personnel_onboarding where preferred_name='DJ' and (phone<>'+17806252210' or reporting_manager_id<>(select id from public.profiles where email='don@ruelconcreteltd.com'))) then raise exception 'DJ identity changed';end if;
 if not exists(select 1 from public.business_unit_approval_settings where business_unit_id=u and approval_threshold=500) then raise exception 'Approval threshold changed';end if;
end $$;
update private.unit_mock_cleanup_batches set completed_at=now(),summary=jsonb_build_object('deleted',(select jsonb_object_agg(source_table,n) from (select source_table,count(*) as n from cleanup_target group by source_table)s),'unrelated_tables_verified',(select count(*) from cleanup_unchanged),'other_units_unchanged',true,'shared_catalogs_retained',true,'real_personnel_retained',true,'warehouse_training_responsibility_cleared',true) where id=(select batch_id from cleanup_meta);
select jsonb_build_object('batch_id',id,'unit',unit_code,'summary',summary,'recoverable_rows',(select count(*) from private.unit_mock_cleanup_archive a where a.batch_id=b.id)) as cleanup_result from private.unit_mock_cleanup_batches b where id=(select batch_id from cleanup_meta);
rollback;
