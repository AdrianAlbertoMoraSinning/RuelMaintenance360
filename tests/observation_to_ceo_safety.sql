begin;
set local request.jwt.claims='{"sub":"2fb0bab9-a296-499c-80fe-fdb87f1127ce","role":"authenticated"}';
do $qa$
declare emp uuid; sup uuid; mgr uuid; guy uuid:='ea8946ea-e093-4ad1-a886-954fb91187db'; unitid uuid; assetid uuid; draft uuid:=gen_random_uuid(); result jsonb; obs uuid; wo uuid; safe uuid; safetyobs uuid; snap uuid;
begin
select id into strict emp from public.profiles where full_name='[MOC] Casey White';
select id,corporate_manager_id into strict sup,mgr from public.profiles where full_name='[MOC] Riley Chen';
select id into strict unitid from public.business_units where code='SAND-PR';
select id into strict assetid from public.assets where business_unit_id=unitid and asset_code like 'MOC-%' order by asset_code limit 1;
update public.profiles set corporate_manager_id=sup where id=emp;
perform public.set_business_unit_approval_threshold(unitid,1000);
insert into public.user_unit_access(user_id,business_unit_id,access_role,can_edit,can_approve) values(sup,unitid,'unit_supervisor',true,false) on conflict(user_id,business_unit_id) do update set can_edit=true;
perform set_config('request.jwt.claims',jsonb_build_object('sub',emp,'role','authenticated')::text,true);
result:=public.submit_field_observation(draft,unitid,assetid,'equipment','[QA rollback] Abnormal vibration recorded by operator','normal');
obs:=(result->>'observation_id')::uuid;
if not exists(select 1 from public.field_observations where id=obs and assigned_manager_id=sup and status='submitted') then raise exception 'Operator observation did not reach supervisor'; end if;
result:=public.submit_field_observation(draft,unitid,assetid,'equipment','[QA rollback] Retry same offline draft','normal');
if (result->>'observation_id')::uuid<>obs or not (result->>'idempotent')::boolean then raise exception 'Duplicate submission was not prevented'; end if;
begin
perform public.create_work_order_from_observation(obs,emp,'medium',2000,'[QA rollback] Operator must not convert');
raise exception 'QA_OPERATOR_CONVERSION_ACCEPTED';
exception when others then if sqlerrm not like '%Not authorized to convert%' then raise; end if; end;
perform set_config('request.jwt.claims',jsonb_build_object('sub',sup,'role','authenticated')::text,true);
wo:=public.create_work_order_from_observation(obs,emp,'medium',2000,'[QA rollback] Operator to CEO route');
if public.create_work_order_from_observation(obs,emp,'medium',2000,null)<>wo then raise exception 'Conversion created duplicate WO'; end if;
perform set_config('request.jwt.claims',jsonb_build_object('sub',sup,'role','authenticated')::text,true);
perform public.request_work_order_execution_approval(wo);
if not exists(select 1 from public.work_orders where id=wo and manager_approver_id=mgr and execution_approval_status='pending_manager' and corporate_approval_required) then raise exception 'WO did not route to manager with corporate escalation'; end if;
perform set_config('request.jwt.claims',jsonb_build_object('sub',guy,'role','authenticated')::text,true);
begin
perform public.approve_work_order_execution_super_admin(wo,'[QA rollback] Must wait for manager');
raise exception 'QA_CEO_SKIPPED_MANAGER';
exception when others then if sqlerrm not like '%Manager approval must be completed first%' then raise; end if; end;
perform set_config('request.jwt.claims',jsonb_build_object('sub',mgr,'role','authenticated')::text,true);
perform public.approve_work_order_execution_manager(wo,'[QA rollback] Manager review');
if not exists(select 1 from public.work_orders where id=wo and execution_approval_status='pending_super_admin') then raise exception 'Manager bypassed CEO stage'; end if;
perform set_config('request.jwt.claims',jsonb_build_object('sub',guy,'role','authenticated')::text,true);
perform public.approve_work_order_execution_super_admin(wo,'[QA rollback] CEO approval');
if not exists(select 1 from public.work_orders where id=wo and execution_approval_status='approved' and corporate_approved_by=guy) then raise exception 'CEO approval not recorded'; end if;
perform set_config('request.jwt.claims',jsonb_build_object('sub',emp,'role','authenticated')::text,true);
result:=public.submit_field_observation(gen_random_uuid(),unitid,assetid,'safety','[QA rollback] Trip hazard on access platform','immediate_safety');
safe:=(result->>'safety_case_id')::uuid;safetyobs:=(result->>'observation_id')::uuid;
if not exists(select 1 from public.safety_cases where id=safe and assigned_safety_user_id=guy and immediate_danger and status='triage') then raise exception 'OHS routing failed'; end if;
if not exists(select 1 from public.field_observations where id=safetyobs and assigned_manager_id=sup) then raise exception 'Safety manager route failed'; end if;
if (select count(distinct user_id) from public.notifications where observation_id=safetyobs and user_id in (sup,guy))<>2 then raise exception 'Missing supervisor or OHS notification'; end if;
begin
perform public.close_safety_case(safe,'Operator cannot close','Operator verification',null);
raise exception 'QA_OPERATOR_SAFETY_CLOSURE_ACCEPTED';
exception when others then if sqlerrm not like '%Not authorized to close safety case%' then raise; end if; end;
perform set_config('request.jwt.claims',jsonb_build_object('sub',guy,'role','authenticated')::text,true);
perform public.review_safety_case(safe,'near_miss_incident','Access','Barricaded access',false,'Reviewed access hazard','Poor housekeeping','Missing inspection','Restore clear access',false,null);
snap:=public.close_safety_case(safe,'Hazard removed and access restored','Access inspected and safe',null);
if not exists(select 1 from public.safety_case_report_snapshots where id=snap and safety_case_id=safe and snapshot_type='closure') then raise exception 'Safety closure report missing'; end if;
if not exists(select 1 from public.field_observations where id=safetyobs and status='resolved') then raise exception 'Safety observation not resolved on case closure'; end if;
end $qa$;
select 'PASS: Operator submission, supervisor routing, idempotency, unauthorized conversion blocked, single WO conversion, Manager then CEO approval, Safety notifications to Supervisor + Guy, unauthorized Safety closure blocked, OHS review/closure snapshot. Rollback.' result;
rollback;
