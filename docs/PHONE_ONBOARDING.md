# Supervisor-forwarded operator activation

Operators retain their real mobile number as the login identifier. Administrators create the phone account from the trusted roster with its existing unit, operator role and reporting supervisor. The assigned supervisor receives a personal activation link by email and forwards it privately to the operator’s registered phone using their own SMS service. No SMS provider is used by this workflow.

The link is a 256-bit random bearer credential in a URL fragment. Only its SHA-256 hash is stored in a private RLS-protected table; browser history is cleared before the Auth client initializes and the page uses no-referrer. It expires after 72 hours. Inspection does not consume it, so email scanners and previews cannot activate it. A valid password submission atomically claims it. A concurrent or repeated claim fails. Auth update failures release the claim; a failure after password update keeps it claimed for administrator review. Completion consumes the link, activates the retained onboarding record and writes an audit event. Clients cannot directly invoke the backend-only database functions.

The recipient sets their own password; the delegated link authorizes enrollment through the supervisor. This is not automated SMS verification. On acceptance, Auth marks the phone identity confirmed so phone/password login can be used. Phone login must be enabled in project settings before an invitation is sent. Public phone signup or SMS auto-confirmation is not required by this design and must not be enabled to work around enrollment.

The administrator control prepares a link to copy into a supervisor email; it does not send an email automatically. Preparing another link revokes previous pending links. Never publish an invitation link in source code, screenshots, logs or shared reports. The operator enters Observations and can read only their own full report history.

Validation: eleven Auth/phone/token tests, production build, rollback tests of expiry, scanner-safe inspection, claim/replay/release/completion and database grants; malformed public redemption rejected. Actual recipient acceptance must be performed by the operator.
