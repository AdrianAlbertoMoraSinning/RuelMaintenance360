-- Versioned manual content for the reporting hierarchy commissioning change.
begin;
do $guard$ begin
  if exists(select 1 from public.section_manuals where section_key in ('admin','work_orders') and version='1.4') then
    raise exception 'Manual 1.4 already exists; inspect it before applying this seed';
  end if;
end $guard$;
insert into public.section_manuals(section_key,title,purpose,audience,quick_start,workflow,field_help,warnings,version,active)
select section_key,title,purpose,audience,
  case section_key when 'admin' then
    'Manage personnel identity and direct Reporting Managers separately from system roles and approval authority. A Supervisor can be a Reporting Manager. WO execution authorization follows that reporting line to the first active Corporate Manager or Super Admin. Only Super Admins can view or change the confidential corporate cost threshold.'
  else
    'Assign the work order and request execution authorization. The reporting line is followed through any Supervisors to the first active Corporate Manager or Super Admin. Estimates above the confidential threshold still need the separate corporate authorization stage before work can begin.'
  end,
  case section_key when 'admin' then jsonb_build_array(
    'Use Production users for real personnel; MOC / training users remain available in a separate filter.',
    'Keep Position, Personnel Category, System Role, Reporting Manager and Business Unit Access separate.',
    'Choose an active Supervisor, Corporate Manager or Super Admin as the direct Reporting Manager. Self-reporting and cycles are rejected.',
    'Reassign active direct reports before deactivating a manager or removing their supervisory role.',
    'A Supervisor can view costs in authorized units without gaining execution approval authority.',
    'Only a Super Admin sets the confidential corporate cost threshold. Safety routes to the direct Reporting Manager plus Primary OHS.'
  ) else jsonb_build_array(
    'Assign the employee who will perform or coordinate the work and enter the estimated cost.',
    'Request execution approval. Supervisors in the reporting line are passed over for this approval; the first active Corporate Manager or Super Admin receives it.',
    'If the estimate exceeds the confidential corporate threshold, manager approval is followed by the corporate approval stage.',
    'Only after execution authorization is approved may work start, parts be issued or vendors be committed.',
    'Record diagnosis, corrective action, evidence, costs and downtime. Critical work retains controlled completion approval.'
  ) end,
  field_help || jsonb_build_object('Reporting Manager','The direct organizational manager, which may be a Supervisor. This assignment does not grant spending or execution approval authority.'),
  warnings || E'\nReporting lines do not grant approval authority. Supervisor cost visibility remains limited to authorized units. Operator/Technician cost masking remains a separate commissioning item.',
  '1.4',true
from public.section_manuals where active and section_key in ('admin','work_orders');
update public.section_manuals set active=false,updated_at=now()
where section_key in ('admin','work_orders') and version<>'1.4' and active;
commit;
