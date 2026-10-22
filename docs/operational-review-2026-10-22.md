# Operational review — 22 October 2026

Scope: production deployment, database readiness, Field Observations and My To-do after the first day of plant use, with additional checks for asset photos, financial visibility, work-order approvals and maintenance sources. Findings below reflect the database at approximately 13:40 UTC (07:40 Alberta).

## Correction applied

Production logs repeatedly reported `permission denied for function can_access_safety_case`. Reproducing a Safety Case SELECT as Don's authenticated role failed even with no Safety Case rows. Both existing Safety RLS predicates lacked EXECUTE for authenticated users. This affects the Safety reads used by Field Observations and Safety screens; it was not the cause of task assignment authorization.

Migration `20261022134007_safety_rls_predicate_permissions.sql` restores authenticated EXECUTE on `private.can_access_safety_case(uuid)` and `private.can_manage_safety_case(uuid)`. The predicate bodies, row policies, table write grants and approval thresholds are unchanged. Anonymous execution remains denied. The existing identity and responsibility predicates determine visible records.

The new rollback regression exercises actual authenticated table RLS: DJ submits and reads a Safety Case; Don can review it; Guy performs OHS review and closure and reads the retained snapshot; an unrelated operator cannot read the case/snapshot or manage it. This passed before deployment with temporary grants and again after applying the migration. Other policy-dependent private functions were checked for the same missing grant; no additional missing functions were found.

## Verification

- Production frontend matches the successfully built main deployment `1d31bcdefb884e7dd6d147312db3b879aee95746`; this review changes database permissions and adds a regression, without changing the frontend.
- `npm run build` passed; all 85 JavaScript/TypeScript tests passed. The existing bundle-size warning remains a future mobile performance improvement, not a build failure.
- Twelve existing SQL regression suites passed: Don assignment, hierarchical tasks, task conversation, maintenance task sources, observation conversation, evidence permissions, supervisor acceptance for AI, operator-to-CEO/Safety workflow, unit activity access, unit thresholds, financial visibility and asset-photo access. The new Safety policy regression also passed. Test records and notifications were rolled back.
- Don can assign both independent and linked tasks to DJ. Authorization remains restricted to eligible active recipients. Tyrel's onboarding remains pending; he has no active linked user account yet.
- Chats retain authors and timestamps, support bilateral replies, resist duplicate retries and do not approve work or add unaccepted observations to AI memory.
- Only the assigned reviewer can accept an observation into AI memory; edits, rejection and requests for information invalidate stale acceptance.
- Photo metadata and Storage permission tests passed. No existing observation evidence metadata points to a missing Storage object. Phone capture, dictation, installation and the final screen experience still require real device acceptance.
- The post-fix security advisor shows no new finding. Existing items: two private cleanup archive tables intentionally have RLS with no client policies; compromised-password protection is disabled in Auth. See https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

## Peace River Concrete Plant snapshot

| Record | State |
| --- | --- |
| Assets | 40 registered |
| Active maintenance plans | 0 — scheduled PM tasks will require real plans and due settings |
| OBS-001042 | Submitted; Adrian Mora → Guy Munden; one stored photo |
| OBS-001043 | Submitted; Adrian Mora → Guy Munden; one stored photo and four chat messages |
| TASK-27 | Guy → Don; pending, 0%; due 28 October, 17:00 Alberta |
| TASK-28 | Guy → Adrian; in progress, 80%; due 22 October, 17:00 Alberta |
| Approval threshold | CAD 500 in every business unit |

## Outstanding operational configuration and findings

1. Create and commission maintenance plans for the plant assets. None are active in this unit; current real tasks are manual assignments.
2. Assign a custodian to the plant's Main Parts Storage position and its warehouse. The readiness audit reports one active warehouse and one active position without a responsible person. No custodian was guessed or assigned during this review.
3. Review WO-000001 in Heavy Equipment (title `;lda;lskdas`): status `waiting_vendor`, execution approval `draft`. It is the audit's one critical work-order finding and is outside Peace River Concrete Plant. It appears to be an early test record, but its status/approval was not changed or retrospectively approved.
4. Complete equipment identification: the audit reports 40 active/standby assets without serial numbers across the authorized corporate scope. Missing serials must be obtained from plates or documents, not invented.
5. Scheduled reporting's latest retained bridge status is `setup_pending`: secure scheduler credential configuration is still outstanding. Do not describe scheduled delivery as operational.
6. Automatic invitation delivery was previously unconfigured; manual invitation generation is available. This review did not send invitations or exercise the email provider. Confirm sender/provider configuration before relying on automatic email.
7. Complete Tyrel's account setup when contact details and the onboarding instruction are available.
8. Confirm the updated Assign task form on Don's actual phone and perform DJ's first real end-to-end task and observation with dictation/photo, supervisor reply, progress and review.

Database integrity checks cannot certify successful microphone access, camera use, home-screen installation or tapping on a particular phone. Those acceptance checks remain distinct from the passing role simulations. No existing operational records, approvals or unrelated mock data were deleted or changed in this review.
