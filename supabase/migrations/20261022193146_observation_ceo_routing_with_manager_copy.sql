-- Explicit CEO recipient with direct-manager accountability and copied chat.
alter table public.field_observations add column addressed_to_id uuid references public.profiles(id);
create index field_observations_addressed_to_idx on public.field_observations(addressed_to_id);
CREATE OR REPLACE FUNCTION private.notify_observation_recipients(p_observation_id uuid, p_title text, p_message text, p_severity text DEFAULT 'info'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'private'
AS $function$
declare v record;
begin
  for v in
    select distinct x.user_id from (
      select o.assigned_manager_id user_id from public.field_observations o where o.id=p_observation_id and o.assigned_manager_id is not null
      union
      select o.addressed_to_id from public.field_observations o where o.id=p_observation_id and o.addressed_to_id is not null
      union
      select private.primary_ohs_admin_user_id() from public.field_observations o where o.id=p_observation_id and o.observation_type='safety'
    ) x where x.user_id is not null
  loop
    if exists(select 1 from public.notifications n where n.user_id=v.user_id and n.dedupe_key='observation:'||p_observation_id::text) then
      update public.notifications set severity=p_severity,title=p_title,message=p_message,read_at=null,created_at=now() where user_id=v.user_id and dedupe_key='observation:'||p_observation_id::text;
    else
      insert into public.notifications(user_id,business_unit_id,observation_id,safety_case_id,notification_type,severity,title,message,dedupe_key)
      select v.user_id,o.business_unit_id,o.id,o.safety_case_id,case when o.observation_type='safety' then 'safety_observation' else 'field_observation' end,p_severity,p_title,p_message,'observation:'||o.id::text from public.field_observations o where o.id=p_observation_id;
    end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION private.send_observation_message(p_observation_id uuid, p_body text, p_client_message_id uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();o public.field_observations%rowtype;existing public.field_observation_messages%rowtype;message_id bigint;recipient uuid;body text:=btrim(p_body);person text;
begin
 if not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Active account required';end if;
 if body is null or length(body) not between 1 and 10000 or p_client_message_id is null then raise exception 'Write a message of 1 to 10000 characters';end if;
 -- Lock one observation so retries and any reviewer reassignment cannot race.
 select * into o from public.field_observations where id=p_observation_id for update;
 if o.id is null or o.assigned_manager_id is null or o.reported_by=o.assigned_manager_id or not (actor=o.reported_by or actor=o.assigned_manager_id or coalesce(actor=o.addressed_to_id,false)) then raise exception 'Only the reporter, assigned manager and addressed recipient may send messages';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_client_message_id::text,0));
 select * into existing from public.field_observation_messages where author_id=actor and client_message_id=p_client_message_id;
 if found then
 if existing.observation_id<>p_observation_id or existing.body<>body then raise exception 'Retry identifier belongs to a different message';end if;
 return existing.id;
 end if;
 select coalesce(full_name,'Team member') into person from public.profiles where id=actor;
 insert into public.field_observation_messages(observation_id,author_id,author_name,author_role,body,client_message_id) values(o.id,actor,person,case when actor=o.reported_by then 'reporter' else 'reviewer' end,body,p_client_message_id) returning id into message_id;
 for recipient in select distinct p.id from public.profiles p where p.id in(o.reported_by,o.assigned_manager_id,o.addressed_to_id) and p.id<>actor and p.active loop
 insert into public.notifications(user_id,business_unit_id,observation_id,notification_type,severity,title,message,dedupe_key)
 values(recipient,o.business_unit_id,o.id,'observation_message','info','New message · OBS-'||lpad(o.observation_number::text,6,'0'),person||': '||left(body,500),'observation-message:'||message_id::text);
 end loop;
 return message_id;
end$function$;
create function private.observation_ceo() returns uuid language sql stable security definer set search_path='' as $$
 select p.id from public.task_governance g join public.profiles p on p.id=g.ceo_user_id where g.singleton and p.active and p.personnel_category='ceo' and p.role in ('super_admin','corporate_manager')
