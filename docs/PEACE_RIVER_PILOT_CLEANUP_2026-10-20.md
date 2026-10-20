# Peace River Concrete Plant production pilot cutover

On 2026-10-20 Adrian explicitly requested deletion of MOCK records for CONC-PR only, retaining all other units' training data. The scoped cleanup was previewed in a rolled-back transaction, then committed. Recovery batch: bd85a0d9-80c1-4703-800e-42e35f856d1a.

Removed 4 simulated assets, 5 work orders, 3 maintenance plans, 2 inspections, 6 inventory transactions, 1 training document plus its indexed chunk, 1 notification, 8 asset assignments, 4 simulated diagnostic identities, 2 maintenance-plan part entries and 1 vendor linkage. Removed 2 MOC unit-access rows for this plant without deleting the shared training profiles. Training registry entries for removed plant entities were also cleared.

The private, RLS-protected recovery archive contains 53 original rows, including deleted rows, training registry entries and the original location/warehouse setup. It is inaccessible to anon/authenticated clients. The plant's existing warehouse/location remain, with simulated staff responsibility cleared to unassigned. They require a real designated custodian before operational inventory use.

All non-target records in 66 public tables were fingerprinted before and after inside the transaction. Unrelated rows, including the other seven units, remained identical. Real profiles, onboarding records and invitations for Don, DJ and Tyrel were preserved, as were unit configuration and the CAD 500 approval threshold. Shared part/vendor catalogs remain for the other units' demonstrations; no global catalog was purged. Raw technical audit history is retained.

Post-commit checks: CONC-PR has zero assets, work orders, inspections, observations, maintenance plans, inventory movements, stock balances and unit training documents. Its four prior assets were expressly tagged MOC TRAINING and must not be treated as real equipment. Actual equipment and verified maintenance plans need to be registered before equipment-based pilot operations. No fabricated OEM details were promoted into production.

The operation script defaults to ROLLBACK. Commit only after reviewing the current scope and dependencies. Restore requires an administrator to replay archived rows in dependency order and resolve cyclic references; no public restore endpoint exists. Never restore over new real records without reviewing conflicts.

Separately, DJ's supervisor invitation was re-sent to Don through Gmail using multipart/alternative. Both the HTML design and plain text include the full personal link, username and manual-forwarding instructions. Saved SENT message 1a15a70071f86af8 was read back and both content parts verified. Recipient-side rendering and DJ's actual acceptance remain human checks.
