# Operations Manual Standard

Every RUEL Maintenance 360 screen must provide contextual help through the **Operations Manual** control in the application header.

## Required content per screen

Each manual entry must include:

1. **Purpose** — what the screen is for and what business process it controls.
2. **Audience** — which application roles should see the manual.
3. **Quick Start** — the shortest safe path to complete the primary task.
4. **Recommended Workflow** — ordered operational steps.
5. **Field Help** — definitions for fields, statuses, calculations and required evidence.
6. **Warnings** — safety, authorization, data-quality or process limitations.
7. **Version** — manuals are versioned and must remain synchronized with screen behavior.

## UX rule

The manual must be reachable without leaving the current screen. Desktop uses a side drawer. Mobile uses the same full-height contextual panel. Opening the manual must never discard unsaved field work.

## Role-awareness

A user should only receive instructions for actions the user is authorized to perform. A technician manual may explain execution and evidence capture; an operator manual may emphasize inspections/reporting; an administrator manual may describe configuration and access.

## Safety rule

The manual is operational guidance and never overrides OEM documentation, qualified-person requirements, engineering decisions, lockout/tagout, regulatory requirements, or company safety policy.

## Data model

Manual content is stored in `public.section_manuals` with:

- `section_key`
- `title`
- `purpose`
- `audience`
- `quick_start`
- `workflow`
- `field_help`
- `warnings`
- `version`
- `active`

This allows manuals to be updated without redeploying the frontend and supports later multilingual content and screen-level submanuals.
