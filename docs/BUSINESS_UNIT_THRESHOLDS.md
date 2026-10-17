# Business Unit authorization thresholds

RUEL commissioning decision, 2026-10-17: one independent CAD authorization threshold per Business Unit. No amounts were supplied or inferred. The eight current units start unconfigured.

Administration lists every unit with its saved threshold and a separate input/save button. Only active Super Admins can read or change the confidential settings. Saving one row preserves unsaved inputs for other units. Zero is allowed explicitly; a blank field is not zero and cannot be saved.

`business_unit_approval_settings` has a unique row per unit, a nullable non-negative CAD amount, and the last editor/time. RLS permits Super Admin reads only. Authenticated clients cannot write the table directly; a guarded private implementation behind the public `set_business_unit_approval_threshold` wrapper validates the caller, unit, amount, precision and finite value.

Execution requests use the threshold belonging to the WO's Business Unit. Missing settings block requests for that unit with no global fallback. Manager approval remains mandatory. Estimates strictly above the threshold additionally require Super Admin approval; an equal estimate does not. A zero threshold escalates every positive estimate.

Each request records `approval_threshold_snapshot`. Changing a setting leaves prior requests intact. Submitting a new request uses the then-current value. Moving a WO between units resets authorization and clears its snapshot through the existing scope-change trigger; the next request uses the destination unit. Threshold snapshots remain hidden from every role except Super Admin.

The old global settings row is retained for history and is no longer consulted by execution requests or readiness checks. Its old setter rejects attempts with instructions to use unit settings, so stale clients cannot silently configure an unused amount. Refresh open application tabs after deployment.

System Readiness Audit counts units with an unset threshold rather than checking one global amount. The audit exposes the missing-configuration count, never the amounts.

## Verification

`tests/business_unit_thresholds.sql` runs inside BEGIN/ROLLBACK. Its amounts are disposable QA fixtures. It verifies independent units, no legacy fallback, missing/zero/exact-boundary behavior, immutable prior snapshots, resubmission, moving units, invalid values, legacy setter rejection, Super Admin-only read/write and anonymous denial. The hierarchy and supervisor-scope tests use the new configuration/read paths. Financial-access regression coverage remains applicable. No test amount or WO persists.
