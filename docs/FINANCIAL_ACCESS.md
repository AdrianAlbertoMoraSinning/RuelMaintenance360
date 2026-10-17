# Financial read access

Commissioning decision: Super Admin and Corporate Manager retain their existing scope. Unit Supervisors see costs only for their authorized Business Units. Operators, Technicians, Viewers, IT and dedicated OHS roles receive operational records with monetary fields set to SQL NULL. Shared parts/vendor catalog prices are available to corporate roles and Supervisors with unit access.

`*_visible` security-invoker views preserve the base tables' RLS. Their private, authenticated financial lookup returns only explicitly listed monetary columns and independently validates role and owning unit. The corporate approval threshold snapshot is returned only to Super Admins.

The cutover revokes monetary SELECT privileges on the seven base tables from authenticated, anon and PUBLIC. Safe base columns remain readable under RLS. Direct monetary reads, filters and aggregates against base tables are denied; applications must use the masked views. Service-role operations retain their existing privileges.

Operational edits omit hidden monetary fields. Parts issue, return, receipts, transfers, counts and PM generation resolve actual prices inside guarded private implementations; their public wrappers return identifiers or operational results only. A masked price must never be converted to zero and saved over a real price. The UI and CSV/PDF exports omit financial values for roles without cost access. Manual email reports use the caller's masked view and retain their separate distribution/scope checks.

## Deployment order

1. Apply additive financial views and server-priced movement RPC.
2. Deploy the client and `send-report-email` function; verify production contains the masked read routes.
3. Apply `financial_column_cutover` and rerun the transactional tests.
4. Refresh open application tabs to load the new client. An older client requesting raw monetary columns will receive a permission error after cutover.

These are delta migrations for the existing commissioned project, not a full database bootstrap. File timestamp order is not a substitute for the coordinated production rollout above.

## Validation

Run `tests/financial_visibility.sql` inside BEGIN/ROLLBACK after the migration. It uses disposable fixtures and temporary access entries on existing MOC users. It covers own/foreign-unit Supervisors, Operator and Technician masking, raw-column denial, threshold confidentiality, operational edits, server-priced movements, parts issue/return, transfers, stock counts, PO receipts, request receipts and PM estimate preservation. No fixture, grant, plan or stock movement survives rollback. A PM generator query was qualified to disambiguate its output variable from the part-template column; intervals and automation settings are unchanged.

Cost visibility does not grant spending approval, execution approval or closure authority. UI walkthrough on a real phone and real-user role testing remain part of commissioning.
