-- Optional personal acknowledgments, drawn by the signed-in record participant.
create table public.record_signatures (
 id uuid primary key default gen_random_uuid(),
 observation_id uuid references public.field_observations(id),
 task_id uuid references public.operation_tasks(id),
 signer_id uuid not null references public.profiles(id),
 signer_name text not null,
 signed_at timestamptz not null default now(),
 strokes jsonb not null,
 note text not null default '' check(length(note)<=500),
 snapshot jsonb not null,
 snapshot_hash text not null,
 client_id uuid not null unique,
 check(num_nonnulls(observation_id,task_id)=1)
);
create index record_signatures_observation on public.record_signatures(observation_id,signed_at desc) where observation_id is not null;
create index record_signatures_task on public.record_signatures(task_id,signed_at desc) where task_id is not null;
create index record_signatures_signer on public.record_signatures(signer_id);
create unique index record_signatures_observation_version on public.record_signatures(observation_id,signer_id,snapshot_hash) where observation_id is not null;
create unique index record_signatures_task_version on public.record_signatures(task_id,signer_id,snapshot_hash) where task_id is not null;
alter table public.record_signatures enable row level security;
revoke all on public.record_signatures from public,anon,authenticated;
grant select on public.record_signatures to authenticated;
grant all on public.record_signatures to service_role;

create function private.record_signature_access(p_observation uuid,p_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and active) and case when p_observation is not null then coalesce(private.can_review_observation(p_observation),false) when p_task is not null then coalesce(private.todo_can_view(p_task,auth.uid()),false) else false end
$$;
revoke all on function private.record_signature_access(uuid,uuid) from public,anon,authenticated;
grant execute on function private.record_signature_access(uuid,uuid) to authenticated;
create policy record_signatures_read on public.record_signatures for select to authenticated using(private.record_signature_access(observation_id,task_id));

create function private.record_signature_snapshot(p_kind text,p_record uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.field_observations%rowtype;t public.operation_tasks%rowtype;r jsonb;
begin
 if p_kind='observation' then
 if not private.record_signature_access(p_record,null) then raise exception 'Observation access denied';end if;
 select * into o from public.field_observations where id=p_record;
 r:=jsonb_build_object('reference','OBS-'||lpad(o.observation_number::text,6,'0'),'record_id',o.id,'description',o.description,'status',o.status,'type',o.observation_type,'urgency',o.immediate_concern,'business_unit_id',o.business_unit_id,'asset_id',o.asset_id,'reporter_id',o.reported_by,'manager_id',o.assigned_manager_id,'addressed_to_id',o.addressed_to_id,'resolution_notes',o.resolution_notes,'manager_disposition',o.manager_disposition,'work_order_id',o.resulting_work_order_id,'safety_case_id',o.safety_case_id,
 'photo_references',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'file_name',e.file_name,'caption',e.caption) order by e.id) from public.field_observation_evidence e where e.observation_id=o.id),'[]'::jsonb));
 elsif p_kind='task' then
 if not private.record_signature_access(null,p_record) then raise exception 'Task access denied';end if;
 select * into t from public.operation_tasks where id=p_record;
 r:=jsonb_build_object('reference','TASK-'||t.task_number,'record_id',t.id,'title',t.title,'description',t.description,'status',t.status,'progress',t.progress,'due_at',t.due_at,'priority',t.priority,'business_unit_id',t.business_unit_id,'asset_id',t.asset_id,'assigner_id',t.assigned_by,'assignee_id',t.assigned_to,'parent_task_id',t.parent_task_id,'work_order_id',t.work_order_id,'completed_at',t.completed_at,
 'checklist',coalesce((select jsonb_agg(jsonb_build_object('id',ch.id,'label',ch.label,'required',ch.required,'done',ch.done) order by ch.position) from public.operation_task_checks ch where ch.task_id=t.id),'[]'::jsonb),
 'latest_update',(select jsonb_build_object('id',a.id,'message',a.message,'event_type',a.event_type) from public.operation_task_activity a where a.task_id=t.id and a.event_type not in ('comment','linked_comment','signature_added','linked_signature_added') order by a.id desc limit 1));
 else raise exception 'Select an observation or task';end if;
 return r;
