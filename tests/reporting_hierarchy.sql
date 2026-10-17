-- Commissioning QA: uses existing MOC users only; every change is rolled back.
begin;
set local request.jwt.claims = '{"sub":"2fb0bab9-a296-499c-80fe-fdb87f1127ce","role":"authenticated"}';
do $qa$
declare
  employee uuid;
  supervisor uuid;
  manager uuid;
  other_supervisor uuid;
  unit_id uuid;
  asset uuid;
  order_id uuid;
begin
  select id into strict employee from public.profiles where full_name='[MOC] Casey White' and role='operator';
  select id,corporate_manager_id into strict supervisor,manager from public.profiles where full_name='[MOC] Riley Chen' and role='unit_supervisor';
  select id into strict other_supervisor from public.profiles where full_name='[MOC] Sam Patel' and role='unit_supervisor';
  update public.profiles set corporate_manager_id=supervisor where id=employee;
  if private.resolve_execution_approver(employee) is distinct from manager then
    raise exception 'Supervisor reporting line did not escalate to the corporate approver';
  end if;
  if private.resolve_execution_approver(supervisor) is distinct from manager then
    raise exception 'Direct corporate-manager route regressed';
  end if;

  begin
    update public.profiles set corporate_manager_id=employee where id=employee;
    raise exception 'QA_SELF_ACCEPTED';
  exception when others then
    if sqlerrm not like '%their own Reporting Manager%' then raise; end if;
  end;
  begin
    update public.profiles set corporate_manager_id=supervisor where id=manager;
    raise exception 'QA_CYCLE_ACCEPTED';
  exception when others then
    if sqlerrm not like '%hierarchy cycle%' then raise; end if;
  end;
  begin
    update public.profiles set active=false where id=supervisor;
    raise exception 'QA_DEACTIVATION_ACCEPTED';
  exception when others then
    if sqlerrm not like '%Reassign active direct reports%' then raise; end if;
  end;
  begin
    update public.profiles set role='technician' where id=supervisor;
    raise exception 'QA_DEMOTION_ACCEPTED';
  exception when others then
    if sqlerrm not like '%Reassign active direct reports%' then raise; end if;
  end;
  update public.profiles set active=false where id=other_supervisor;
  begin
    update public.profiles set corporate_manager_id=other_supervisor where id=employee;
    raise exception 'QA_INACTIVE_MANAGER_ACCEPTED';
  exception when others then
    if sqlerrm not like '%Reporting Manager must be an active%' then raise; end if;
  end;

  select a.id,a.business_unit_id into strict asset,unit_id from public.assets a
  join public.business_units b on b.id=a.business_unit_id where b.code='HEAVY-EQP' order by a.id limit 1;
  perform public.set_business_unit_approval_threshold(unit_id,1000);
  insert into public.work_orders(asset_id,business_unit_id,title,status,type,priority,assigned_to,requested_by,estimated_cost)
  values(asset,unit_id,'[QA rollback] Reporting hierarchy approval','open','corrective','low',employee,auth.uid(),100)
  returning id into order_id;
  perform public.request_work_order_execution_approval(order_id);
  if not exists(select 1 from public.work_orders where id=order_id and manager_approver_id=manager
     and execution_approval_status='pending_manager' and corporate_approval_required=false) then
    raise exception 'WO authorization was routed incorrectly';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',supervisor,'role','authenticated')::text,true);
  begin
    perform public.approve_work_order_execution_manager(order_id,'QA supervisor must not approve');
    raise exception 'QA_SUPERVISOR_APPROVAL_ACCEPTED';
  exception when others then
    if sqlerrm not like '%Only the assigned employee manager%' then raise; end if;
  end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',manager,'role','authenticated')::text,true);
  perform public.approve_work_order_execution_manager(order_id,'QA corporate manager approval');
  if not exists(select 1 from public.work_orders where id=order_id and execution_approval_status='approved') then
    raise exception 'Corporate manager could not authorize the correctly routed WO';
  end if;
  -- A larger estimate must retain the separate corporate authorization stage.
  insert into public.work_orders(asset_id,business_unit_id,title,status,type,priority,assigned_to,requested_by,estimated_cost)
  values(asset,unit_id,'[QA rollback] Reporting hierarchy corporate threshold','open','corrective','low',employee,auth.uid(),2000)
  returning id into order_id;
  perform public.request_work_order_execution_approval(order_id);
  perform public.approve_work_order_execution_manager(order_id,'QA threshold escalation');
  if not exists(select 1 from public.work_orders where id=order_id and execution_approval_status='pending_super_admin'
     and corporate_approval_required=true and execution_approved_at is null) then
    raise exception 'Corporate threshold escalation regressed';
  end if;
  if has_function_privilege('authenticated','private.resolve_execution_approver(uuid)','execute')
     or has_function_privilege('anon','private.resolve_execution_approver(uuid)','execute') then
    raise exception 'Internal hierarchy resolver is callable directly';
  end if;
end
$qa$;
select 'PASS: supervisor reporting, corporate authorization routing, cycle/self/inactive-manager rejection, deactivation/demotion guards, unchanged corporate threshold, private resolver. All fixtures rolled back.' as result;
rollback;
