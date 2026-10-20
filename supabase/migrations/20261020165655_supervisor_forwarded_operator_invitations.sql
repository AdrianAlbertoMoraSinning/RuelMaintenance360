create table private.operator_invitations (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references public.profiles(id),
 manager_id uuid not null references public.profiles(id),
 phone text not null,
 token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '72 hours',
 status text not null default 'pending' check(status in ('pending','processing','used','revoked')),
 claimed_at timestamptz,used_at timestamptz,
 check(expires_at>created_at)
);
alter table private.operator_invitations enable row level security;
revoke all on private.operator_invitations from public,anon,authenticated;
grant usage on schema private to service_role;
grant all on private.operator_invitations to service_role;

create function public.issue_forwarded_operator_invitation(p_profile_id uuid,p_token_hash text,p_actor_id uuid)
returns timestamptz language plpgsql security invoker set search_path='' as $$
declare target public.profiles%rowtype; expiry timestamptz;
begin
 if not exists(select 1 from public.profiles where id=p_actor_id and active and role in ('super_admin','it_admin')) then raise exception 'Active administrator required';end if;
 select * into strict target from public.profiles where id=p_profile_id and active and role='operator' and phone is not null for update;
 if not exists(select 1 from public.profiles where id=target.corporate_manager_id and active and email is not null) then raise exception 'Supervisor email required';end if;
 if not exists(select 1 from public.personnel_onboarding where profile_id=target.id and status<>'active') then raise exception 'Operator already activated or not in onboarding';end if;
 update private.operator_invitations set status='revoked' where profile_id=target.id and status='pending';
 insert into private.operator_invitations(profile_id,manager_id,phone,token_hash,created_by) values(target.id,target.corporate_manager_id,target.phone,p_token_hash,p_actor_id) returning expires_at into expiry;
 return expiry;
end $$;

create function public.inspect_forwarded_operator_invitation(p_token_hash text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('profile_id',p.id,'full_name',p.full_name,'phone',p.phone,'supervisor',m.full_name,'expires_at',i.expires_at)
 from private.operator_invitations i join public.profiles p on p.id=i.profile_id join public.profiles m on m.id=i.manager_id
 join public.personnel_onboarding o on o.profile_id=p.id
 where i.token_hash=p_token_hash and i.status='pending' and i.expires_at>now()
 and p.active and p.role='operator' and m.active and p.corporate_manager_id=i.manager_id and p.phone=i.phone and o.status<>'active';
$$;

create function public.claim_forwarded_operator_invitation(p_token_hash text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare context jsonb;
begin
 -- Lock and recheck after any concurrent redeemer has completed.
 perform 1 from private.operator_invitations where token_hash=p_token_hash for update;
 context:=public.inspect_forwarded_operator_invitation(p_token_hash);
 if context is null then raise exception 'Invitation invalid, expired or already used';end if;
 update private.operator_invitations set status='processing',claimed_at=now() where token_hash=p_token_hash and status='pending';
 if not found then raise exception 'Invitation already being processed';end if;
 return context;
end $$;

create function public.release_forwarded_operator_invitation(p_token_hash text)
returns void language sql security invoker set search_path='' as $$
 update private.operator_invitations set status='pending',claimed_at=null where token_hash=p_token_hash and status='processing';
$$;

create function public.finish_forwarded_operator_invitation(p_token_hash text)
returns void language plpgsql security invoker set search_path='' as $$
declare invitation private.operator_invitations%rowtype;
begin
 update private.operator_invitations set status='used',used_at=now() where token_hash=p_token_hash and status='processing' returning * into invitation;
 if not found then raise exception 'Invitation is not being processed';end if;
 update public.personnel_onboarding set status='active',invitation_error=null where profile_id=invitation.profile_id;
 insert into public.admin_security_events(actor_user_id,target_user_id,action) values(invitation.created_by,invitation.profile_id,'operator_activated_supervisor_forwarded_link');
end $$;

revoke all on function public.issue_forwarded_operator_invitation(uuid,text,uuid),public.inspect_forwarded_operator_invitation(text),public.claim_forwarded_operator_invitation(text),public.release_forwarded_operator_invitation(text),public.finish_forwarded_operator_invitation(text) from public,anon,authenticated;
grant execute on function public.issue_forwarded_operator_invitation(uuid,text,uuid),public.inspect_forwarded_operator_invitation(text),public.claim_forwarded_operator_invitation(text),public.release_forwarded_operator_invitation(text),public.finish_forwarded_operator_invitation(text) to service_role;
