-- Preserve the existing asset/accountability checks and component RLS in one transaction.
create or replace function public.create_asset_with_parts(p_asset jsonb, p_parts jsonb default '[]'::jsonb)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_asset_id uuid; v_item jsonb; v_part_id uuid; v_type text; v_quantity numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_asset) is distinct from 'object' or jsonb_typeof(p_parts) is distinct from 'array' then
    raise exception 'Asset details and a parts array are required';
  end if;
  v_asset_id := public.create_asset_with_primary_responsible(
    (p_asset->>'business_unit_id')::uuid, (p_asset->>'responsible_user_id')::uuid,
    p_asset->>'asset_code', p_asset->>'name', p_asset->>'asset_category',
    nullif(btrim(p_asset->>'manufacturer'),''), nullif(btrim(p_asset->>'model'),''),
    nullif(btrim(p_asset->>'serial_number'),''), nullif(p_asset->>'year','')::integer,
    coalesce((p_asset->>'criticality')::smallint,3::smallint), nullif(btrim(p_asset->>'notes'),'')
  );
  for v_item in select value from jsonb_array_elements(p_parts) loop
    if jsonb_typeof(v_item) is distinct from 'object' then raise exception 'Invalid component row'; end if;
    v_part_id := (v_item->>'part_id')::uuid;
    if v_part_id is null or not exists(select 1 from public.parts_visible where id=v_part_id and active) then
      raise exception 'Select an active inventory part for every component';
    end if;
    v_type := coalesce(v_item->>'relationship_type','installed');
    if v_type not in ('installed','compatible') then raise exception 'Invalid component relationship'; end if;
    v_quantity := case when v_type='compatible' then 0 else (v_item->>'installed_quantity')::numeric end;
    if v_quantity is null or v_quantity < 0 or v_quantity >= 1000000000 or (v_type='installed' and v_quantity=0) then
      raise exception 'Installed quantity must be positive and below 1,000,000,000';
    end if;
    if exists(select 1 from public.asset_part_compatibility where asset_id=v_asset_id and part_id=v_part_id) then
      raise exception 'Each catalogue reference can appear once; combine its installed quantity';
    end if;
    insert into public.asset_part_compatibility(asset_id,part_id,relationship_type,installed_quantity,component_system,installation_position,preferred,notes)
    values(v_asset_id,v_part_id,v_type,v_quantity,nullif(btrim(v_item->>'component_system'),''),nullif(btrim(v_item->>'installation_position'),''),coalesce((v_item->>'preferred')::boolean,false),nullif(btrim(v_item->>'notes'),''));
  end loop;
  return v_asset_id;
end;
$$;
revoke all on function public.create_asset_with_parts(jsonb,jsonb) from public, anon;
grant execute on function public.create_asset_with_parts(jsonb,jsonb) to authenticated;
