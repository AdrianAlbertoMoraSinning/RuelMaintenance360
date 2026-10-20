# Phone operator onboarding

An administrator provisions a phone account from the retained personnel roster. The server takes the role, number, reporting manager and business unit from that record, creates the Auth user without marking their phone verified, saves the operator profile and unit access, and retains the account ID before sending. Retrying uses the same identity. Active operators cannot be reprovisioned through this action.

SMS requires Phone Auth and a funded, configured supported provider. The client never creates new identities (`shouldCreateUser:false`). SMS acceptance by Auth is recorded separately from activation; provider errors remain visible. No delivery claim is inferred from API acceptance. The generic activation URL contains no recipient or credential: https://ruelmaintenance360.netlify.app/?setup=phone .

Configure the Supabase SMS template with an invitation and activation URL, for example:

RUEL Maintenance 360: Activate your operator account at https://ruelmaintenance360.netlify.app/?setup=phone . Your verification code is {{ .Code }}. Do not share this code.

The recipient verifies their own SMS code, saves a password and completes activation. Server completion requires a confirmed phone and a saved password for the authenticated user. Ordinary subsequent login uses phone plus password. Operators enter Observations, see their own reports including resolved history, and cannot read other reporters' observations via the Data API.

Validation: authentication tests, phone normalization and code-format tests, production TypeScript build, anonymous completion rejection and transactionally rolled-back operator observation visibility checks. Real SMS delivery and device acceptance remain blocked until provider commissioning. No SMS provider account was purchased or created as part of this change.
