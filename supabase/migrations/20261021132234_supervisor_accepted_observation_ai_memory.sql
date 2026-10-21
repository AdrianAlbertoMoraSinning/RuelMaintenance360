create table private.observation_ai_acceptances (
 id uuid primary key default gen_random_uuid(),
 observation_id uuid not null references public.field_observations(id) on delete cascade,
 accepted_by uuid not null references public.profiles(id),
 accepted_at timestamptz not null default now(),
 acceptance_note text not null check(length(btrim(acceptance_note))>=3),
 source_snapshot jsonb not null,
 source_fingerprint text not null,
 revoked_at timestamptz,
 search_vector tsvector generated always as (to_tsvector('simple'::regconfig,coalesce(source_snapshot->>'description','')||' '||coalesce(source_snapshot->>'resolution_notes',''))) stored
);
create unique index observation_ai_one_current on private.observation_ai_acceptances(observation_id) where revoked_at is null;
create index observation_ai_search on private.observation_ai_acceptances using gin(search_vector);
alter table private.observation_ai_acceptances enable row level security;
revoke all on private.observation_ai_acceptances from public,anon,authenticated;
grant usage on schema private to authenticated;
grant select on private.observation_ai_acceptances to authenticated;
grant all on private.observation_ai_acceptances to service_role;
create policy observation_ai_acceptance_read on private.observation_ai_acceptances for select to authenticated using (exists(select 1 from public.field_observations o where o.id=observation_id));

create function private.observation_ai_fingerprint(o public.field_observations) returns text language sql immutable set search_path='' as $$
 select md5(jsonb_build_array(o.description,o.asset_id,o.business_unit_id,o.observation_type,o.immediate_concern,o.resolution_notes,o.reported_by,o.assigned_manager_id)::text);
$$;
revoke all on function private.observation_ai_fingerprint(public.field_observations) from public,anon;
grant execute on function private.observation_ai_fingerprint(public.field_observations) to authenticated,service_role;

create function private.accept_observation_ai(p_observation_id uuid,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); o public.field_observations; acceptance uuid;
begin
 if actor is null then raise exception 'Authentication required';end if;
 select * into strict o from public.field_observations where id=p_observation_id for update;
 if actor is distinct from o.assigned_manager_id or actor=o.reported_by or not exists(select 1 from public.profiles where id=actor and active and role in ('unit_supervisor','corporate_manager','super_admin','it_admin')) then raise exception 'Only the assigned active supervisor may accept this observation for AI';end if;
 if o.status in ('rejected','information_requested') then raise exception 'Resolve the review before accepting this observation';end if;
 if length(btrim(coalesce(p_note,'')))<3 then raise exception 'A supervisor acceptance note is required';end if;
 if o.description ~* '^\s*\[(MOC|MOCK|QA)' or exists(select 1 from public.profiles where id=o.reported_by and full_name like '[MOC]%') or exists(select 1 from public.assets where id=o.asset_id and asset_code like 'MOC-%') then raise exception 'Training observations cannot enter real AI memory';end if;
 select id into acceptance from private.observation_ai_acceptances where observation_id=o.id and revoked_at is null and source_fingerprint=private.observation_ai_fingerprint(o);
 if acceptance is not null then return acceptance;end if;
 update private.observation_ai_acceptances set revoked_at=now() where observation_id=o.id and revoked_at is null;
 if o.status='submitted' then update public.field_observations set status='under_review',first_reviewed_at=coalesce(first_reviewed_at,now()),updated_at=now() where id=o.id;end if;
 insert into private.observation_ai_acceptances(observation_id,accepted_by,acceptance_note,source_snapshot,source_fingerprint)
 values(o.id,actor,btrim(p_note),to_jsonb(o),private.observation_ai_fingerprint(o)) returning id into acceptance;
 insert into public.field_observation_history(observation_id,event_type,actor_id,from_status,to_status,details)
 values(o.id,'accepted_for_ai',actor,o.status,case when o.status='submitted' then 'under_review' else o.status end,jsonb_build_object('acceptance_id',acceptance,'note',btrim(p_note)));
 return acceptance;
end $$;
revoke all on function private.accept_observation_ai(uuid,text) from public,anon;
grant execute on function private.accept_observation_ai(uuid,text) to authenticated;
create function public.accept_observation_for_ai(p_observation_id uuid,p_note text) returns uuid language sql security invoker set search_path='' as $$select private.accept_observation_ai(p_observation_id,p_note);$$;
revoke all on function public.accept_observation_for_ai(uuid,text) from public,anon;
grant execute on function public.accept_observation_for_ai(uuid,text) to authenticated;

create function private.invalidate_observation_ai_acceptance() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if private.observation_ai_fingerprint(old)<>private.observation_ai_fingerprint(new) or new.status in ('information_requested','rejected') then
 update private.observation_ai_acceptances set revoked_at=now() where observation_id=new.id and revoked_at is null;
 end if;
 return new;
end $$;
revoke all on function private.invalidate_observation_ai_acceptance() from public,anon,authenticated;
create trigger invalidate_observation_ai_acceptance after update on public.field_observations for each row execute function private.invalidate_observation_ai_acceptance();

create view public.observation_ai_memory with (security_invoker=true) as
select o.id as observation_id,o.observation_number,o.business_unit_id,o.asset_id,o.status,
 a.id as acceptance_id,a.accepted_by,a.accepted_at,a.acceptance_note,
 a.source_snapshot->>'description' as description,a.source_snapshot->>'resolution_notes' as resolution_notes,
 a.search_vector
from public.field_observations o join private.observation_ai_acceptances a on a.observation_id=o.id
where a.revoked_at is null and a.source_fingerprint=private.observation_ai_fingerprint(o)
 and o.status not in ('information_requested','rejected');
revoke all on public.observation_ai_memory from public,anon;
grant select on public.observation_ai_memory to authenticated,service_role;
create function public.search_observation_ai_memory(p_asset_id uuid,p_query text,p_limit integer default 8)
returns setof public.observation_ai_memory language sql stable security invoker set search_path='' as $$
 select m.* from public.observation_ai_memory m
 where (m.asset_id=p_asset_id or (m.asset_id is null and m.business_unit_id in (select business_unit_id from public.assets where id=p_asset_id)))
 and m.search_vector @@ websearch_to_tsquery('simple'::regconfig,left(coalesce(p_query,''),500))
 order by ts_rank(m.search_vector,websearch_to_tsquery('simple'::regconfig,left(coalesce(p_query,''),500))) desc,m.accepted_at desc
 limit least(greatest(coalesce(p_limit,8),1),20);
$$;
revoke all on function public.search_observation_ai_memory(uuid,text,integer) from public,anon;
grant execute on function public.search_observation_ai_memory(uuid,text,integer) to authenticated,service_role;
