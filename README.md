# RUEL Maintenance 360

Enterprise Asset & Maintenance Management System for RUEL operations.

## Current foundation

- Multi-user Supabase Auth
- Role-based access and Row Level Security
- Business units and site information
- Asset hierarchy and responsible-person assignments
- Corrective, preventive and predictive maintenance plans
- Work orders, inspections, vendors, documents and audit trail
- Contextual **Operations Manual** on every application section
- Mobile-first field workflow

## Technology

- React + TypeScript + Vite
- Supabase (Postgres, Auth, Storage)
- GitHub
- Netlify deployment

## Environment variables

Copy `.env.example` to `.env.local` for local development. Never commit service-role or database secrets.

```bash
VITE_SUPABASE_URL=https://hnqesskokhygtrjyhttb.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your_publishable_key
```

## Development

```bash
npm install
npm run dev
```

## Product rule: Operations Manual

Every major screen must expose a clearly visible **Operations Manual** action. Manuals are stored in `public.section_manuals`, versioned and role-aware. The manual explains purpose, quick start, workflow, field meanings and safety/operational warnings for the current section.

## Security

Authorization is enforced in the database with Supabase Row Level Security. Frontend visibility is convenience only and is never the security boundary.
