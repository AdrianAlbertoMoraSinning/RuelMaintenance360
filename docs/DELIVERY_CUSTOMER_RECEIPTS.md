# Customer delivery receipt · 0.3.5

The assigned driver can collect the customer's finger-drawn signature after arrival. This is acceptance of one specific load, not the entire multi-load order, an invoice, GPS departure or driver completion.

## On the driver's phone
1. Open My deliveries and confirm ARRIVED (or wait for server-confirmed GPS arrival).
2. Before finishing, tap Collect customer signature. A connection is required; sync queued arrival first.
3. Hand the phone to the customer. Review the order reference, load number, product, load quantity, customer and jobsite.
4. Enter the receiver's full name. The receiver draws with a finger, can clear/retry and confirms receipt and acceptance, including visibility in the private tracking link.
5. Tap Save signed receipt. Wait for Received & signed before leaving the screen.
6. The driver then uses COMPLETE DELIVERY. GPS site departure remains a separate event.

An unsigned completed load remains Customer signature pending. The five most recent completed loads are accessible below the active delivery for missed-signature recovery; older loads can be opened from their order by the assigned driver. A signature is offered, not fabricated or inferred when the customer is unavailable. Partial orders keep a separate receipt for each load.

If saving fails, the drawing stays in the open editor and can be retried. It is not stored in the offline outbox; closing or reloading loses an unsaved drawing. After a successful server write, a lost response can be retried with the same request identifier. GPS capture, completion and app updates are paused while the receipt editor is open.

## What the dispatcher and customer see
The order detail and private customer tracking show Received & signed, receiver name, Alberta date/time and the drawn signature. Expand Signed delivery details for the immutable load snapshot. The tracking timeline adds Customer received & signed independently of Delivery completed and Left jobsite. Only this signed load is accepted. Existing manager publication rules for photos, videos, audio and notes remain in place.

## Integrity and access
- External receiver identity is stated by name and recorded by the authenticated assigned driver; it is not represented as the customer's authenticated account.
- Database checks require an active authorized assigned driver, arrived/completed load, nonblank bounded drawing, receiver name, consent and the exact reviewed snapshot hash.
- One receipt per load, immutable to app users. Exact retries return the same receipt; changed payloads and attempts to overwrite are rejected.
- Stored snapshot retains the reference and delivery details even if the current Amsio reference changes later.
- RLS and SELECT-only grants restrict staff reads to the existing delivery audience; anonymous users cannot read the table or call receipt APIs.
- The existing service-only tracking RPC exposes curated receipt evidence through its expiring bearer link; it does not expose internal user IDs, retry identifiers, private messages or coordinates.
- Receipt creation and its customer-visible timeline entry/dispatcher notifications commit together. No stock, order quantity, driver completion, GPS exit or maintenance records are changed.

## Validation
Component tests exercise the actual finger pointer handlers, interruption, consent, snapshot/driver binding, rendering and save payload. Rollback SQL exercises real dispatch flow, permissions, stale hashes, retries, immutable evidence, private tracking, partial orders and separation from completion. Existing production/geofence tests and TypeScript/Vite build are required. Physical phone testing remains a pilot check.
