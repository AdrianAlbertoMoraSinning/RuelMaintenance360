-- Keep contextual help aligned with the invitation password screen.
begin;
do $guard$ begin
 if exists(select 1 from public.section_manuals where section_key in('admin','profile') and version='2.3') then raise exception 'Invitation manual 2.3 already exists'; end if;
end $guard$;
insert into public.section_manuals(section_key,title,purpose,audience,quick_start,workflow,field_help,warnings,version,active)
select section_key,title,purpose,audience,quick_start,
 workflow || jsonb_build_array('Invited users open their personal invitation link and create a matching password of at least 10 characters before continuing to the workspace. Expired or already-used links require a fresh invitation from an administrator.'),
 field_help || jsonb_build_object(
  'Invitation password','Each invited user chooses their own password on the verified invitation screen. Never share passwords or forward invitation links. An incomplete setup resumes for the same account after refresh.',
  'Invitation readiness','Configure a production SMTP provider and confirm sending limits before a large campaign. Prepare the real participant email, role, Reporting Manager and Business Unit access matrix. MOC/training users are not production recipients.',
  'Delivery status','An accepted send request does not prove inbox delivery or account acceptance. Complete a real invitation, password creation, sign-out and password sign-in test before a larger batch.'
 ),
 warnings || E'\nAdministration currently sends invitations individually. Do not assume bulk delivery is ready solely because the email template preview looks correct.',
 '2.3',true
from public.section_manuals where active and section_key in('admin','profile');
update public.section_manuals set active=false,updated_at=now() where active and section_key in('admin','profile') and version<>'2.3';
commit;
