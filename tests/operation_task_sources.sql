-- PM and WO calendar integration: no fixtures survive the transaction.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where active and personnel_category='manager' and email='concrete@ruelconcreteltd.com'),true);
do $$
declare mgr uuid:=auth.uid();op uuid;sup uuid;unit_id uuid;machine uuid;plan_id uuid;wo uuid;v_task uuid;first_due timestamptz;count_events bigint;failed boolean;wo_status text;wo_approval text;
begin
 select p.id,p.corporate_manager_id into op,sup from public.profiles p where p.active and p.role='operator' and p.full_name not like '[MOC]%' limit 1;
 select business_unit_id into unit_id from public.user_unit_access where user_id=op limit 1;
 machine:=public.create_asset_with_parts(jsonb_build_object('business_unit_id',unit_id,'responsible_user_id',sup,'asset_code','TRANSIENT-TODO-'||gen_random_uuid(),'name','Transient source test','asset_category','BATCH_PLANT','criticality','3'),'[]');
 update public.assets set hour_meter=120 where id=machine;
 insert into public.maintenance_plans(asset_id,title,plan_type,assigned_to,next_due_hours,procedure) values(machine,'TRANSIENT-TODO meter PM','preventive',op,100,'[{"label":"Check condition"},{"label":"Record findings"}]') returning id into plan_id;
 perform set_config('request.jwt.claim.sub',op::text,true);
 perform public.refresh_operation_task_sources();
 select id,due_at into v_task,first_due from public.operation_tasks where maintenance_plan_id=plan_id;
 if v_task is null or (select count(*) from public.operation_task_checks where operation_task_checks.task_id=v_task)<>2 then raise exception 'Meter PM did not create its checklist';end if;
 select count(*) into count_events from public.operation_task_activity where operation_task_activity.task_id=v_task;
 perform public.refresh_operation_task_sources();
 if (select due_at from public.operation_tasks where id=v_task) is distinct from first_due or (select count(*) from public.operation_task_activity where operation_task_activity.task_id=v_task)<>count_events then raise exception 'Meter schedule drifted on refresh';end if;
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 insert into public.work_orders(business_unit_id,asset_id,type,title,assigned_to,maintenance_plan_id,scheduled_for) values(unit_id,machine,'preventive','TRANSIENT-TODO linked WO',op,plan_id,now()) returning id into wo;
 select status::text,execution_approval_status into wo_status,wo_approval from public.work_orders where id=wo;
 perform set_config('request.jwt.claim.sub',op::text,true);
 perform public.refresh_operation_task_sources();
 if not exists(select 1 from public.operation_tasks where id=v_task and work_order_id=wo and source_key='wo:'||wo||':'||op) then raise exception 'WO did not absorb plan reminder';end if;
 perform public.refresh_operation_task_sources();
 if (select count(*) from public.operation_tasks where maintenance_plan_id=plan_id)<>1 then raise exception 'WO source duplicated absorbed reminder';end if;
 failed:=false;begin perform public.update_operation_task(v_task,'Attempt bypass WO approval',100,'completion_requested',(select jsonb_agg(jsonb_build_object('id',id,'done',true)) from public.operation_task_checks where operation_task_checks.task_id=v_task));exception when raise_exception then failed:=true;end;
 if not failed then raise exception 'Task completion bypassed controlled WO';end if;
 if not exists(select 1 from public.work_orders where id=wo and status::text=wo_status and execution_approval_status is not distinct from wo_approval) then raise exception 'To-do changed WO approval or status';end if;
end $$;
rollback;
select 'PASS: meter PM/checklist, stable schedule, WO absorption without duplicates and controlled approval boundary; fixtures rolled back' as result;
