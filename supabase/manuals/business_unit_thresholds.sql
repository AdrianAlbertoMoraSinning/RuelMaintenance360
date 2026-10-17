-- Versioned help for independent unit thresholds. Preserve earlier versions.
begin;
do $guard$ begin
 if exists(select 1 from public.section_manuals where version='2.2' and section_key in('admin','work_orders','inventory','vendors','reports','analytics','business_units','planning','maintenance','approvals','readiness')) then raise exception 'Manual version 2.2 already exists'; end if;
end $guard$;
insert into public.section_manuals(section_key,title,purpose,audience,quick_start,workflow,field_help,warnings,version,active)
select section_key,title,purpose,audience,
 case when section_key='admin' then 'Use Production users for real personnel and configure the confidential CAD authorization threshold separately for every Business Unit. Only an active Super Admin may read or save these amounts. A blank amount is unconfigured, not zero.' else quick_start end,
 case when section_key='admin' then workflow || jsonb_build_array('Review every Business Unit threshold row. Enter the agreed CAD amount and save that unit. Other unsaved unit inputs are preserved. A missing amount blocks new authorization requests only for that unit.') else workflow end,
 field_help || jsonb_build_object(
  'Corporate threshold','Corporate authorization uses the threshold for the Work Order Business Unit. There is no global fallback. Only active Super Admins may see or change the amounts.',
  'Business Unit threshold','Manager approval is required first. Estimates strictly above the unit threshold also require Super Admin approval. An estimate equal to the threshold does not add that stage. Zero is valid and escalates every positive estimate.',
  'Threshold snapshot','Each authorization request retains its selected unit threshold. Changing settings does not rewrite prior requests. Moving a Work Order to another unit resets authorization and requires a new request using the destination unit threshold.',
  'Threshold readiness','The readiness audit counts Business Units with missing thresholds. It does not expose confidential amounts.'
 ),
 warnings || E'\nEach Business Unit needs its own agreed CAD threshold. Missing configuration blocks requests for that unit; no amount is inferred from another unit or the old global setting. Saving cost settings does not grant approval or closure authority.',
 '2.2',true
from public.section_manuals where active and section_key in('admin','work_orders','inventory','vendors','reports','analytics','business_units','planning','maintenance','approvals','readiness');
update public.section_manuals set active=false,updated_at=now()
where active and version<>'2.2' and section_key in('admin','work_orders','inventory','vendors','reports','analytics','business_units','planning','maintenance','approvals','readiness');
commit;
