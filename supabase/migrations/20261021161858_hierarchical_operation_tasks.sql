-- Operational task delegation is independent of authentication/admin privileges and WO approvals.
create table public.task_governance(singleton boolean primary key default true check(singleton),ceo_user_id uuid references public.profiles(id),updated_by uuid references public.profiles(id),updated_at timestamptz not null default now());
create table public.task_committee_members(user_id uuid primary key references public.profiles(id),active boolean not null default true,appointed_by uuid references public.profiles(id),updated_at timestamptz not null default now());
insert into public.task_governance(singleton,ceo_user_id) select true,id from public.profiles where active and personnel_category='ceo' order by created_at limit 1;
-- Explicit client direction: the active Shareholders constitute the committee.
insert into public.task_committee_members(user_id) select id from public.profiles where active and personnel_category='shareholder';
create table public.operation_tasks(
 id uuid primary key default gen_random_uuid(),task_number bigint generated always as identity unique,
 title text not null check(length(btrim(title)) between 1 and 200),description text not null default '' check(length(description)<=10000),
 business_unit_id uuid references public.business_units(id),asset_id uuid references public.assets(id),
 assigned_by uuid not null references public.profiles(id),assigned_to uuid not null references public.profiles(id),created_by uuid references public.profiles(id),
 parent_task_id uuid references public.operation_tasks(id),origin text not null default 'manual' check(origin in ('manual','emergency','maintenance','work_order','observation')),
 maintenance_plan_id uuid references public.maintenance_plans(id),work_order_id uuid references public.work_orders(id),observation_action_id uuid references public.field_observation_actions(id),source_key text unique,
 source_status text,source_approval text,due_at timestamptz not null,priority text not null default 'normal' check(priority in ('normal','high','emergency')),
 status text not null default 'pending' check(status in ('pending','in_progress','blocked','completion_requested','completed','cancelled')),
 progress integer not null default 0 check(progress between 0 and 100),last_activity_id bigint not null default 0,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),completed_at timestamptz,reviewed_by uuid references public.profiles(id),
 check(assigned_by<>assigned_to),check(parent_task_id is distinct from id)
);
create index operation_tasks_assignee_due on public.operation_tasks(assigned_to,status,due_at);
create index operation_tasks_assigner_due on public.operation_tasks(assigned_by,status,due_at);
create index operation_tasks_parent on public.operation_tasks(parent_task_id);
create index operation_tasks_unit on public.operation_tasks(business_unit_id);
create index operation_tasks_asset on public.operation_tasks(asset_id);
create index operation_tasks_plan on public.operation_tasks(maintenance_plan_id);
create index operation_tasks_wo on public.operation_tasks(work_order_id);
create index operation_tasks_action on public.operation_tasks(observation_action_id);
create table public.operation_task_checks(id uuid primary key default gen_random_uuid(),task_id uuid not null references public.operation_tasks(id) on delete cascade,position integer not null,label text not null check(length(btrim(label)) between 1 and 1000),required boolean not null default true,done boolean not null default false,done_by uuid references public.profiles(id),done_at timestamptz,unique(task_id,position));
create table public.operation_task_activity(id bigint generated always as identity primary key,task_id uuid not null references public.operation_tasks(id) on delete cascade,source_task_id uuid not null references public.operation_tasks(id),actor_id uuid references public.profiles(id),event_type text not null,message text not null,progress integer not null,created_at timestamptz not null default now());
create index operation_task_activity_task on public.operation_task_activity(task_id,id desc);
create index operation_task_activity_source on public.operation_task_activity(source_task_id);
create index operation_task_activity_actor on public.operation_task_activity(actor_id);
create table public.operation_task_reads(task_id uuid not null references public.operation_tasks(id) on delete cascade,user_id uuid not null references public.profiles(id),last_seen_activity_id bigint not null default 0,primary key(task_id,user_id));
create index operation_task_reads_user on public.operation_task_reads(user_id);
alter table public.notifications add column task_id uuid references public.operation_tasks(id) on delete cascade;
create index notifications_task_id on public.notifications(task_id);

