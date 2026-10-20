begin;
do $qa$
declare op uuid; manager uuid; unitid uuid; assetid uuid; ownid uuid; otherid uuid; result jsonb;
begin
 select id into strict op from public.profiles where full_name='[MOC] Casey White';
 select id into strict manager from public.profiles where email='concrete@ruelconcreteltd.com';
 select id into strict unitid from public.business_units where code='CONC-PR';
 select id into strict assetid from public.assets where business_unit_id=unitid and asset_code like 'MOC-%' limit 1;
 insert into public.user_unit_access(user_id,business_unit_id,access_role,can_edit,can_approve) values(op,unitid,'operator',false,false) on conflict(user_id,business_unit_id) do update set can_edit=false,can_approve=false;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',op,'role','authenticated')::text,true);
 result:=public.submit_field_observation(gen_random_uuid(),unitid,assetid,'equipment','[QA rollback] own phone-report visibility','normal'); ownid:=(result->>'observation_id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',manager,'role','authenticated')::text,true);
 result:=public.submit_field_observation(gen_random_uuid(),unitid,assetid,'equipment','[QA rollback] other reporter visibility','normal'); otherid:=(result->>'observation_id')::uuid;
 perform set_config('qa.own_id',ownid::text,true); perform set_config('qa.other_id',otherid::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',op,'role','authenticated')::text,true);
end $qa$;
set local role authenticated;
do $qa$ begin
 if (select count(*) from public.field_observations where id=current_setting('qa.own_id')::uuid)<>1 then raise exception 'Operator lost own report'; end if;
 if exists(select 1 from public.field_observations where id=current_setting('qa.other_id')::uuid) then raise exception 'Operator can read another reporter'; end if;
 begin perform public.complete_phone_onboarding();raise exception 'Unverified phone activation accepted';exception when others then if sqlerrm<>'Verify your phone and save your password first' then raise;end if;end;
end $qa$;
reset role;
rollback;
select 'PASS: operator reads own reports only; unverified phone completion rejected. Fixtures rolled back.' result;
