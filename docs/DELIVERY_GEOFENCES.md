# Foreground delivery location assistance — 0.3.3

## Setup

In Production & Dispatch → Customers & setup, choose the producing business unit. A production manager can enter the plant latitude, longitude and radius under Plant departure zone. Configure each jobsite under Customers & jobsites, or directly in an open customer order. “Use my current location” is appropriate only while physically at that plant/jobsite. No coordinates are guessed or geocoded automatically.

Radii range from 75 to 1000 metres; the default input is 150 m. Coordinates are optional: manual events remain available. At Confirm produced & ready, the load stores its own plant/jobsite zone snapshots. Later catalogue edits affect subsequent ready confirmations. For an already ready load, a plant manager can choose Update delivery zones before departure; this resets detector state and writes an internal audit event. In-transit snapshots cannot be edited through this action.

## Driver

Open My deliveries, choose Enable location assistance, and grant browser location permission. Assistance runs only on this delivery screen while visible and online. It stops its GPS watcher when hidden/unmounted and resumes when visible if the driver enabled it for that screen session. It is not a background/native tracking service and cannot guarantee events while the phone is locked. Device location permission and this screen's opt-in are both required.

GPS fixes must be fresh (45 seconds maximum age), no more than 5 seconds in the future and within 50 m reported accuracy. The server independently validates them and requires three qualifying samples spanning at least 30 seconds, spaced at least 8 seconds apart, without a gap over 45 seconds. Inside detection includes the reported accuracy radius; exits add a 30 m buffer beyond the configured radius and accuracy radius.

- Plant departure requires confirmed production/readiness and an inside-plant observation before the outside readings. It uses the existing driver event state machine, including active truck/driver exclusivity.
- Site arrival requires a departed load and sustained inside-site readings.
- Site departure requires an arrived load, a previously observed inside-site location and sustained outside-site readings. It records left_site_at without changing the delivery or order completion status.
- Completion remains the driver's COMPLETE DELIVERY action. If confirmed before physical departure, site departure may still be recorded for up to 12 hours after completion while the screen remains active.

Only the current ready/active service is eligible for automatic departure/arrival. Future ready loads do not auto-depart. Pending manual offline events pause assistance; automatic samples are never queued for retrospective inference. A delayed manual departure/arrival update acknowledges an existing GPS milestone, so a stale screen or offline retry cannot duplicate it or leave the outbox stuck. Completion still requires the manual driver action. Driver updates and photos/audio/video are unchanged.

## Data and visibility

The server accepts samples only from the assigned, active, enrolled driver with existing fleet access. Zone setup requires the producing unit's production manager permission. Cross-account updates and anonymous calls are denied. Public API functions are invokers calling permission-checked private implementations; explicit grants and RLS protect new data.

No continuous route history is retained. Detector state contains the latest timestamp and counters; confirmed automatic events retain their GPS point, accuracy and source in the internal activity ledger. Dispatchers receive the normal event notifications. Customer tracking shows departure, arrival, site departure and delivery completion, but never the precise GPS coordinates or detector state. Messages and media still require dispatcher publication to become customer-visible.

## Verification

- tests/deliveryGeofence.test.mjs: bad fixes, load selection, foreground lifecycle cleanup, account binding, offline/hidden/manual-busy suppression.
- tests/production_geofences.sql: full rollback simulation of setup, snapshots, readiness, arming, dwell, nonduplicated transitions, site exit without completion, customer privacy, notifications and permission denials.
- Existing production_dispatch.sql and production_inline_catalogue.sql pass after the migration.
- Real Android/iPhone travel testing remains necessary with verified plant/site coordinates. No physical trip was performed during implementation.
