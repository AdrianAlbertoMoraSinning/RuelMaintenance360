begin;
-- Run inside BEGIN/ROLLBACK. All amounts below are disposable QA fixtures.
set local request.jwt.claims='{"sub":"2fb0bab9-a296-499c-80fe-fdb87f1127ce","role":"authenticated"}';
do $qa$
declare ua uuid; ub uuid; uc uuid; aa uuid; ab uuid; ac uuid; employee uuid; wa uuid; wb uuid; wc uuid; boundary uuid; who uuid;
begin
 select id into strict ua from public.business_units where code='HEAVY-EQP';
 select id into strict ub from public.business_units where code='CONC-PR';
 select id into strict uc from public.business_units where code='ASP-SL';
 select id into aa from public.assets where business_unit_id=ua limit 1;
 select id into ab from public.assets where business_unit_id=ub limit 1;
 select id into ac from public.assets where business_unit_id=uc limit 1;
 select id into strict employee from public.profiles where full_name='[MOC] Casey White';
 perform public.set_business_unit_approval_threshold(ua,1000);
 perform public.set_business_unit_approval_threshold(ub,5000);
 update public.business_unit_approval_settings set approval_threshold=null where business_unit_id=uc;
 -- The old global amount must not supply a fallback.
 update public.maintenance_approval_settings set corporate_approval_threshold=999999;
 insert into public.work_orders(business_unit_id,asset_id,title,type,priority,status,assigned_to,estimated_cost)
 values(ua,aa,'[QA rollback] Unit threshold A','corrective','low','open',employee,2000) returning id into wa;
 insert into public.work_orders(business_unit_id,asset_id,title,type,priority,status,assigned_to,estimated_cost)
 values(ub,ab,'[QA rollback] Unit threshold B','corrective','low','open',employee,2000) returning id into wb;
 insert into public.work_orders(business_unit_id,asset_id,title,type,priority,status,assigned_to,estimated_cost)
 values(uc,ac,'[QA rollback] Unit threshold unset','corrective','low','open',employee,2000) returning id into wc;
 perform public.request_work_order_execution_approval(wa);
 perform public.request_work_order_execution_approval(wb);
 if not exists(select 1 from public.work_orders where id=wa and approval_threshold_snapshot=1000 and corporate_approval_required) then raise exception 'Unit A threshold not applied'; end if;
 if not exists(select 1 from public.work_orders where id=wb and approval_threshold_snapshot=5000 and not corporate_approval_required) then raise exception 'Unit B threshold not applied independently'; end if;
 begin
  perform public.request_work_order_execution_approval(wc);
  raise exception 'QA_MISSING_THRESHOLD_ACCEPTED';
 exception when others then if sqlerrm not like '%Business Unit approval threshold has not been configured%' then raise; end if; end;
 if not exists(select 1 from public.work_orders where id=wc and execution_approval_status='draft' and approval_threshold_snapshot is null) then raise exception 'Blocked request changed state'; end if;
 perform public.set_business_unit_approval_threshold(ua,2500);
 if not exists(select 1 from public.work_orders where id=wa and approval_threshold_snapshot=1000 and corporate_approval_required) then raise exception 'Existing approval snapshot was rewritten'; end if;
 perform public.request_work_order_execution_approval(wa);
 if not exists(select 1 from public.work_orders where id=wa and approval_threshold_snapshot=2500 and not corporate_approval_required) then raise exception 'New request did not use updated unit threshold'; end if;
 update public.work_orders set business_unit_id=ua,asset_id=aa where id=wb;
 if not exists(select 1 from public.work_orders where id=wb and execution_approval_status='draft' and approval_threshold_snapshot is null) then raise exception 'Moving WO did not reset authorization'; end if;
 perform public.request_work_order_execution_approval(wb);
 if not exists(select 1 from public.work_orders where id=wb and approval_threshold_snapshot=2500) then raise exception 'Moved WO retained the wrong unit threshold'; end if;
 insert into public.work_orders(business_unit_id,asset_id,title,type,priority,status,assigned_to,estimated_cost)
 values(ua,aa,'[QA rollback] Unit threshold exact boundary','corrective','low','open',employee,2500) returning id into boundary;
 perform public.request_work_order_execution_approval(boundary);
 if exists(select 1 from public.work_orders where id=boundary and corporate_approval_required) then raise exception 'Equal estimate incorrectly escalated'; end if;
 perform public.set_business_unit_approval_threshold(uc,0);
 update public.work_orders set estimated_cost=1 where id=wc;
 perform public.request_work_order_execution_approval(wc);
 if not exists(select 1 from public.work_orders where id=wc and approval_threshold_snapshot=0 and corporate_approval_required) then raise exception 'Zero threshold not applied'; end if;
 begin perform public.set_business_unit_approval_threshold(ua,-1); raise exception 'QA_NEGATIVE_ACCEPTED'; exception when others then if sqlerrm not like '%non-negative CAD%' then raise; end if; end;
 begin perform public.set_business_unit_approval_threshold(ua,'NaN'::numeric); raise exception 'QA_NAN_ACCEPTED'; exception when others then if sqlerrm not like '%non-negative CAD%' then raise; end if; end;
 begin perform public.set_business_unit_approval_threshold(ua,12.345); raise exception 'QA_PRECISION_ACCEPTED'; exception when others then if sqlerrm not like '%non-negative CAD%' then raise; end if; end;
 begin perform public.set_maintenance_approval_threshold(100); raise exception 'QA_LEGACY_SETTER_ACCEPTED'; exception when others then if sqlerrm not like '%separate threshold for each Business Unit%' then raise; end if; end;
 perform set_config('ruel.qa.threshold_unit',ua::text,true);
end $qa$;
set local role authenticated;
do $qa$
declare who uuid;
begin
 -- Super Admin RPC works through actual authenticated-role privileges.
 perform public.set_business_unit_approval_threshold(current_setting('ruel.qa.threshold_unit')::uuid,2500);
 if not exists(select 1 from public.business_unit_approval_settings where business_unit_id=current_setting('ruel.qa.threshold_unit')::uuid and approval_threshold=2500) then raise exception 'Super Admin cannot read saved unit threshold'; end if;
 for who in select id from public.profiles where full_name in('[MOC] Morgan Ellis','[MOC] Riley Chen','[MOC] Casey White','[MOC] Jamie Park') loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',who,'role','authenticated')::text,true);
  if exists(select 1 from public.business_unit_approval_settings) then raise exception 'Non-Super Admin can read confidential thresholds'; end if;
  begin perform public.set_business_unit_approval_threshold(current_setting('ruel.qa.threshold_unit')::uuid,10); raise exception 'QA_NON_ADMIN_WRITE_ACCEPTED'; exception when others then if sqlerrm not like '%Super Admin access required%' then raise; end if; end;
 end loop;
 if has_table_privilege('anon','public.business_unit_approval_settings','select') or has_function_privilege('anon','public.set_business_unit_approval_threshold(uuid,numeric)','execute') then raise exception 'Anonymous access was granted'; end if;
end $qa$;
reset role;
select 'PASS: independent unit thresholds, no global fallback, unset/zero/boundary behavior, snapshots, moved WO and confidential Super Admin-only settings' as result;

rollback;
