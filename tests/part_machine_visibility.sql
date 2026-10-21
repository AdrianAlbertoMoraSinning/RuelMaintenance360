begin;
do $$
declare mgr uuid;sup uuid;unit_id uuid;first_asset uuid;second_asset uuid;hidden_asset uuid;part uuid;
begin
 select id into mgr from public.profiles where email='concrete@ruelconcreteltd.com';
 select id into sup from public.profiles where email='don@ruelconcreteltd.com';
 select id into unit_id from public.business_units where code='CONC-PR';
 select a.id into hidden_asset from public.assets a where not exists(select 1 from public.user_unit_access u where u.user_id=sup and u.business_unit_id=a.business_unit_id) limit 1;
 if hidden_asset is null then raise exception 'Test requires a machine outside supervisor scope';end if;
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 first_asset:=public.create_asset_with_parts(jsonb_build_object('business_unit_id',unit_id,'responsible_user_id',sup,'asset_code','TRANSIENT-PHOTO-A-'||gen_random_uuid(),'name','Transient installed machine','asset_category','BATCH_PLANT'),'[]');
 second_asset:=public.create_asset_with_parts(jsonb_build_object('business_unit_id',unit_id,'responsible_user_id',sup,'asset_code','TRANSIENT-PHOTO-B-'||gen_random_uuid(),'name','Transient compatible machine','asset_category','BATCH_PLANT'),'[]');
 insert into public.parts(part_number,description,responsible_user_id) values('TRANSIENT-BEARING-'||gen_random_uuid(),'Transient test reference',sup) returning id into part;
 insert into public.asset_part_compatibility(asset_id,part_id,relationship_type,installed_quantity,component_system,installation_position) values(first_asset,part,'installed',2,'Drive','Outlet'),(second_asset,part,'compatible',0,'Drive','Outlet'),(hidden_asset,part,'compatible',0,null,null);
 perform set_config('ruel.photo.part',part::text,true);perform set_config('ruel.photo.hidden',hidden_asset::text,true);perform set_config('request.jwt.claim.sub',sup::text,true);
end $$;
set local role authenticated;
do $$ begin
 if (select count(*) from public.asset_part_compatibility where part_id=current_setting('ruel.photo.part')::uuid)<>2 then raise exception 'Authorized shared-machine lookup omitted a record or exposed a hidden machine';end if;
 if exists(select 1 from public.assets where id=current_setting('ruel.photo.hidden')::uuid) then raise exception 'Unauthorized machine is visible';end if;
 if not exists(select 1 from public.asset_part_compatibility where part_id=current_setting('ruel.photo.part')::uuid and relationship_type='installed' and installed_quantity=2) then raise exception 'Installed quantity was lost';end if;
 if not exists(select 1 from public.asset_part_compatibility where part_id=current_setting('ruel.photo.part')::uuid and relationship_type='compatible' and installed_quantity=0) then raise exception 'Compatible spare was treated as installed';end if;
 if exists(select 1 from public.inventory_transactions where part_id=current_setting('ruel.photo.part')::uuid) then raise exception 'Lookup setup moved stock';end if;
end $$;
rollback;
select 'PASS: shared reference lists both authorized machines, distinguishes installed and compatible, hides other units and moves no stock; all fixtures rolled back' as result;
