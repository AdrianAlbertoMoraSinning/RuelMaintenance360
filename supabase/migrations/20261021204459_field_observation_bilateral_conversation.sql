-- Conversations are evidence belonging to one observation, independent of its workflow status.
create table public.field_observation_messages(
 id bigint generated always as identity primary key,
 observation_id uuid not null references public.field_observations(id) on delete cascade,
 author_id uuid not null references public.profiles(id),
 author_name text not null,
 author_role text not null check(author_role in ('reporter','reviewer')),
 body text not null check(length(btrim(body)) between 1 and 10000),
 client_message_id uuid not null,
 created_at timestamptz not null default clock_timestamp(),
 unique(author_id,client_message_id)
);
create index field_observation_message_order on public.field_observation_messages(observation_id,id);
create table public.field_observation_message_reads(
 observation_id uuid not null references public.field_observations(id) on delete cascade,
 user_id uuid not null references public.profiles(id),
 last_seen_message_id bigint not null default 0,
 primary key(observation_id,user_id)
);
alter table public.field_observation_messages enable row level security;
alter table public.field_observation_message_reads enable row level security;
create policy observation_chat_read on public.field_observation_messages for select to authenticated using((select private.can_review_observation(observation_id)) and exists(select 1 from public.profiles where id=(select auth.uid()) and active));
create policy observation_chat_reads on public.field_observation_message_reads for select to authenticated using(user_id=(select auth.uid()) and (select private.can_review_observation(observation_id)));
revoke all on public.field_observation_messages,public.field_observation_message_reads from public,anon,authenticated;
grant select on public.field_observation_messages,public.field_observation_message_reads to authenticated,service_role;
-- Writes must pass the identity-checked RPC. Workflow requests/responses retain their existing functions.
revoke insert,update,delete,truncate,references,trigger on public.field_observation_comments from anon,authenticated;

create function private.observation_chat_context(p_observation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();o public.field_observations%rowtype;
begin
 if not exists(select 1 from public.profiles where id=actor and active) or not coalesce(private.can_review_observation(p_observation_id),false) then raise exception 'Observation access denied';end if;
 select * into o from public.field_observations where id=p_observation_id;
 return jsonb_build_object('reported_by',o.reported_by,'reporter_name',(select full_name from public.profiles where id=o.reported_by),'assigned_manager_id',o.assigned_manager_id,'reviewer_name',(select full_name from public.profiles where id=o.assigned_manager_id),'can_send',o.assigned_manager_id is not null and o.assigned_manager_id<>o.reported_by and actor in(o.reported_by,o.assigned_manager_id));
end$$;
create function public.observation_conversation_context(p_observation_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.observation_chat_context(p_observation_id)$$;

create function private.send_observation_message(p_observation_id uuid,p_body text,p_client_message_id uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();o public.field_observations%rowtype;existing public.field_observation_messages%rowtype;message_id bigint;recipient uuid;body text:=btrim(p_body);person text;
begin
 if not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 if body is null or length(body) not between 1 and 10000 or p_client_message_id is null then raise exception 'Write a message of 1 to 10000 characters';end if;
 -- Lock one observation so retries and any reviewer reassignment cannot race.
 select * into o from public.field_observations where id=p_observation_id for update;
 if o.id is null or o.assigned_manager_id is null or o.reported_by=o.assigned_manager_id or actor not in(o.reported_by,o.assigned_manager_id) then raise exception 'Only the reporter and assigned reviewer may send messages';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_client_message_id::text,0));
 select * into existing from public.field_observation_messages where author_id=actor and client_message_id=p_client_message_id;
 if found then
 if existing.observation_id<>p_observation_id or existing.body<>body then raise exception 'Retry identifier belongs to a different message';end if;
 return existing.id;
 end if;
 select coalesce(full_name,'Team member') into person from public.profiles where id=actor;
 insert into public.field_observation_messages(observation_id,author_id,author_name,author_role,body,client_message_id) values(o.id,actor,person,case when actor=o.reported_by then 'reporter' else 'reviewer' end,body,p_client_message_id) returning id into message_id;
 recipient:=case when actor=o.reported_by then o.assigned_manager_id else o.reported_by end;
 insert into public.notifications(user_id,business_unit_id,observation_id,notification_type,severity,title,message,dedupe_key)
 values(recipient,o.business_unit_id,o.id,'observation_message','info','New message · OBS-'||lpad(o.observation_number::text,6,'0'),person||': '||left(body,500),'observation-message:'||message_id::text);
 return message_id;
end$$;
create function public.send_field_observation_message(p_observation_id uuid,p_body text,p_client_message_id uuid) returns bigint language sql security invoker set search_path='' as $$select private.send_observation_message(p_observation_id,p_body,p_client_message_id)$$;

create function private.seen_observation_messages(p_observation_id uuid,p_through_message_id bigint) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();through_id bigint;
begin
 if not exists(select 1 from public.profiles where id=actor and active) or not coalesce(private.can_review_observation(p_observation_id),false) then raise exception 'Observation access denied';end if;
 select coalesce(max(id),0) into through_id from public.field_observation_messages where observation_id=p_observation_id and id<=coalesce(p_through_message_id,0);
 insert into public.field_observation_message_reads(observation_id,user_id,last_seen_message_id) values(p_observation_id,actor,through_id) on conflict(observation_id,user_id) do update set last_seen_message_id=greatest(public.field_observation_message_reads.last_seen_message_id,excluded.last_seen_message_id);
 update public.notifications n set read_at=coalesce(n.read_at,now()) where n.user_id=actor and n.observation_id=p_observation_id and n.notification_type='observation_message' and exists(select 1 from public.field_observation_messages m where m.observation_id=p_observation_id and m.id<=through_id and n.dedupe_key='observation-message:'||m.id::text);
end$$;
create function public.mark_observation_messages_seen(p_observation_id uuid,p_through_message_id bigint) returns void language sql security invoker set search_path='' as $$select private.seen_observation_messages(p_observation_id,p_through_message_id)$$;

revoke all on function private.observation_chat_context(uuid),public.observation_conversation_context(uuid),private.send_observation_message(uuid,text,uuid),public.send_field_observation_message(uuid,text,uuid),private.seen_observation_messages(uuid,bigint),public.mark_observation_messages_seen(uuid,bigint) from public,anon;
grant execute on function private.observation_chat_context(uuid),public.observation_conversation_context(uuid),private.send_observation_message(uuid,text,uuid),public.send_field_observation_message(uuid,text,uuid),private.seen_observation_messages(uuid,bigint),public.mark_observation_messages_seen(uuid,bigint) to authenticated;

create view public.field_observation_chat_updates with(security_invoker=true) as
 select o.id as observation_id,exists(select 1 from public.field_observation_messages m where m.observation_id=o.id and m.author_id<>(select auth.uid()) and m.id>coalesce(r.last_seen_message_id,0)) as has_updates
 from public.field_observations o left join public.field_observation_message_reads r on r.observation_id=o.id and r.user_id=(select auth.uid());
revoke all on public.field_observation_chat_updates from public,anon,authenticated;
grant select on public.field_observation_chat_updates to authenticated,service_role;
