begin;
-- Run inside BEGIN/ROLLBACK; fixtures and temporary MOC grants never persist.
set local request.jwt.claims = '{"sub":"2fb0bab9-a296-499c-80fe-fdb87f1127ce","role":"authenticated"}';
do $qa$
declare u uuid; a uuid; w uuid; p uuid; v uuid; loc uuid; employee uuid; po uuid; target uuid; plan uuid; count_id uuid;
begin
 select id into strict u from public.business_units where code='HEAVY-EQP';
 select id into a from public.assets where business_unit_id=u limit 1;
 select id into strict employee from public.profiles where full_name='[MOC] Jamie Park';
 perform set_config('ruel.qa.tech',employee::text,true);
 insert into public.user_unit_access(user_id,business_unit_id,access_role,can_edit,can_approve)
 values(employee,u,'technician',true,false),('f126df16-2496-4d7b-8d56-c62f01e5cda6',u,'operator',true,false)
 on conflict(user_id,business_unit_id) do update set can_edit=true;
 insert into public.work_orders(asset_id,business_unit_id,title,type,priority,status,assigned_to,requested_by,estimated_cost,labour_cost,approval_threshold_snapshot,execution_approval_status)
 values(a,u,'[QA rollback] financial visibility','corrective','low','open',employee,employee,1234,123,9876,'approved') returning id into w;
 insert into public.parts(part_number,description,standard_cost) values('QA-COST-'||gen_random_uuid(),'[QA rollback] financial fixture',47.25) returning id into p;
 insert into public.vendors(name,hourly_rate) values('[QA rollback] financial vendor',88) returning id into v;
 select id into loc from public.inventory_locations where business_unit_id=u and active limit 1;
 insert into public.work_order_vendors(work_order_id,vendor_id,quoted_amount) values(w,v,333);
 insert into public.inventory_purchase_orders(business_unit_id,vendor_id,po_number,status) values(u,v,'QA-'||gen_random_uuid(),'draft') returning id into po;
 insert into public.inventory_purchase_order_lines(purchase_order_id,part_id,destination_location_id,quantity_ordered,unit_cost) values(po,p,loc,2,61);
 update public.inventory_purchase_orders set status='ordered' where id=po;
 insert into public.inventory_locations(business_unit_id,name) values(u,'[QA rollback] transfer location') returning id into target;
 insert into public.inventory_counts(business_unit_id,location_id,count_reference,status,counted_by) values(u,target,'QA-'||gen_random_uuid(),'in_progress',employee) returning id into count_id;
 insert into public.inventory_count_lines(count_id,part_id,system_quantity,actual_quantity) values(count_id,p,0,3);
 insert into public.maintenance_plans(asset_id,plan_type,title,trigger_basis,interval_days,next_due_date,auto_generate,estimated_cost,assigned_to)
 values(a,'preventive','[QA rollback] financial PM','calendar',30,current_date,true,222,employee) returning id into plan;
 perform set_config('ruel.qa.target',target::text,true); perform set_config('ruel.qa.count',count_id::text,true); perform set_config('ruel.qa.plan',plan::text,true);
 perform set_config('ruel.qa.order',w::text,true); perform set_config('ruel.qa.part',p::text,true);
 perform set_config('ruel.qa.vendor',v::text,true); perform set_config('ruel.qa.location',loc::text,true);
 perform set_config('ruel.qa.po',po::text,true);
 update public.work_orders set execution_approval_status='draft' where id=w;
 perform set_config('ruel.qa.req',public.add_work_order_part_requirement(w,p,1,loc)::text,true);
 update public.work_orders set execution_approval_status='approved',status='in_progress' where id=w;
end $qa$;
set local role authenticated;
set local request.jwt.claims = '{"sub":"53bc4a33-6d79-4164-8937-b19c757d56ac","role":"authenticated"}';
do $qa$
declare t text; col text; n numeric;
begin
 select estimated_cost into n from public.work_orders_visible where id=current_setting('ruel.qa.order')::uuid;
 if n is distinct from 1234 then raise exception 'Supervisor cannot see own-unit costs'; end if;
 if exists(select 1 from public.work_orders_visible where id=current_setting('ruel.qa.order')::uuid and approval_threshold_snapshot is not null) then raise exception 'Threshold snapshot leaked'; end if;
 -- Monetary base columns must be inaccessible even to authorized finance readers.
 for t,col in select * from (values('work_orders','estimated_cost'),('maintenance_plans','estimated_cost'),('parts','standard_cost'),('vendors','hourly_rate'),('inventory_transactions','unit_cost'),('inventory_purchase_order_lines','unit_cost'),('work_order_vendors','quoted_amount')) c(t,col) loop
  begin
   execute format('select %I from public.%I limit 1',col,t);
   raise exception 'QA_RAW_COST_READ_ACCEPTED: %',t;
  exception when insufficient_privilege then null;
  end;
 end loop;
 -- Direct UPDATE with an explicit value still works for authorized users.
 update public.work_orders set estimated_cost=1234 where id=current_setting('ruel.qa.order')::uuid;
 -- Every derived report must execute after column privileges are narrowed.
 perform 1 from public.inventory_kardex limit 1; perform 1 from public.inventory_stock_summary limit 1;
 perform 1 from public.inventory_usage_by_work_order limit 1; perform 1 from public.inventory_replenishment_report limit 1;
 perform 1 from public.pm_forecast limit 1; perform 1 from public.maintenance_due_board limit 1;