create function private.todo_can_assign(p_actor uuid,p_target uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a public.profiles%rowtype;b public.profiles%rowtype;ceo uuid;
begin
 select * into a from public.profiles where id=p_actor and active;select * into b from public.profiles where id=p_target and active;
 if a.id is null or b.id is null or a.id=b.id then return false;end if;
 select ceo_user_id into ceo from public.task_governance where singleton;
 if exists(select 1 from public.task_committee_members where user_id=a.id and active) then return b.id=ceo;end if;
 if a.id=ceo then return b.personnel_category in ('manager','supervisor') or b.role in ('corporate_manager','unit_supervisor');end if;
 if b.corporate_manager_id is distinct from a.id then return false;end if;
 if a.personnel_category='manager' or a.role='corporate_manager' then return b.personnel_category='supervisor' or b.role='unit_supervisor';end if;
 if a.personnel_category='supervisor' or a.role='unit_supervisor' then return b.role in ('operator','technician','viewer') and b.personnel_category not in ('ceo','shareholder','manager','supervisor');end if;
 return false;
end $$;
create function private.todo_unit_access(p_user uuid,p_unit uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=p_user and p.active and (p_unit is null or p.role in ('super_admin','corporate_manager') or exists(select 1 from public.user_unit_access u where u.user_id=p.id and u.business_unit_id=p_unit)))
$$;
create function private.todo_can_view(p_task uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 with recursive chain as(select id,parent_task_id,assigned_by,assigned_to from public.operation_tasks where id=p_task union all select t.id,t.parent_task_id,t.assigned_by,t.assigned_to from public.operation_tasks t join chain c on t.id=c.parent_task_id)
 select exists(select 1 from public.profiles where id=p_user and active) and exists(select 1 from chain where assigned_by=p_user or assigned_to=p_user)
$$;
create function private.todo_lock_tree(p_task uuid) returns void language plpgsql security definer set search_path='' as $$
declare root uuid;begin
 with recursive chain as(select id,parent_task_id from public.operation_tasks where id=p_task union all select t.id,t.parent_task_id from public.operation_tasks t join chain c on t.id=c.parent_task_id)
 select id into root from chain where parent_task_id is null;
 if root is not null then perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(root::text,178));end if;
end $$;
create function private.todo_activity(p_task uuid,p_actor uuid,p_kind text,p_message text) returns void language plpgsql security definer set search_path='' as $$
declare t record;s public.operation_tasks%rowtype;e bigint;r uuid;notified uuid[]:='{}';
begin
 select * into strict s from public.operation_tasks where id=p_task;
 for t in with recursive chain as(select id,parent_task_id,assigned_by,assigned_to from public.operation_tasks where id=p_task union all select p.id,p.parent_task_id,p.assigned_by,p.assigned_to from public.operation_tasks p join chain c on p.id=c.parent_task_id) select * from chain loop
 insert into public.operation_task_activity(task_id,source_task_id,actor_id,event_type,message,progress) values(t.id,p_task,p_actor,case when t.id=p_task then p_kind else 'linked_'||p_kind end,case when t.id=p_task then p_message else 'TASK-'||s.task_number||' · '||s.title||': '||p_message end,s.progress) returning id into e;
 update public.operation_tasks set last_activity_id=e,updated_at=now() where id=t.id;
 foreach r in array array[t.assigned_by,t.assigned_to] loop
 if r is distinct from p_actor and not r=any(notified) and exists(select 1 from public.profiles where id=r and active) then
 insert into public.notifications(user_id,business_unit_id,task_id,notification_type,severity,title,message,dedupe_key) values(r,s.business_unit_id,t.id,'task_activity',case when s.priority='emergency' then 'high' else 'info' end,'TASK-'||s.task_number||' · '||s.title,left(p_message,500),'todo:'||e||':'||r);
 notified:=array_append(notified,r);end if;end loop;
 end loop;
end $$;

alter table public.task_governance enable row level security;alter table public.task_committee_members enable row level security;alter table public.operation_tasks enable row level security;alter table public.operation_task_checks enable row level security;alter table public.operation_task_activity enable row level security;alter table public.operation_task_reads enable row level security;
create policy task_governance_read on public.task_governance for select to authenticated using(exists(select 1 from public.profiles where id=(select auth.uid()) and active));
create policy task_committee_read on public.task_committee_members for select to authenticated using(exists(select 1 from public.profiles where id=(select auth.uid()) and active));
create policy operation_tasks_read on public.operation_tasks for select to authenticated using(private.todo_can_view(id,(select auth.uid())));
create policy operation_checks_read on public.operation_task_checks for select to authenticated using(private.todo_can_view(task_id,(select auth.uid())));
create policy operation_activity_read on public.operation_task_activity for select to authenticated using(private.todo_can_view(task_id,(select auth.uid())));
create policy operation_reads_read on public.operation_task_reads for select to authenticated using(user_id=(select auth.uid()) and private.todo_can_view(task_id,(select auth.uid())));
revoke all on public.task_governance,public.task_committee_members,public.operation_tasks,public.operation_task_checks,public.operation_task_activity,public.operation_task_reads from public,anon,authenticated;
grant select on public.task_governance,public.task_committee_members,public.operation_tasks,public.operation_task_checks,public.operation_task_activity,public.operation_task_reads to authenticated;
grant all on public.task_governance,public.task_committee_members,public.operation_tasks,public.operation_task_checks,public.operation_task_activity,public.operation_task_reads to service_role;
grant usage,select on sequence public.operation_tasks_task_number_seq,public.operation_task_activity_id_seq to service_role;

create view public.operation_task_inbox with(security_invoker=true) as
 select t.*,p.full_name as assignee_name,a.full_name as assigner_name,b.asset_code,b.name as asset_name,
 exists(select 1 from public.operation_task_activity e where e.task_id=t.id and e.id>coalesce(r.last_seen_activity_id,0) and e.actor_id is distinct from (select auth.uid())) as has_updates,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id) as child_count,
 (select count(*) from public.operation_tasks c where c.parent_task_id=t.id and c.status='completed') as children_completed,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id) as check_count,
 (select count(*) from public.operation_task_checks c where c.task_id=t.id and c.done) as checks_done
 from public.operation_tasks t join public.profiles p on p.id=t.assigned_to join public.profiles a on a.id=t.assigned_by left join public.assets b on b.id=t.asset_id left join public.operation_task_reads r on r.task_id=t.id and r.user_id=(select auth.uid());
revoke all on public.operation_task_inbox from public,anon,authenticated;grant select on public.operation_task_inbox to authenticated,service_role;


revoke all on function private.todo_can_assign(uuid,uuid),private.todo_unit_access(uuid,uuid),private.todo_can_view(uuid,uuid),private.todo_lock_tree(uuid),private.todo_activity(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function private.todo_can_assign(uuid,uuid),private.todo_can_view(uuid,uuid) to authenticated;
