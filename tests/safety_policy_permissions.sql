-- Exercise actual RLS, not only privileged RPCs. All records and notifications roll back.
begin;
select set_config('request.jwt.claim.sub',(select profile_id::text from public.personnel_onboarding where preferred_name='DJ'),true);
set local role authenticated;
do $$
declare unit_id uuid;asset_id uuid;submitted jsonb;
begin
 if not has_function_privilege(current_user,'private.can_access_safety_case(uuid)','execute')
 or not has_function_privilege(current_user,'private.can_manage_safety_case(uuid)','execute') then
  raise exception 'Authenticated RLS predicates are not callable';
 end if;
 if has_function_privilege('anon','private.can_access_safety_case(uuid)','execute')
 or has_function_privilege('anon','private.can_manage_safety_case(uuid)','execute') then
  raise exception 'Anonymous Safety predicate access introduced';
 end if;
 select business_unit_id,id into strict unit_id,asset_id from public.assets where asset_code='MIX-BP-SHELF';
 submitted:=public.submit_field_observation(gen_random_uuid(),unit_id,asset_id,'safety','[QA rollback] Safety RLS permission audit','immediate_safety');
 perform set_config('qa.safety_case_id',submitted->>'safety_case_id',true);
 if not exists(select 1 from public.safety_cases where id=current_setting('qa.safety_case_id')::uuid) then
  raise exception 'Reporter cannot read their own Safety Case';
 end if;
 if private.can_manage_safety_case(current_setting('qa.safety_case_id')::uuid) then
  raise exception 'Reporter incorrectly gained management rights';
 end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='don@ruelconcreteltd.com'),true);
set local role authenticated;
do $$begin
 if not exists(select 1 from public.safety_cases where id=current_setting('qa.safety_case_id')::uuid)
 or not private.can_manage_safety_case(current_setting('qa.safety_case_id')::uuid) then
  raise exception 'Assigned supervisor cannot review the Safety Case';
 end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='guy@ruelconcreteltd.com'),true);
set local role authenticated;
do $$declare case_id uuid:=current_setting('qa.safety_case_id')::uuid;snapshot_id uuid;begin
 perform public.review_safety_case(case_id,'near_miss_incident','Access','Area isolated',false,'Verified test hazard','Test fixture','Test fixture','Restore clear access',false,null);
 snapshot_id:=public.close_safety_case(case_id,'Test hazard removed','Verified safe',null);
 if not exists(select 1 from public.safety_case_report_snapshots where id=snapshot_id and safety_case_id=case_id) then
  raise exception 'Safety reviewer cannot read the closure snapshot';
 end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where full_name='[MOC] Casey White' and active),true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.safety_cases where id=current_setting('qa.safety_case_id')::uuid)
 or exists(select 1 from public.safety_case_report_snapshots where safety_case_id=current_setting('qa.safety_case_id')::uuid)
 or private.can_manage_safety_case(current_setting('qa.safety_case_id')::uuid) then
  raise exception 'Unrelated operator can access or manage the Safety Case';
 end if;
end$$;
rollback;
select 'PASS: authenticated reporter, supervisor and OHS access; retained closure snapshot; unrelated operator and anonymous access denied; all fixtures rolled back' as result;
