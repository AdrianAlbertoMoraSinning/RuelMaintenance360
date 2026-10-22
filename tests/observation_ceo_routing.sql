begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','0d87a0bf-b3a8-434b-9012-45c5d9bacfff',true);
do $$
declare don uuid:='0d87a0bf-b3a8-434b-9012-45c5d9bacfff';adrian uuid:='2fb0bab9-a296-499c-80fe-fdb87f1127ce';guy uuid:='ea8946ea-e093-4ad1-a886-954fb91187db';dj uuid:='b6a1f147-ae25-4b3e-bdb5-f35c5b4addba';marcel uuid:='cc33d17c-f2cb-4c1c-8bf4-109d189f2539';unit uuid:='772039c9-622b-430c-90d7-8278adaa42aa';o uuid;normal uuid;draft_key uuid:=gen_random_uuid();response jsonb;failed boolean;msg bigint;reply bigint;cnt integer;
begin
 response:=public.observation_recipient_options(unit);if not(response->>'can_address_ceo')::boolean or response->'manager'->>'id'<>adrian::text or response->'ceo'->>'id'<>guy::text then raise exception 'Wrong supervisor recipient options';end if;
 normal:=(public.submit_addressed_field_observation(gen_random_uuid(),unit,null,'other','QA Default manager report','normal',null)->>'observation_id')::uuid;
 if not exists(select 1 from public.field_observations where id=normal and assigned_manager_id=adrian and addressed_to_id is null) then raise exception 'Default manager changed';end if;
 -- CEO is an observer unless explicitly addressed.
 perform set_config('request.jwt.claim.sub',guy::text,true);failed:=false;begin perform public.send_field_observation_message(normal,'Not a participant',gen_random_uuid());exception when raise_exception then failed:=true;end;if not failed then raise exception 'Unaddressed CEO posted to a bilateral chat';end if;
 perform set_config('request.jwt.claim.sub',don::text,true);
 o:=(public.submit_addressed_field_observation(draft_key,unit,null,'other','QA To CEO with manager copy','normal',guy)->>'observation_id')::uuid;
 if not exists(select 1 from public.field_observations where id=o and assigned_manager_id=adrian and addressed_to_id=guy and status='submitted') then raise exception 'Recipient or manager accountability incorrect';end if;
 if (public.submit_addressed_field_observation(draft_key,unit,null,'other','QA To CEO with manager copy','normal',guy)->>'observation_id')::uuid<>o then raise exception 'Draft retry duplicated report';end if;
 if(select count(*) from public.field_observation_history where observation_id=o and event_type='addressed_to_ceo')<>1 then raise exception 'Retry duplicated routing history';end if;
 -- Reporter messages notify the CEO and copied manager.
 msg:=public.send_field_observation_message(o,'QA Question to CEO and manager',gen_random_uuid());
 perform set_config('request.jwt.claim.sub',guy::text,true);
 if not exists(select 1 from public.notifications where observation_id=o and notification_type='field_observation' and read_at is null) or not exists(select 1 from public.notifications where observation_id=o and notification_type='observation_message' and dedupe_key='observation-message:'||msg) then raise exception 'CEO did not receive report/chat';end if;
 if not(public.observation_conversation_context(o)->>'can_send')::boolean then raise exception 'Addressed CEO cannot reply';end if;
 reply:=public.send_field_observation_message(o,'QA CEO reply',gen_random_uuid());
 perform set_config('request.jwt.claim.sub',adrian::text,true);
 if not exists(select 1 from public.notifications where observation_id=o and notification_type='field_observation') or not exists(select 1 from public.notifications where observation_id=o and dedupe_key='observation-message:'||msg) or not exists(select 1 from public.notifications where observation_id=o and dedupe_key='observation-message:'||reply) then raise exception 'Manager missing report or bilateral copies';end if;
 if not(public.observation_conversation_context(o)->>'can_send')::boolean then raise exception 'Copied manager cannot reply';end if;
 perform public.send_field_observation_message(o,'QA Manager reply in copied thread',gen_random_uuid());
 perform public.accept_observation_for_ai(o,'QA reviewed by assigned manager');
 perform public.escalate_observation_to_ceo(normal,'QA manager forwarding original observation');
 if not exists(select 1 from public.field_observations where id=normal and assigned_manager_id=adrian and addressed_to_id=guy) then raise exception 'Manager forward failed';end if;
 -- Direct table changes cannot bypass routing/audit, even for an administrator.
 failed:=false;begin update public.field_observations set addressed_to_id=null where id=o;exception when raise_exception or insufficient_privilege then failed:=true;end;if not failed then raise exception 'Direct recipient update bypassed command';end if;
 perform set_config('request.jwt.claim.sub',marcel::text,true);
 failed:=false;begin perform public.send_field_observation_message(o,'Unrelated shareholder message',gen_random_uuid());exception when raise_exception then failed:=true;end;if not failed then raise exception 'Unrelated shareholder joined chat';end if;
 perform set_config('request.jwt.claim.sub',dj::text,true);
 if(public.observation_recipient_options(unit)->>'can_address_ceo')::boolean then raise exception 'Operator was offered CEO bypass';end if;
 failed:=false;begin perform public.submit_addressed_field_observation(gen_random_uuid(),unit,null,'other','QA Operator cannot bypass supervisor','normal',guy);exception when raise_exception then failed:=true;end;if not failed then raise exception 'Operator bypassed manager';end if;
 failed:=false;begin perform public.escalate_observation_to_ceo(o,'Unauthorized');exception when raise_exception then failed:=true;end;if not failed then raise exception 'Unrelated user routed report';end if;
 perform set_config('request.jwt.claim.sub',don::text,true);
 failed:=false;begin perform public.submit_addressed_field_observation(gen_random_uuid(),unit,null,'other','QA Arbitrary recipient','normal',marcel);exception when raise_exception then failed:=true;end;if not failed then raise exception 'Arbitrary recipient accepted';end if;
 -- Safety routing to the primary OHS administrator is retained.
 o:=(public.submit_addressed_field_observation(gen_random_uuid(),unit,null,'safety','QA Safety CEO route','immediate_safety',guy)->>'observation_id')::uuid;
 if not exists(select 1 from public.field_observations where id=o and safety_case_id is not null and assigned_manager_id=adrian and addressed_to_id=guy) then raise exception 'Safety case was lost';end if;
end $$;
reset role;
select 'observation_ceo_routing_passed' as result;
rollback;
