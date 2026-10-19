# Invitation readiness — 2026-10-19

The signed-in Supabase dashboard still shows the built-in email service and a disabled rate limit of 2 emails/hour. Custom SMTP is not configured. The corporate invite template is saved with the RUEL black/yellow design and the `ConfirmationURL` action. Site URL is `https://ruelmaintenance360.netlify.app/`. No redirect allow-list entries are configured; current invites use the root Site URL.

## Password setup

The client now captures invite/recovery purpose before Supabase consumes the callback fragment. A verified session and valid return are required before the new password form is shown. Expired or invalid returns show a dedicated error screen rather than opening another account's workspace or changing its password. The screen requires a matching password of at least 10 characters, waits for `updateUser` to succeed, then opens the existing workspace.

An unfinished setup marker is scoped to the authenticated user and survives refresh. It contains only the flow purpose; passwords and tokens are never stored there. URL auth parameters are removed when the flow finishes or the user returns to sign in. Normal login, QR asset context, roles and RLS remain unchanged. This is onboarding UX; authorization continues to be enforced by Supabase and database policies.

`npm run test:auth` covers invitation/recovery parsing, expiry flags, user-isolated resumption, blocked storage, URL cleanup, validation, backend rejection, network failure and successful password submission. No account credentials are changed by these tests. A real email acceptance/password/sign-out/password-sign-in test remains pending until delivery is configured and a participant is selected.

## Before a mass invitation campaign

- Configure a production SMTP provider and verified sender/domain; check its sending quota together with the Supabase email limit. Do not increase limits without a working provider.
- Confirm the real participant roster: email, position/category, system role, direct Reporting Manager and unit access. Existing MOC identities are not recipients.
- Configure participant permissions and verify an end-to-end invitation with an intended real recipient before a larger batch.
- Use controlled batches or a queue with individual results and backoff; the current Administration UI sends one invitation at a time. A bulk campaign feature is not certified or implemented by this change.
- Resolve pending invitations for Marcel and Sylvain after the email/password flow is verified. Do not interpret a provider acceptance response as inbox delivery.

Operational commissioning remains separate: all eight Business Unit approval amounts are unset, and the readiness audit still identifies one historical WO in an execution state without execution approval. Missing thresholds block WO authorization, not account invitations. These facts do not establish that every module is ready for production.
