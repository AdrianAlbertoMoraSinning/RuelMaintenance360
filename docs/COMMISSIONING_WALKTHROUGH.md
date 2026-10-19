# RUEL commissioning walkthrough — 2026-10-19

The commissioning exercise is intentionally conducted with MOC/training records to find failures and improve workflows before a real pilot. SMTP remains pending corporate DNS access. No invitations were sent in this exercise.

## Confirmed organization

Adrian Mora remains responsible for CONC-PR and MOBILE-PR. Guy Munden is now responsible for ASP-PEARLESS, ASP-SL, CRUSH-SL, HEAVY-EQP, SAND-PR and SHOP-PR. All eight unit approval amounts remain unset; no permanent amounts have been invented.

## Evidence completed

- `tests/reporting_hierarchy.sql` passed against the commissioning database: Supervisor reporting, corporate approver resolution, rejection of self/cyclic/inactive lines, deactivation/demotion guards and corporate escalation.
- `tests/supervisor_cost_scope.sql` passed as the authenticated database role: own-unit costs visible, cross-unit requester/assignee bypass denied, confidential threshold hidden and approval authority unchanged.
- `tests/observation_to_ceo_safety.sql` passed: Operator submits to Supervisor; repeated draft submission and repeated WO conversion are idempotent; Operator cannot convert; WO routes to Manager, then Guy as Super Admin above a temporary test threshold; CEO cannot skip the Manager. Safety routes to Supervisor and Guy, creates internal notifications, rejects Operator closure, and retains a closure report after OHS review/closure.
- These SQL fixtures were rolled back. PostgreSQL sequence numbers can advance despite rollback. The broad workflow test checks RPC authorization with role-specific JWT identities under the administrative test connection; it does not certify all RLS policies or replace browser sessions for each role.
- Live browser sign-in succeeded as Adrian. Unit performance loaded. Field capture filters equipment by the chosen unit; SEND is initially disabled, then shows a sending state and confirmation.
- Live browser created OBS-001010 on MOC-SND-001, assigned its review to Guy, and converted it into WO #77, assigned to [MOC] Casey White with a proposed estimate of CAD 1,200. Its description begins `[QA COMMISSIONING 2026-10-19]` and explicitly describes a simulation. It remains assigned/draft; execution, inventory issue and vendor commitment are locked. Requesting authorization correctly reports that the unit threshold is unconfigured.
- Found and corrected misleading WO wording that described a draft estimate as approved and declared corporate approval unnecessary before the request had evaluated the threshold. No authorization logic changed.

## Remaining test matrix

| Area | Variants to exercise |
| --- | --- |
| Personnel | Separate real/MOC users, Supervisor reporting, unit scope, Viewer/IT/OHS restrictions, approval and closure authority |
| Observations | Equipment/Safety/Process/Facility/Other, no-asset rules, QR, photos, actual phone camera, offline/reconnect, repeated SEND, more-info/respond, direct actions, rejection/no-action, duplicate conversion |
| WO authorization | Missing threshold, below/equal/above threshold, rejection/resubmission, cost/scope/assignee changes, wrong approver, separate Manager/CEO stages |
| Execution and closure | Start/wait/resume, diagnosis/action validation, labor and downtime, critical evidence, request/reject/approve closure, forbidden direct transitions |
| OHS | Immediate danger, investigation, corrective assignment/completion, open-action closure guard, regulatory disposition, report snapshots, authorized and unauthorized closure |
| PM and calendar | Each due basis, lead time, duplicate prevention, assignment, completion roll-forward, backlog and calendar consistency; all current 24 automatic plans are MOC |
| Inventory/procurement | Warehouses/positions, receipt/adjustment, reservation/shortage, requests/PO/receipt, issue/return, negative stock, vendor commitments and cost scope |
| Inspections | Published checklist versions, pre-start/daily/safety/post-repair, failed result escalation, evidence and historical version retention |
| Analytics/reports | Drilldowns match sources, scope/role visibility, cost totals, exports, report scheduler and real delivery after mail configuration |
| Notifications | Correct recipient and urgency, deduplication, read/unread, action completion, no irrelevant broad fan-out |
| Security/mobile | Per-role RLS, leaked-password protection, chosen MFA policy, desktop/mobile permissions, loading/errors, accessibility, deployment |

## Cleanup and pilot

Keep test movements until their scenarios and fixes are verified. Before cleanup, identify the exact records and dependent rows, distinguish test data from real configuration/equipment, and preserve an agreed baseline/evidence. Remove only the identified test movements in dependency order; do not erase real personnel, unit responsibilities, approved permissions, asset identities or reusable controlled templates as part of a blanket reset. Identify legacy WO #1 and the non-MOC asset MX 003 separately. Confirm counters, balances, open cases, approvals, notifications and PM next-due values after cleanup, then run a small real pilot from intake through closure.
