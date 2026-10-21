-- Exercise the actual Storage and metadata RLS policies; all test records roll back.
begin;
select set_config('qa.observation_id',(select id::text from public.field_observations where reported_by=(select id from public.profiles where full_name='Adrian Mora' and active limit 1) order by submitted_at desc limit 1),true);
select set_config('qa.reporter_id',(select reported_by::text from public.field_observations where id=current_setting('qa.observation_id')::uuid),true);
select set_config('qa.ceo_id',(select id::text from public.profiles where active and personnel_category='ceo' limit 1),true);
select set_config('qa.operator_id',(select id::text from public.profiles where active and role='operator' and full_name not like '[MOC]%' limit 1),true);
select set_config('qa.photo_path',current_setting('qa.observation_id')||'/'||gen_random_uuid()||'.jpg',true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.reporter_id'),true);
do $$begin
 if not has_function_privilege(current_user,'private.can_manage_observation(uuid)','execute') then raise exception 'Storage policy helper is not callable';end if;
 if has_function_privilege('anon','private.can_manage_observation(uuid)','execute') then raise exception 'Anonymous helper access was introduced';end if;
end$$;
insert into storage.objects(bucket_id,name,owner_id,metadata) values('ruel-observation-evidence',current_setting('qa.photo_path'),current_setting('qa.reporter_id'),'{"mimetype":"image/jpeg","size":100}');
insert into public.field_observation_evidence(observation_id,uploaded_by,storage_path,file_name,mime_type,caption) values(current_setting('qa.observation_id')::uuid,auth.uid(),current_setting('qa.photo_path'),'rollback-photo.jpg','image/jpeg','[QA rollback]');
select set_config('request.jwt.claim.sub',current_setting('qa.ceo_id'),true);
do $$begin
 if not exists(select 1 from storage.objects where bucket_id='ruel-observation-evidence' and name=current_setting('qa.photo_path')) then raise exception 'CEO cannot read reporter photo';end if;
 if not exists(select 1 from public.field_observation_evidence where storage_path=current_setting('qa.photo_path')) then raise exception 'CEO cannot see photo in report';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('qa.operator_id'),true);
do $$begin
 if exists(select 1 from storage.objects where bucket_id='ruel-observation-evidence' and name=current_setting('qa.photo_path')) then raise exception 'Unrelated operator can read photo';end if;
 if exists(select 1 from public.field_observation_evidence where storage_path=current_setting('qa.photo_path')) then raise exception 'Unrelated operator can read photo metadata';end if;
end$$;
rollback;
