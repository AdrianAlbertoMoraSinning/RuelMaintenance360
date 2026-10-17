# Reporting hierarchy and execution authorization

Commissioning change: 2026-10-17.

Personnel Category describes the organizational position. System Role controls application permissions. `corporate_manager_id` is retained for compatibility but represents the **direct Reporting Manager**, which may now be an active Supervisor, Corporate Manager, or Super Admin.

## Routing

An Operator or Technician can report to a Supervisor. Field Observations keep their existing direct-manager routing; Safety also routes to Primary OHS. A WO execution-approval request follows that employee's reporting line through Supervisors to the first active Corporate Manager or Super Admin. A missing, inactive, cyclic, or invalid hierarchy blocks the request. The separate corporate cost threshold and approval stage are preserved.

Being a Reporting Manager does not grant execution approval authority. Controlled completion permissions remain independently configured through the existing authorization model.

The database rejects self-reporting and cycles. A Supervisor with active direct reports cannot be deactivated or demoted to a non-supervisory role until those reports are reassigned. The last-active-Super-Admin protection remains in place.

The resolver is internal to the private schema, checks authentication, and is not executable directly by `anon` or `authenticated`. The existing public authorization RPC is retained.

## Application and administration service

Administration uses the label **Reporting Manager**, includes Supervisors in eligible reporting-manager choices, and explains the separate authorization route. Production personnel are shown by default; the MOC / training group remains available. Production onboarding excludes MOC managers from its choices. This is a presentation safeguard; it is not database isolation of training data.

`admin-user-security` uses the same eligible reporting-manager roles as the database. Its JWT verification and administrator-only caller checks remain enabled. The Supabase client dependency is pinned to 2.58.0.

Only Guy Munden, Marcel Ruel, Sylvain Ruel, and Adrian Mora are real users at this stage. No users or invitations were created by this change. Real reporting lines, business-unit assignments and the unset corporate threshold were preserved.

## Validation

- `tests/reporting_hierarchy.sql`: transactional MOC-only fixtures, rolled back after checking Supervisor reporting, corporate-manager escalation, denial of Supervisor execution approval, retained threshold escalation, self/cycle/inactive-manager rejection, and manager deactivation/demotion safeguards.
- `npm run build`: regression guard, TypeScript and production bundle.
- Supabase security advisor: no new database warnings; the existing Leaked Password Protection item remains for the planned security commissioning stage.

The migration file is a delta for the existing commissioning database, not a standalone database bootstrap. Existing foundational migrations must precede it.

## Remaining commissioning order

1. Finish the cost-visibility separation for Operators/Technicians and formal approval/closure matrix. Configure the corporate threshold only after the amount is supplied.
2. Confirm the eight Business Units, real responsibilities/access, and Peerless spelling.
3. Review the Asset Master, then Observations/OHS, WO workflows, PM, inventory, inspections, dashboards, notifications, reports and production security.
4. Keep MOC cleanup controlled and defer Equipment Diagnostics until equipment identity and documentation are available. Retain historical WO #1 until its disposition is agreed.

Email follow-up remains separate: the corporate Invite template and production Site URL are saved. Sylvain's resend is pending the built-in mail quota; Marcel's earlier link must be checked/reissued as needed after the Site URL correction. Custom SMTP is not configured.
