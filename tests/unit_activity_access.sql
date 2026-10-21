begin;
-- Test fixtures and all messages are rolled back.
insert into public.operation_tasks(id,title,description,business_unit_id,assigned_by,assigned_to,due_at)
values ('789b1aca-0040-4b3e-bf63-18ef93006c51','QA unit activity observer','Read-only validation','772039c9-622b-430c-90d7-8278adaa42aa','0d87a0bf-b3a8-434b-9012-45c5d9bacfff','b6a1f147-ae25-4b3e-bdb5-f35c5b4addba',now()),
('789b1aca-0040-4b3e-bf63-18ef93006c52','QA unit activity supervisor','Read-only validation','772039c9-622b-430c-90d7-8278adaa42aa','ea8946ea-e093-4ad1-a886-954fb91187db','2fb0bab9-a296-499c-80fe-fdb87f1127ce',now()),
('789b1aca-0040-4b3e-bf63-18ef93006c53','QA corporate activity privacy','Read-only validation',null,'ea8946ea-e093-4ad1-a886-954fb91187db','2fb0bab9-a296-499c-80fe-fdb87f1127ce',now());
select set_config('request.jwt.claim.sub','ea8946ea-e093-4ad1-a886-954fb91187db',true);
set local role authenticated;
do $$begin
 if not exists(select 1 from public.operation_task_inbox where id='789b1aca-0040-4b3e-bf63-18ef93006c51' and assignee_name is not null) then raise exception 'CEO cannot inspect unit task and participant names';end if;
 begin
  perform public.send_operation_task_message('789b1aca-0040-4b3e-bf63-18ef93006c51','QA read-only attempt',gen_random_uuid());
  raise exception 'Observer was allowed to send a message';
 exception when others then
  if sqlerrm not like '%Only the task assigner and assignee%' then raise;end if;
 end;
 begin
  perform public.review_operation_task('789b1aca-0040-4b3e-bf63-18ef93006c51','cancel','QA read-only attempt',0);
  raise exception 'Observer was allowed to review a task';
 exception when others then
  if sqlerrm not like '%Only the task assigner%' then raise;end if;
 end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','0d87a0bf-b3a8-434b-9012-45c5d9bacfff',true);
set local role authenticated;
do $$begin
 if not exists(select 1 from public.operation_task_inbox where id='789b1aca-0040-4b3e-bf63-18ef93006c52') then raise exception 'Unit supervisor cannot inspect own unit';end if;
 if exists(select 1 from public.operation_task_inbox where id='789b1aca-0040-4b3e-bf63-18ef93006c53') then raise exception 'Supervisor can inspect unrelated corporate task';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','53bc4a33-6d79-4164-8937-b19c757d56ac',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.operation_task_inbox where id in('789b1aca-0040-4b3e-bf63-18ef93006c51','789b1aca-0040-4b3e-bf63-18ef93006c52')) then raise exception 'Other-unit supervisor sees plant activity';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','f126df16-2496-4d7b-8d56-c62f01e5cda6',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.operation_task_inbox where id in('789b1aca-0040-4b3e-bf63-18ef93006c51','789b1aca-0040-4b3e-bf63-18ef93006c52')) then raise exception 'Unrelated operator sees plant activity';end if;
end$$;
rollback;
