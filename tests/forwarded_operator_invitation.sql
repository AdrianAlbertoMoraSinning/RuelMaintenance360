begin;
do $qa$
declare op uuid; actor uuid; hash text:=encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'); expiry timestamptz; detail jsonb;
begin
 select profile_id into strict op from public.personnel_onboarding where preferred_name='DJ';
 select id into strict actor from public.profiles where email='concrete@ruelconcreteltd.com';
 expiry:=public.issue_forwarded_operator_invitation(op,hash,actor);
 if expiry<now()+interval '71 hours' then raise exception 'Wrong expiry';end if;
 detail:=public.inspect_forwarded_operator_invitation(hash);
 if detail is null or (detail->>'profile_id')::uuid<>op then raise exception 'Wrong invitation identity';end if;
 if public.inspect_forwarded_operator_invitation(hash) is null then raise exception 'Inspection consumed invitation';end if;
 perform public.claim_forwarded_operator_invitation(hash);
 begin perform public.claim_forwarded_operator_invitation(hash);raise exception 'QA replay accepted';exception when others then if sqlerrm<>'Invitation invalid, expired or already used' then raise;end if;end;
 perform public.release_forwarded_operator_invitation(hash);
 if public.inspect_forwarded_operator_invitation(hash) is null then raise exception 'Failed request cannot resume';end if;
 perform public.claim_forwarded_operator_invitation(hash);
 perform public.finish_forwarded_operator_invitation(hash);
 if public.inspect_forwarded_operator_invitation(hash) is not null then raise exception 'Used invitation still accepted';end if;
 if not exists(select 1 from public.personnel_onboarding where profile_id=op and status='active') then raise exception 'Onboarding not completed';end if;
 -- Only a backend service may issue, inspect or redeem invitations.
 if has_function_privilege('anon','public.claim_forwarded_operator_invitation(text)','EXECUTE') or has_function_privilege('authenticated','public.issue_forwarded_operator_invitation(uuid,text,uuid)','EXECUTE') then raise exception 'Client has backend-only privileges';end if;
end $qa$;
rollback;
select 'PASS: 72-hour expiry, repeat-safe inspection, atomic claim, replay rejection, recovery after failed Auth update, completion and backend-only grants. Fixtures rolled back; no password changed.' result;