end $qa$;
set local request.jwt.claims = '{"sub":"f54655c7-7688-498b-8860-41d96444d48e","role":"authenticated"}';
do $qa$
begin
 if exists(select 1 from public.work_orders_visible where id=current_setting('ruel.qa.order')::uuid) then raise exception 'Foreign-unit supervisor read accepted'; end if;
 if private.financial_fields('work_orders',current_setting('ruel.qa.order')::uuid)<>'{}'::jsonb then raise exception 'Foreign-unit financial helper leaked'; end if;
end $qa$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('ruel.qa.tech'),'role','authenticated')::text,true);
do $qa$
declare tx uuid; req uuid; line_id uuid;
begin
 if not exists(select 1 from public.work_orders_visible where id=current_setting('ruel.qa.order')::uuid and estimated_cost is null and labour_cost is null and approval_threshold_snapshot is null) then raise exception 'Technician financial masking failed'; end if;
 if exists(select 1 from public.parts_visible where standard_cost is not null) or exists(select 1 from public.vendors_visible where hourly_rate is not null) then raise exception 'Catalog price leaked'; end if;
 if exists(select 1 from public.work_order_vendors_visible where quoted_amount is not null or invoiced_amount is not null) then raise exception 'Vendor amount leaked'; end if;
 if exists(select 1 from public.inventory_purchase_order_lines_visible where unit_cost is not null) then raise exception 'Purchase price leaked'; end if;
 update public.work_orders set diagnosis='[QA rollback] operational edit' where id=current_setting('ruel.qa.order')::uuid;
 tx:=public.post_inventory_movement(current_setting('ruel.qa.part')::uuid,current_setting('ruel.qa.location')::uuid,'receipt',10,99999);
 perform set_config('ruel.qa.receipt',tx::text,true);
 req:=current_setting('ruel.qa.req')::uuid;
 tx:=public.issue_part_to_work_order(current_setting('ruel.qa.order')::uuid,current_setting('ruel.qa.part')::uuid,current_setting('ruel.qa.location')::uuid,1,99999,req);
 perform set_config('ruel.qa.issue',tx::text,true);
 perform public.return_part_from_work_order(current_setting('ruel.qa.order')::uuid,current_setting('ruel.qa.part')::uuid,current_setting('ruel.qa.location')::uuid,1,99999,req);
 perform public.transfer_inventory_part(current_setting('ruel.qa.part')::uuid,current_setting('ruel.qa.location')::uuid,current_setting('ruel.qa.target')::uuid,1);
 perform public.post_inventory_count(current_setting('ruel.qa.count')::uuid);
 select id into line_id from public.inventory_purchase_order_lines where purchase_order_id=current_setting('ruel.qa.po')::uuid;
 tx:=public.receive_purchase_order_line(line_id,1,99999);
 perform set_config('ruel.qa.po_receipt',tx::text,true);
 perform public.receive_part_for_work_order_request(req,current_setting('ruel.qa.location')::uuid,1,99999);
 perform public.generate_due_maintenance_work_orders('8c2590f3-5260-4242-a151-851119f0099b',now());
 if exists(select 1 from public.inventory_transactions_visible where unit_cost is not null) then raise exception 'Transaction price leaked'; end if;
 if exists(select 1 from public.inventory_replenishment_report where standard_cost is not null or inventory_value is not null) then raise exception 'Replenishment price leaked'; end if;
 if exists(select 1 from public.pm_forecast where estimated_cost is not null) then raise exception 'PM forecast cost leaked'; end if;
end $qa$;
set local request.jwt.claims = '{"sub":"f126df16-2496-4d7b-8d56-c62f01e5cda6","role":"authenticated"}';
do $qa$
begin
 if not exists(select 1 from public.work_orders_visible where id=current_setting('ruel.qa.order')::uuid and estimated_cost is null) then raise exception 'Operator masking or operational visibility failed'; end if;
end $qa$;
set local request.jwt.claims = '{"sub":"2fb0bab9-a296-499c-80fe-fdb87f1127ce","role":"authenticated"}';
do $qa$
begin
 if not exists(select 1 from public.work_orders_visible where id=current_setting('ruel.qa.order')::uuid and estimated_cost=1234 and labour_cost=123 and approval_threshold_snapshot=9876) then raise exception 'Super Admin view or hidden-cost preservation failed'; end if;
end $qa$;
reset role;
do $qa$
begin
 if (select unit_cost from public.inventory_transactions where id=current_setting('ruel.qa.receipt')::uuid) is distinct from 47.25 then raise exception 'Masked receipt pricing corrupted cost'; end if;
 if (select unit_cost from public.inventory_transactions where id=current_setting('ruel.qa.issue')::uuid) is distinct from 47.25 then raise exception 'Masked issue pricing corrupted cost'; end if;
 if (select unit_cost from public.inventory_transactions where id=current_setting('ruel.qa.po_receipt')::uuid) is distinct from 61 then raise exception 'Masked PO receipt lost the agreed price'; end if;
 if not exists(select 1 from public.work_orders where maintenance_plan_id=current_setting('ruel.qa.plan')::uuid and estimated_cost=222) then raise exception 'PM generation lost the plan estimate'; end if;
end $qa$;
select 'financial visibility, scope, operational editing and server pricing passed' as qa_result;

rollback;
