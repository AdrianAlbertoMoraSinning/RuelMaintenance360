-- Task conversation reuses immutable task evidence, including existing direct comments.
alter table public.operation_task_activity add column client_message_id uuid;
create unique index operation_task_message_retry on public.operation_task_activity(actor_id,client_message_id) where client_message_id is not null;
create index operation_task_conversation_order on public.operation_task_activity(task_id,id) where event_type='comment' and task_id=source_task_id;
alter table public.operation_task_reads add column last_seen_message_id bigint not null default 0;

create view public.operation_task_conversation with(security_invoker=true) as
 select e.id,e.task_id,e.actor_id,private.todo_person_label(e.task_id,e.actor_id) as author_name,e.message as body,e.created_at,e.client_message_id
 from public.operation_task_activity e where e.event_type='comment' and e.task_id=e.source_task_id;
revoke all on public.operation_task_conversation from public,anon,authenticated;
grant select on public.operation_task_conversation to authenticated,service_role;

create function private.todo_send_message(p_task uuid,p_body text,p_client_message_id uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();t public.operation_tasks%rowtype;existing public.operation_task_activity%rowtype;result_id bigint;body text:=btrim(p_body);
begin
 if not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 if p_client_message_id is null or body is null or length(body) not between 1 and 10000 then raise exception 'Write a message of 1 to 10000 characters';end if;
 perform private.todo_lock_tree(p_task);
 select * into t from public.operation_tasks where id=p_task for update;
 if t.id is null or actor not in(t.assigned_by,t.assigned_to) then raise exception 'Only the task assigner and assignee may send messages';end if;
 select * into existing from public.operation_task_activity where actor_id=actor and client_message_id=p_client_message_id;
 if found then
 if existing.task_id<>p_task or existing.message<>body then raise exception 'Retry identifier belongs to a different message';end if;
 return existing.id;
 end if;
 -- A clarification never changes progress, approval, completion or the checklist.
 perform private.todo_activity(p_task,actor,'comment',body);
 select last_activity_id into result_id from public.operation_tasks where id=p_task;
 update public.operation_task_activity set client_message_id=p_client_message_id where id=result_id;
 return result_id;
end $$;
create function public.send_operation_task_message(p_task_id uuid,p_body text,p_client_message_id uuid) returns bigint language sql security invoker set search_path='' as $$select private.todo_send_message(p_task_id,p_body,p_client_message_id)$$;
revoke all on function private.todo_send_message(uuid,text,uuid),public.send_operation_task_message(uuid,text,uuid) from public,anon;
grant execute on function private.todo_send_message(uuid,text,uuid),public.send_operation_task_message(uuid,text,uuid) to authenticated;

create function private.todo_seen_messages(p_task uuid,p_through bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();seen_id bigint;
begin
 if not private.todo_can_view(p_task,actor) then raise exception 'Task access denied';end if;
 select coalesce(max(id),0) into seen_id from public.operation_task_activity where task_id=p_task and source_task_id=p_task and event_type='comment' and id<=coalesce(p_through,0);
 insert into public.operation_task_reads(task_id,user_id,last_seen_message_id) values(p_task,actor,seen_id) on conflict(task_id,user_id) do update set last_seen_message_id=greatest(public.operation_task_reads.last_seen_message_id,excluded.last_seen_message_id);
end $$;
create function public.mark_operation_task_messages_seen(p_task_id uuid,p_through_message_id bigint) returns void language sql security invoker set search_path='' as $$select private.todo_seen_messages(p_task_id,p_through_message_id)$$;
revoke all on function private.todo_seen_messages(uuid,bigint),public.mark_operation_task_messages_seen(uuid,bigint) from public,anon;
grant execute on function private.todo_seen_messages(uuid,bigint),public.mark_operation_task_messages_seen(uuid,bigint) to authenticated;

create or replace view public.operation_task_inbox with(security_invoker=true) as
 select t.*,private.todo_person_label(t.id,t.assigned_to) as assignee_name,private.todo_person_label(t.id,t.assigned_by) as assigner_name,b.asset_code,b.name as asset_name,
 exists(select 1 from public.operation_task_activity e where e.task_id=t.id and e.id>coalesce(r.last_seen_activity_id,0) and e.actor_id is distinct from (select auth.uid()) and (e.event_type<>'comment' or e.id>coalesce(r.last_seen_message_id,0))) as has_updates,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id) as child_count,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id and c.status='completed') as children_completed,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id) as check_count,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id and c.done) as checks_done
 from public.operation_tasks t left join public.assets b on b.id=t.asset_id left join public.operation_task_reads r on r.task_id=t.id and r.user_id=(select auth.uid());
revoke all on public.operation_task_inbox from public,anon,authenticated;grant select on public.operation_task_inbox to authenticated,service_role;

update public.section_manuals set workflow=workflow||jsonb_build_array('Open Task conversation inside an assignment to ask questions, provide instructions and reply. Messages retain their author and timestamp, and remain available after completion. Only the assigner and assignee can reply; authorized linked-task owners can read the evidence.'),updated_at=now() where section_key='todo';
