# Production & Dispatch pilot — 0.3.0

Independent operational ledger; existing maintenance tables and workflows are unchanged. Business Unit Performance replaces the retired duplicate Dashboard as the management home. Every unit has production drilldown; operators retain Observations/My To-do and enrolled drivers open My deliveries.

## Setup

1. Administration: create the real driver's account, authorize Peace River Mobile Concrete Fleet access. Existing invitation/recovery flow is retained. No new invitations are sent by this release.
2. Production & Dispatch → Customers & setup: register customer, email/phone, delivery sites/addresses and the unit's products/services (m³, t, h, service, load, each). No fabricated customers, products or drivers are inserted.
3. Enroll the authorized fleet user as a driver. This is a separate capability, not an administrator role. Select an active vehicle from fleet assets.
4. New order: select customer/site/product, quantity and requested Alberta delivery time; dictate instructions or type. Temporary order reference can be replaced with the external Amsio order number. Amsio is a manually aligned reference, not an API integration.
5. Plan one or more loads within remaining order quantity. Confirm production/service readiness before departure.
6. Driver: DEPART → ARRIVED → COMPLETE DELIVERY. Each event is audited with capture and receipt time. Completing all ordered quantity closes the order; partial delivery leaves it pending. Completion means driver service completion, not customer acceptance. Travel/site/total time contributes to Fleet metrics, separately from plant production.
7. Add update supports text, voice dictation, recorded audio with browser transcription when supported, photos, video/audio attachments. Review transcript before sending; use keyboard dictation/type a summary where browser recognition is unavailable. Original audio is retained when recorded/attached. There is no server speech transcription service configured. Files: allow-listed MIME types, max 20 MB; use JPG/PNG/WebP for photos. HEIC needs conversion. Driver updates are internal; managers explicitly publish individual notes/evidence.
8. Generate a private 90-day tracking link. Copy the customer message or open an email draft. Replacing invalidates previous token. Email/SMS are not automatically sent: system email delivery is still unconfigured. Customer page refreshes every 30 seconds and shows only server-received events and explicitly shared evidence. No GPS tracking or ETA is inferred.

## Reliability and boundaries

Driver events/messages/media persist to a separate IndexedDB outbox before sending. Sync uses account ownership, immutable client UUIDs, sequential event validation and transaction-level idempotency. Sync retries when online/app opens; pending updates remain visible and cannot update the customer until received. A rejected transition stays queued for review rather than silently discarded. Offline drafts are device/browser-local; clearing browser storage loses unuploaded updates. Core order/setup forms require a connection. The app update guard protects active edits/recording; already committed outbox records survive reload.

Private storage bucket; RLS read policies, explicit least-privilege Data API grants, manager-scoped commands and driver enrollment checks. The public Edge Function is a deliberate capability endpoint; its database RPC is service-role-only: 192-bit random token, only SHA-256 stored, curated response, no anonymous table access. Fragment URL avoids sending token in HTTP navigation/referrers. Edge Function signs only published attachment paths for two minutes. A tracking link grants read-only access; visiting does not acknowledge receipt. Keep links private; regenerate to revoke. Never store tokens in notifications or logs.

Production statistics separate each physical unit of measure. No production stock consumption, recipes, fiscal invoicing or automatic Amsio interface is enabled. Validate real opening stock and approved recipes before enabling a dedicated production-origin inventory transaction. Never use maintenance work orders or stock adjustments as a substitute. No duplicate material consumption or transport revenue is generated.

## Validation

`npm run build`, `npm run test:production`, existing regression suites, and `tests/production_dispatch.sql` (transaction rolled back). Tests cover manager setup, partial/multiple deliveries, over-dispatch denial, driver isolation, event sequence/readiness, idempotent retries, private notes, link rotation and anonymous denial. No QA fixtures survive. A real phone/driver/customer acceptance walkthrough with actual customer data is still required before pilot dispatch.
