-- Entry reminders use per-user unread activity, not every pending assignment.
-- No production tasks, notifications or read cursors survive this test.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='don@ruelconcreteltd.com'),true);
select set_config('qa.entry_operator',(select profile_id::text from public.personnel_onboarding where preferred_name='DJ'),true);
set local role authenticated;
do $$declare task uuid;observation uuid;msg bigint;reply bigint;unit_id uuid;asset_id uuid;supervisor uuid:=auth.uid();operator_id uuid:=current_setting('qa.entry_operator')::uuid;begin
 select business_unit_id,id into strict unit_id,asset_id from public.assets where asset_code='MIX-BP-SHELF';
 task:=public.create_operation_task(jsonb_build_object('title','TRANSIENT-ENTRY reminder','assigned_to',operator_id,'business_unit_id',unit_id,'due_at',now()+interval '1 day'));
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 if not exists(select 1 from public.operation_task_inbox where id=task and has_updates and (assigned_by=auth.uid() or assigned_to=auth.uid())) then raise exception 'Assignment missing from entry reminder';end if;
 perform public.mark_operation_task_seen(task,(select last_activity_id from public.operation_tasks where id=task));
 if exists(select 1 from public.operation_task_inbox where id=task and has_updates) then raise exception 'Reviewed assignment still counted as new';end if;
 perform set_config('request.jwt.claim.sub',supervisor::text,true);
 msg:=public.send_operation_task_message(task,'[QA rollback] New instruction in task chat',gen_random_uuid());
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 if not exists(select 1 from public.operation_task_inbox where id=task and has_updates) then raise exception 'Unread task chat missing from entry reminder';end if;
 perform public.mark_operation_task_messages_seen(task,msg);
 if exists(select 1 from public.operation_task_inbox where id=task and has_updates) then raise exception 'Read task chat still counted as new';end if;
 observation:=(public.submit_field_observation(gen_random_uuid(),unit_id,asset_id,'equipment','[QA rollback] Entry observation message','normal')->>'observation_id')::uuid;
 msg:=public.send_field_observation_message(observation,'[QA rollback] Question for my supervisor',gen_random_uuid());
 if exists(select 1 from public.notifications where user_id=auth.uid() and read_at is null and notification_type='observation_message' and observation_id=observation) then raise exception 'Sender received own unread message reminder';end if;
 perform set_config('request.jwt.claim.sub',supervisor::text,true);
 if (select count(*) from public.notifications where user_id=auth.uid() and read_at is null and notification_type='observation_message' and observation_id=observation)<>1 then raise exception 'Supervisor unread observation message missing';end if;
 perform public.mark_observation_messages_seen(observation,msg);
 if exists(select 1 from public.notifications where user_id=auth.uid() and read_at is null and notification_type='observation_message' and observation_id=observation) then raise exception 'Read observation message still counted as new';end if;
 reply:=public.send_field_observation_message(observation,'[QA rollback] Supervisor reply',gen_random_uuid());
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 if (select count(*) from public.notifications where user_id=auth.uid() and read_at is null and notification_type='observation_message' and observation_id=observation)<>1 then raise exception 'Operator unread supervisor reply missing';end if;
 perform public.mark_observation_messages_seen(observation,reply);
end$$;
rollback;
select 'PASS: new assignment and task chat counted, read activity removed, bilateral observation messages use only recipient notifications, read messages removed; fixtures rolled back' as result;