end $$;
revoke all on function private.record_signature_snapshot(text,uuid) from public,anon,authenticated;

create function private.record_signature_context(p_kind text,p_record uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();s jsonb;h text;can_sign boolean;
begin
 s:=private.record_signature_snapshot(p_kind,p_record);h:=encode(extensions.digest(s::text,'sha256'),'hex');
 if p_kind='observation' then select actor=any(array_remove(array[reported_by,assigned_manager_id,addressed_to_id],null)) into can_sign from public.field_observations where id=p_record;
 else select actor in(assigned_by,assigned_to) into can_sign from public.operation_tasks where id=p_record;end if;
 return jsonb_build_object('can_sign',coalesce(can_sign,false),'snapshot',s,'snapshot_hash',h,'signer_name',(select full_name from public.profiles where id=actor),
 'already_signed',exists(select 1 from public.record_signatures z where z.signer_id=actor and z.snapshot_hash=h and (case when p_kind='observation' then z.observation_id=p_record else z.task_id=p_record end)),
 'signatures',coalesce((select jsonb_agg(to_jsonb(z)-'client_id' order by z.signed_at desc) from (select * from public.record_signatures where case when p_kind='observation' then observation_id=p_record else task_id=p_record end order by signed_at desc limit 50) z),'[]'::jsonb));
end $$;
create function public.record_signature_context(p_kind text,p_record_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.record_signature_context(p_kind,p_record_id)$$;
revoke all on function private.record_signature_context(text,uuid),public.record_signature_context(text,uuid) from public,anon,authenticated;
grant execute on function private.record_signature_context(text,uuid),public.record_signature_context(text,uuid) to authenticated;

create function private.add_record_signature(p_kind text,p_record uuid,p_expected_signer uuid,p_expected_hash text,p_strokes jsonb,p_note text,p_client uuid,p_confirm boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();s jsonb;h text;z public.record_signatures%rowtype;o public.field_observations%rowtype;t public.operation_tasks%rowtype;stroke jsonb;point jsonb;x numeric;y numeric;lo_x numeric:=1;hi_x numeric:=0;lo_y numeric:=1;hi_y numeric:=0;n integer:=0;recipient uuid;label text;unit_id uuid;participants uuid[];
begin
 if p_expected_signer is distinct from actor or actor is null or not exists(select 1 from public.profiles where id=actor and active) then raise exception 'Sign in as the person who drew this signature';end if;
 if p_confirm is distinct from true then raise exception 'Confirm that this is your own signature';end if;
 if p_client is null then raise exception 'Signature request identifier required';end if;
 if p_note is null or length(p_note)>500 then raise exception 'Signature note must be at most 500 characters';end if;
 if p_kind='observation' then
 select * into o from public.field_observations where id=p_record for update;
 if o.id is null or not private.record_signature_access(p_record,null) or not(actor=any(array_remove(array[o.reported_by,o.assigned_manager_id,o.addressed_to_id],null))) then raise exception 'Only observation participants can add their own signature';end if;
 participants:=array[o.reported_by,o.assigned_manager_id,o.addressed_to_id];unit_id:=o.business_unit_id;
 elsif p_kind='task' then
 select * into t from public.operation_tasks where id=p_record for update;
 if t.id is null or not private.record_signature_access(null,p_record) or actor not in(t.assigned_by,t.assigned_to) then raise exception 'Only the task assigner and assignee can add their own signature';end if;
 participants:=array[t.assigned_by,t.assigned_to];unit_id:=t.business_unit_id;
 else raise exception 'Select an observation or task';end if;
 select * into z from public.record_signatures where client_id=p_client;
 if z.id is not null then
 if z.signer_id<>actor or z.snapshot_hash is distinct from p_expected_hash or z.strokes is distinct from p_strokes or z.note is distinct from btrim(p_note) or (case when p_kind='observation' then z.observation_id is distinct from p_record else z.task_id is distinct from p_record end) then raise exception 'Signature request already used for different data';end if;
 return z.id;end if;
 s:=private.record_signature_snapshot(p_kind,p_record);h:=encode(extensions.digest(s::text,'sha256'),'hex');
 if h is distinct from p_expected_hash then raise exception 'This record changed. Cancel signing, review the latest saved record and draw your signature again';end if;
 if jsonb_typeof(p_strokes) is distinct from 'array' or octet_length(p_strokes::text)>200000 then raise exception 'Invalid or oversized signature';end if;
 if jsonb_array_length(p_strokes) not between 1 and 100 then raise exception 'Draw your signature in the signature box';end if;
 for stroke in select value from jsonb_array_elements(p_strokes) loop
 if jsonb_typeof(stroke) is distinct from 'array' then raise exception 'Invalid signature stroke';end if;
 if jsonb_array_length(stroke) not between 2 and 4000 then raise exception 'Invalid signature stroke';end if;
 for point in select value from jsonb_array_elements(stroke) loop
 if jsonb_typeof(point) is distinct from 'array' then raise exception 'Invalid signature point';end if;
 if jsonb_array_length(point)<>2 or jsonb_typeof(point->0) is distinct from 'number' or jsonb_typeof(point->1) is distinct from 'number' then raise exception 'Invalid signature point';end if;
 x:=(point->>0)::numeric;y:=(point->>1)::numeric;
 if x not between 0 and 1 or y not between 0 and 1 then raise exception 'Invalid signature coordinates';end if;
 n:=n+1;if n>4000 then raise exception 'Signature is too long. Clear and draw again';end if;
 lo_x:=least(lo_x,x);hi_x:=greatest(hi_x,x);lo_y:=least(lo_y,y);hi_y:=greatest(hi_y,y);
 end loop;end loop;
 if n<8 or hi_x-lo_x<0.02 or hi_y-lo_y<0.02 then raise exception 'Draw a visible signature, not a blank box or a dot';end if;
 select * into z from public.record_signatures where signer_id=actor and snapshot_hash=h and case when p_kind='observation' then observation_id=p_record else task_id=p_record end;
 if z.id is not null then return z.id;end if;
 select full_name into label from public.profiles where id=actor;
 insert into public.record_signatures(observation_id,task_id,signer_id,signer_name,strokes,note,snapshot,snapshot_hash,client_id) values(case when p_kind='observation' then p_record end,case when p_kind='task' then p_record end,actor,coalesce(nullif(label,''),'Team member'),p_strokes,btrim(p_note),s,h,p_client) returning * into z;
 -- Signature evidence is separate: no progress/status, approval, AI-memory or chat mutation.
 for recipient in select distinct v from unnest(participants) r(v) join public.profiles p on p.id=v where v<>actor and p.active loop
 insert into public.notifications(user_id,business_unit_id,observation_id,task_id,notification_type,severity,title,message,dedupe_key) values(recipient,unit_id,case when p_kind='observation' then p_record end,case when p_kind='task' then p_record end,case when p_kind='observation' then 'field_observation' else 'task_activity' end,'info','Signature added - '||(s->>'reference'),coalesce(label,'Team member')||' added a personal signature. Open the record to view the signed details.','signature:'||z.id::text);
 end loop;
 return z.id;
end $$;
create function public.add_record_signature(p_kind text,p_record_id uuid,p_expected_signer uuid,p_expected_hash text,p_strokes jsonb,p_note text,p_client_id uuid,p_confirm boolean) returns uuid language sql security invoker set search_path='' as $$select private.add_record_signature(p_kind,p_record_id,p_expected_signer,p_expected_hash,p_strokes,p_note,p_client_id,p_confirm)$$;
revoke all on function private.add_record_signature(text,uuid,uuid,text,jsonb,text,uuid,boolean),public.add_record_signature(text,uuid,uuid,text,jsonb,text,uuid,boolean) from public,anon,authenticated;
grant execute on function private.add_record_signature(text,uuid,uuid,text,jsonb,text,uuid,boolean),public.add_record_signature(text,uuid,uuid,text,jsonb,text,uuid,boolean) to authenticated;
