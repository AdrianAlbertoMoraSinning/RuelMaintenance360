-- Apply only after financial_column_cutover. Preserve previous manual versions.
begin;
do $guard$ begin
 if exists(select 1 from public.section_manuals where version='2.1' and section_key in('admin','work_orders','inventory','vendors','reports','analytics','business_units','planning','maintenance','approvals')) then
  raise exception 'Financial-access manual version 2.1 already exists';
 end if;
end $guard$;
insert into public.section_manuals(section_key,title,purpose,audience,quick_start,workflow,field_help,warnings,version,active)
select section_key,title,purpose,audience,
 quick_start || E'\nCosts are visible to Super Admins, Corporate Managers and Supervisors in their authorized scope. Operators and Technicians use operational data without monetary values.',
 case when section_key='work_orders' then jsonb_build_array(
  'Assign the employee who will perform or coordinate the work. Authorized financial personnel provide the estimate; Operators and Technicians do not enter hidden costs.',
  'Request execution approval. The reporting line is followed through Supervisors to the first active Corporate Manager or Super Admin.',
  'Estimates above the confidential threshold require the separate corporate approval stage.',
  'Start execution, issue parts or commit vendors only after the required execution authorization is complete.',
  'Record diagnosis, corrective action, evidence, labour hours and downtime. Authorized financial personnel record costs. Critical completion retains controlled approval.'
 ) else workflow end,
 field_help || jsonb_build_object(
  'Cost visibility','Super Admin and Corporate Manager retain their authorized scope. Supervisors see costs only in authorized Business Units. Operators, Technicians, Viewers, IT and dedicated OHS roles receive no monetary values. Catalog prices are shared with authorized corporate roles and Supervisors with unit access.',
  'Hidden costs','A hidden monetary field is not zero. Operational edits preserve it, and inventory workflows resolve actual prices on the server. CSV and PDF exports omit monetary fields for roles without cost access.',
  'Corporate threshold','The configured corporate threshold and its Work Order snapshot are visible only to Super Admins. Cost visibility alone grants no spending, execution or closure approval.'
 ),
 replace(warnings,'Operator/Technician cost masking remains a separate commissioning item.','Operator/Technician monetary masking is enforced by the financial read API and base-column privileges.') || E'\nRefresh open application tabs after deployment. A stale client requesting raw monetary columns receives a permission error; this does not mean that recorded costs were deleted.',
 '2.1',true
from public.section_manuals where active and section_key in('admin','work_orders','inventory','vendors','reports','analytics','business_units','planning','maintenance','approvals');
update public.section_manuals set active=false,updated_at=now()
where active and version<>'2.1' and section_key in('admin','work_orders','inventory','vendors','reports','analytics','business_units','planning','maintenance','approvals');
commit;
