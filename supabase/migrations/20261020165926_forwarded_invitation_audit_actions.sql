alter table public.admin_security_events drop constraint admin_security_events_action_check;
alter table public.admin_security_events add constraint admin_security_events_action_check check(action in ('password_changed','user_activated','user_deactivated','user_invited','ohs_administrator_invited','phone_operator_provisioned','phone_invitation_sms_requested','supervisor_forwarded_invitation_prepared','operator_activated_supervisor_forwarded_link'));
create policy operator_invitation_service_only on private.operator_invitations for all to service_role using(true) with check(true);
