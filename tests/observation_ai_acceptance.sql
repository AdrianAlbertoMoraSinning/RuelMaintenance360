begin;
do $$
declare obs uuid; dj uuid; don uuid; ceo uuid; acceptance uuid;
begin
 select profile_id into strict dj from public.personnel_onboarding where preferred_name='DJ';
 select id into strict don from public.profiles where email='don@ruelconcreteltd.com';
 select id into strict ceo from public.profiles where email='guy@ruelconcreteltd.com';
 insert into public.field_observations(business_unit_id,observation_type,description,immediate_concern,status,reported_by,assigned_manager_id)
 select id,'process','Transient verification of hydraulic leak report','normal','submitted',dj,don from public.business_units where code='CONC-PR' returning id into obs;
 if exists(select 1 from public.observation_ai_memory where observation_id=obs) then raise exception 'Unreviewed observation entered AI';end if;
 perform set_config('request.jwt.claim.sub',dj::text,true);
 begin perform public.accept_observation_for_ai(obs,'I approve my own report');raise exception 'Reporter accepted own observation';exception when others then if sqlerrm='Reporter accepted own observation' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',ceo::text,true);
 begin perform public.accept_observation_for_ai(obs,'CEO is not assigned supervisor');raise exception 'Unassigned CEO accepted observation';exception when others then if sqlerrm='Unassigned CEO accepted observation' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',don::text,true);
 acceptance:=public.accept_observation_for_ai(obs,'Reviewed the submitted description');
 if acceptance<>public.accept_observation_for_ai(obs,'Repeated request') then raise exception 'Acceptance not idempotent';end if;
 if not exists(select 1 from public.observation_ai_memory where observation_id=obs and accepted_by=don) then raise exception 'Accepted report missing';end if;
 update public.field_observations set description='Corrected report needs another review' where id=obs;
 if exists(select 1 from public.observation_ai_memory where observation_id=obs) then raise exception 'Edited text retained stale approval';end if;
 perform public.accept_observation_for_ai(obs,'Reviewed corrected description');
 update public.field_observations set status='information_requested' where id=obs;
 if exists(select 1 from public.observation_ai_memory where observation_id=obs) then raise exception 'Returned observation entered AI';end if;
 update public.field_observations set status='submitted' where id=obs;
 if exists(select 1 from public.observation_ai_memory where observation_id=obs) then raise exception 'Resubmission reused old approval';end if;
 perform public.accept_observation_for_ai(obs,'Reviewed resubmitted report');
 update public.field_observations set status='rejected' where id=obs;
 if exists(select 1 from public.observation_ai_memory where observation_id=obs) then raise exception 'Rejected observation entered AI';end if;
 update public.field_observations set status='submitted',description='[MOC] Simulated report' where id=obs;
 begin perform public.accept_observation_for_ai(obs,'Attempt training admission');raise exception 'Training admitted';exception when others then if sqlerrm='Training admitted' then raise;end if;end;
 if has_table_privilege('authenticated','private.observation_ai_acceptances','INSERT') or has_function_privilege('anon','public.accept_observation_for_ai(uuid,text)','EXECUTE') then raise exception 'Validation grants are unsafe';end if;
end $$;
do $$ declare obs uuid; don uuid; begin
 select id into strict don from public.profiles where email='don@ruelconcreteltd.com';
 select id into strict obs from public.field_observations where description='[MOC] Simulated report' and reported_by=(select profile_id from public.personnel_onboarding where preferred_name='DJ');
 update public.field_observations set description='Transient reviewed hydraulic leak for visibility verification',status='submitted' where id=obs;
 perform set_config('request.jwt.claim.sub',don::text,true);
 perform public.accept_observation_for_ai(obs,'Supervisor reviewed visibility fixture');
end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where full_name='[MOC] Casey White'),true);
set local role authenticated;
do $$ begin if exists(select 1 from public.observation_ai_memory where description='Transient reviewed hydraulic leak for visibility verification') then raise exception 'Unrelated operator can see accepted report';end if;end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='don@ruelconcreteltd.com'),true);
set local role authenticated;
do $$ begin if not exists(select 1 from public.observation_ai_memory where description='Transient reviewed hydraulic leak for visibility verification') then raise exception 'Supervisor cannot read own accepted report';end if;end $$;
reset role;
rollback;
select 'PASS: pending excluded; only assigned supervisor accepts; no self/CEO override; acceptance idempotent; edits/returns/rejections invalidate; resubmission requires fresh acceptance; MOCK excluded; protected grants. All fixtures rolled back.' as result;
