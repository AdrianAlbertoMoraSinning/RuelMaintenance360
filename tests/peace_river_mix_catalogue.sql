begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where active and personnel_category='ceo' limit 1),true);
set local role authenticated;
do $$
declare plant_unit uuid;pid uuid;bad boolean;workspace jsonb;
begin
 select id into strict plant_unit from public.business_units where code='CONC-PR';
 if (select count(*) from public.production_products where business_unit_id=plant_unit and reference_code is not null)<>79 then raise exception 'Expected 79 imported references';end if;
 if not exists(select 1 from public.production_products where business_unit_id=plant_unit and reference_code='GR25S' and catalogue_description='25MPA Type S W/AIR' and unit='m³' and source_reference like '%GR25S!B4:B6%') then raise exception 'Original mix description or provenance missing';end if;
 workspace:=public.production_workspace();
 if not exists(select 1 from jsonb_array_elements(workspace->'products') p where p->>'reference_code'='35C1GU20A' and p->>'business_unit_id'=plant_unit::text) then raise exception 'Catalogue reference absent from workspace';end if;
 pid:=(public.production_command('product',jsonb_build_object('business_unit_id',plant_unit,'name','[QA rollback] Catalogue reference','reference_code','QA-NEW-MIX','unit','m³','kind','product'))->>'id')::uuid;
 if not exists(select 1 from public.production_products where id=pid and reference_code='QA-NEW-MIX' and name='QA-NEW-MIX — [QA rollback] Catalogue reference') then raise exception 'Manual reference creation failed';end if;
 bad:=false;begin perform public.production_command('product',jsonb_build_object('business_unit_id',plant_unit,'name','Duplicate code','reference_code','qa-new-mix','unit','m³','kind','product'));exception when unique_violation then bad:=true;end;if not bad then raise exception 'Duplicate reference allowed';end if;
end$$;
reset role;
select 'peace_river_mix_catalogue_passed' as result;
rollback;