$$;
create function private.observation_route_allowed(p_observation_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.field_observations o join public.profiles a on a.id=(select auth.uid()) join public.profiles m on m.id=o.assigned_manager_id where o.id=p_observation_id and a.active and m.active and o.status not in ('resolved','closed_no_action','rejected') and private.observation_ceo() is not null and (a.id=o.assigned_manager_id or(a.id=o.reported_by and (a.role in ('unit_supervisor','corporate_manager') or a.personnel_category in ('supervisor','manager')))))
$$;
create function private.observation_recipient_options(p_business_unit_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles%rowtype;manager uuid;ceo uuid:=private.observation_ceo();begin
 select * into actor from public.profiles where id=auth.uid() and active;
 if actor.id is null or (p_business_unit_id is not null and not private.can_access_unit(p_business_unit_id)) then raise exception 'Observation access denied';end if;
 manager:=actor.corporate_manager_id;
 if manager is null then select supervisor_user_id into manager from public.business_units where id=p_business_unit_id;end if;
 return jsonb_build_object('manager',(select jsonb_build_object('id',id,'name',full_name) from public.profiles where id=manager and active),'ceo',(select jsonb_build_object('id',id,'name',full_name) from public.profiles where id=ceo),'can_address_ceo',coalesce(ceo is not null and ceo<>actor.id and manager is not null and (actor.role in ('unit_supervisor','corporate_manager') or actor.personnel_category in ('supervisor','manager')),false));
end $$;
create function public.observation_recipient_options(p_business_unit_id uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select private.observation_recipient_options(p_business_unit_id)$$;
create function private.escalate_observation_to_ceo(p_observation_id uuid,p_note text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();o public.field_observations%rowtype;ceo uuid:=private.observation_ceo();begin
 select * into o from public.field_observations where id=p_observation_id for update;
 if not coalesce(private.observation_route_allowed(p_observation_id),false) then raise exception 'Only the reporting supervisor/manager or the assigned manager may send an open observation to the CEO';end if;
 if o.addressed_to_id=ceo then return jsonb_build_object('observation_id',o.id,'recipient_id',ceo,'copied_manager_id',o.assigned_manager_id,'idempotent',true);end if;
 if length(coalesce(p_note,''))>10000 then raise exception 'Routing note must be at most 10000 characters';end if;
 update public.field_observations set addressed_to_id=ceo,updated_at=now() where id=o.id;
 insert into public.field_observation_history(observation_id,event_type,actor_id,from_status,to_status,details) values(o.id,'addressed_to_ceo',actor,o.status,o.status,jsonb_build_object('recipient_id',ceo,'copied_manager_id',o.assigned_manager_id,'note',coalesce(nullif(btrim(p_note),''),'Sent to CEO with the assigned manager copied')));
 perform private.notify_observation_recipients(o.id,case when o.observation_type='safety' then 'Safety · CEO review · OBS-' else 'CEO review · OBS-' end||lpad(o.observation_number::text,6,'0'),'To CEO · CC direct manager. '||left(o.description,400),case when o.immediate_concern='immediate_safety' then 'critical' when o.immediate_concern='equipment_unsafe' then 'warning' else 'info' end);
 return jsonb_build_object('observation_id',o.id,'recipient_id',ceo,'copied_manager_id',o.assigned_manager_id,'idempotent',false);
end $$;
create function public.escalate_observation_to_ceo(p_observation_id uuid,p_note text default '') returns jsonb language sql security invoker set search_path='' as $$select private.escalate_observation_to_ceo(p_observation_id,p_note)$$;
create function private.submit_addressed_field_observation(p_client_draft_id uuid,p_business_unit_id uuid,p_asset_id uuid,p_observation_type text,p_description text,p_immediate_concern text,p_recipient_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;o public.field_observations%rowtype;begin
 -- Existing intake, safety routing and AI review gates are preserved.
 result:=private.submit_field_observation(p_client_draft_id,p_business_unit_id,p_asset_id,p_observation_type,p_description,p_immediate_concern);
 select * into o from public.field_observations where id=(result->>'observation_id')::uuid for update;
 if coalesce((result->>'idempotent')::boolean,false) then
 if p_recipient_id is not null and p_recipient_id is distinct from coalesce(o.addressed_to_id,o.assigned_manager_id) then raise exception 'This saved report has a different recipient. Open it to request escalation';end if;
 return result;end if;
 if p_recipient_id is not null and p_recipient_id is distinct from o.assigned_manager_id then
 if p_recipient_id is distinct from private.observation_ceo() then raise exception 'Choose the direct manager or the authorized CEO';end if;
 perform private.escalate_observation_to_ceo(o.id,'Reporter selected the CEO; direct manager remains copied');
 end if;return result;
end $$;
create function public.submit_addressed_field_observation(p_client_draft_id uuid,p_business_unit_id uuid,p_asset_id uuid,p_observation_type text,p_description text,p_immediate_concern text default 'normal',p_recipient_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.submit_addressed_field_observation(p_client_draft_id,p_business_unit_id,p_asset_id,p_observation_type,p_description,p_immediate_concern,p_recipient_id)$$;
create function private.observation_routing_context(p_observation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.field_observations%rowtype;begin
 if not coalesce(private.can_review_observation(p_observation_id),false) or private.current_role() is null then raise exception 'Observation access denied';end if;
 select * into o from public.field_observations where id=p_observation_id;
 return jsonb_build_object('recipient_id',coalesce(o.addressed_to_id,o.assigned_manager_id),'recipient_name',(select full_name from public.profiles where id=coalesce(o.addressed_to_id,o.assigned_manager_id)),'manager_id',o.assigned_manager_id,'manager_name',(select full_name from public.profiles where id=o.assigned_manager_id),'ceo_name',(select full_name from public.profiles where id=private.observation_ceo()),'can_escalate',private.observation_route_allowed(o.id) and o.addressed_to_id is distinct from private.observation_ceo());end $$;
create function public.observation_routing_context(p_observation_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.observation_routing_context(p_observation_id)$$;
create or replace function private.observation_chat_context(p_observation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();o public.field_observations%rowtype;begin
 if not exists(select 1 from public.profiles where id=actor and active) or not coalesce(private.can_review_observation(p_observation_id),false) then raise exception 'Observation access denied';end if;
 select * into o from public.field_observations where id=p_observation_id;
 return jsonb_build_object('reported_by',o.reported_by,'reporter_name',(select full_name from public.profiles where id=o.reported_by),'assigned_manager_id',o.assigned_manager_id,'reviewer_name',(select full_name from public.profiles where id=o.assigned_manager_id),'can_send',o.assigned_manager_id is not null and o.assigned_manager_id<>o.reported_by and actor=any(array_remove(array[o.reported_by,o.assigned_manager_id,o.addressed_to_id],null)),'participants',(select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by case when p.id=o.addressed_to_id then 0 when p.id=o.assigned_manager_id then 1 else 2 end) from public.profiles p where p.id in(o.reported_by,o.assigned_manager_id,o.addressed_to_id) and p.active));
end $$;
-- A direct client UPDATE cannot bypass the routing RPC's audit and notification.
create function private.guard_observation_recipient_write() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if current_user not in ('postgres','supabase_admin','service_role') and (new.addressed_to_id is not null or (tg_op='UPDATE' and new.addressed_to_id is distinct from old.addressed_to_id)) then raise exception 'Use the observation recipient routing command';end if;return new;end $$;
revoke all on function private.guard_observation_recipient_write() from public,anon,authenticated;
create trigger observation_recipient_write before insert or update of addressed_to_id on public.field_observations for each row execute function private.guard_observation_recipient_write();
revoke all on function private.observation_ceo(),private.observation_route_allowed(uuid),private.observation_recipient_options(uuid),public.observation_recipient_options(uuid),private.escalate_observation_to_ceo(uuid,text),public.escalate_observation_to_ceo(uuid,text),private.submit_addressed_field_observation(uuid,uuid,uuid,text,text,text,uuid),public.submit_addressed_field_observation(uuid,uuid,uuid,text,text,text,uuid),private.observation_routing_context(uuid),public.observation_routing_context(uuid) from public,anon,authenticated;
grant execute on function private.observation_ceo(),private.observation_route_allowed(uuid),private.observation_recipient_options(uuid),public.observation_recipient_options(uuid),private.escalate_observation_to_ceo(uuid,text),public.escalate_observation_to_ceo(uuid,text),private.submit_addressed_field_observation(uuid,uuid,uuid,text,text,text,uuid),public.submit_addressed_field_observation(uuid,uuid,uuid,text,text,text,uuid),private.observation_routing_context(uuid),public.observation_routing_context(uuid) to authenticated;
