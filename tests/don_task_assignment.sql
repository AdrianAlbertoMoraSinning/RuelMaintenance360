-- Exercise the real supervisor account. No tasks or notifications survive this transaction.
begin;
select set_config('request.jwt.claim.sub','ea8946ea-e093-4ad1-a886-954fb91187db',true);
set local role authenticated;
do $$
declare parent_id uuid;child_id uuid;standalone_id uuid;failed boolean;
begin
 parent_id:=public.create_operation_task(jsonb_build_object('title','TRANSIENT-DON parent assignment','assigned_to','0d87a0bf-b3a8-434b-9012-45c5d9bacfff','business_unit_id','772039c9-622b-430c-90d7-8278adaa42aa','due_at',now()+interval '2 days'));
 perform set_config('request.jwt.claim.sub','0d87a0bf-b3a8-434b-9012-45c5d9bacfff',true);
 if not exists(select 1 from public.task_assignment_candidates() where id='b6a1f147-ae25-4b3e-bdb5-f35c5b4addba') then raise exception 'DJ missing from Don assignment recipients';end if;
 standalone_id:=public.create_operation_task(jsonb_build_object('title','TRANSIENT-DON standalone assignment','assigned_to','b6a1f147-ae25-4b3e-bdb5-f35c5b4addba','business_unit_id','772039c9-622b-430c-90d7-8278adaa42aa','asset_id','','parent_task_id','','maintenance_plan_id','','description','Validate standalone assignment','origin','manual','priority','normal','due_at',now()+interval '1 day','checklist',jsonb_build_array(jsonb_build_object('label','Check condition','required',true))));
 child_id:=public.create_operation_task(jsonb_build_object('title','TRANSIENT-DON linked delegation','assigned_to','b6a1f147-ae25-4b3e-bdb5-f35c5b4addba','business_unit_id','772039c9-622b-430c-90d7-8278adaa42aa','parent_task_id',parent_id,'due_at',now()+interval '1 day'));
 if not exists(select 1 from public.operation_task_inbox where id=child_id and parent_task_id=parent_id and assigned_by=auth.uid()) then raise exception 'Linked delegation not visible to Don';end if;
 failed:=false;begin
  perform public.create_operation_task(jsonb_build_object('title','TRANSIENT-DON forbidden assignment','assigned_to','ea8946ea-e093-4ad1-a886-954fb91187db','due_at',now()));
 exception when raise_exception then failed:=true;end;
 if not failed then raise exception 'Supervisor was allowed to assign to CEO';end if;
 perform set_config('request.jwt.claim.sub','b6a1f147-ae25-4b3e-bdb5-f35c5b4addba',true);
 if (select count(*) from public.operation_task_inbox where id in(child_id,standalone_id))<>2 then raise exception 'DJ cannot see both assigned tasks';end if;
 if not exists(select 1 from public.notifications where user_id=auth.uid() and task_id=child_id) then raise exception 'DJ assignment notification missing';end if;
end$$;
rollback;
