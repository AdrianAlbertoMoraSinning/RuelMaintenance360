-- Verify imported photo integrity and scoped access without retaining test records.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where full_name='Guy Munden' and active),true);
set local role authenticated;
do $$begin
 if (select count(*) from public.asset_photo_links l join public.assets a on a.id=l.asset_id where a.asset_code like 'PRC-%')<>34 then raise exception 'CEO cannot read the expected asset photos';end if;
 if exists(select 1 from public.asset_photo_images where encode(sha256(decode(image_data,'base64')),'hex')<>content_hash) then raise exception 'Photo content integrity failed';end if;
 if has_table_privilege('anon','public.asset_photo_images','select') then raise exception 'Anonymous image access introduced';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles p where active and role='operator' and not exists(select 1 from public.user_unit_access ua join public.business_units u on u.id=ua.business_unit_id where ua.user_id=p.id and u.code='CONC-PR') limit 1),true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.asset_photo_links l join public.assets a on a.id=l.asset_id where a.asset_code like 'PRC-%') or exists(select 1 from public.asset_photo_images) then raise exception 'Other-unit operator can read plant photos';end if;
end$$;
rollback;
