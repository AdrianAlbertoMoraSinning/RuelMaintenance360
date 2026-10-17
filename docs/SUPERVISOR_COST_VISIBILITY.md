# Supervisor cost visibility

Commissioning decision, 2026-10-17: Supervisors may view maintenance costs in their authorized Business Units. Viewing costs does not itself authorize expenditure, execution, or closure.

## Enforced scope

`supervisor_work_order_unit_scope` is a restrictive SELECT policy on `public.work_orders`. For an authenticated `unit_supervisor`, the work order's Business Unit must pass `private.can_access_unit`. The requester/assignee exceptions in the existing permissive read policy cannot grant cross-unit access. All existing read policies continue to apply.

The policy also scopes security-invoker reporting views that read work orders. Inventory transactions, purchase orders/lines, work-order vendor costs, and maintenance plans already check their owning Business Unit through their existing policies. Parts and vendors remain shared corporate catalogs; their standard prices/rates are not a unit's spending history.

Existing approval checks are unchanged: `can_approve` remains separate, and the confidential corporate threshold remains restricted to Super Admins. Corporate roles retain their existing scope.

## Applied database migration

Supabase migration name: `supervisor_work_order_cost_unit_scope`.

```sql
create policy supervisor_work_order_unit_scope
on public.work_orders
as restrictive
for select
to authenticated
using (
  (select private.current_role()) is distinct from 'unit_supervisor'::public.app_role
  or (select private.can_access_unit(work_orders.business_unit_id))
);
```

## Validation

The transaction in `tests/supervisor_cost_scope.sql` was run against the commissioning database and rolled back. It verifies:

- own-unit estimated costs are readable by a Supervisor;
- a foreign-unit WO remains hidden even when the Supervisor is requester and assignee;
- the corporate approval threshold is hidden;
- a Supervisor without approval authority does not gain it;
- Super Admin visibility is preserved.

Only Guy Munden, Marcel Ruel, Sylvain Ruel, and Adrian Mora are real users at this stage. MOC profiles provide the QA fixtures; no real Supervisor account was created.

## Remaining commissioning work

This change does **not** conceal monetary fields from Operators or Technicians. Those fields currently share records with operational data. A separate API/data-model change and all relevant readers/exports must be reviewed before that restriction can be claimed. Do not certify the full cost-visibility matrix as complete.

Reporting Manager and spending approval authority also remain separate decisions; adding a reporting line must not silently grant approval authority.
