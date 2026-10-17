begin;
with candidates as (
 select distinct on (b.code) a.id as asset_id,b.id as business_unit_id,b.code
 from public.assets a join public.business_units b on b.id=a.business_unit_id
 where b.code in ('HEAVY-EQP','CONC-PR') order by b.code,a.id
), inserted as (
 insert into public.work_orders (asset_id,business_unit_id,title,status,type,priority,requested_by,assigned_to,estimated_cost)
 select asset_id,business_unit_id,'[QA rollback] Supervisor cost visibility '||code,'open','corrective','low',
 '53bc4a33-6d79-4164-8937-b19c757d56ac','53bc4a33-6d79-4164-8937-b19c757d56ac',123.45 from candidates
 returning id,business_unit_id
)
select set_config('ruel.qa.own_wo',(select i.id::text from inserted i join public.business_units b on b.id=i.business_unit_id where b.code='HEAVY-EQP'),true),
set_config('ruel.qa.other_wo',(select i.id::text from inserted i join public.business_units b on b.id=i.business_unit_id where b.code='CONC-PR'),true);
set local role authenticated;
set local request.jwt.claims = '{"sub":"53bc4a33-6d79-4164-8937-b19c757d56ac","role":"authenticated"}';
do $qa$ begin
 if not exists(select 1 from public.work_orders_visible where id=current_setting('ruel.qa.own_wo')::uuid and estimated_cost=123.45) then raise exception 'Supervisor cannot read own-unit cost'; end if;
 if exists(select 1 from public.work_orders where id=current_setting('ruel.qa.other_wo')::uuid) then raise exception 'Supervisor can read cross-unit cost via requester/assignee'; end if;
 if exists(select 1 from public.maintenance_approval_settings) then raise exception 'Supervisor can read confidential corporate threshold'; end if;
 if private.can_approve_unit((select business_unit_id from public.work_orders where id=current_setting('ruel.qa.own_wo')::uuid)) then raise exception 'Cost viewing unexpectedly grants approval'; end if;
end $qa$;
set local request.jwt.claims = '{"sub":"2fb0bab9-a296-499c-80fe-fdb87f1127ce","role":"authenticated"}';
do $qa$ begin
 if (select count(*) from public.work_orders where id in (current_setting('ruel.qa.own_wo')::uuid,current_setting('ruel.qa.other_wo')::uuid))<>2 then raise exception 'Super Admin cross-unit visibility regressed'; end if;
end $qa$;
select 'PASS: own-unit costs visible; cross-unit requester/assignee blocked; corporate threshold hidden; approval unchanged; Super Admin visibility retained. Fixtures rolled back.' as result;
rollback;
