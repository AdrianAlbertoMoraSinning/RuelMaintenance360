import { createClient } from '@supabase/supabase-js'

// Netlify can override these per environment. The fallback values are the
// public project URL and publishable browser key for RUEL Maintenance 360.
// Never place the service_role key or database password in frontend code.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://hnqesskokhygtrjyhttb.supabase.co'
const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_VgOf2QDrKRHMdlnxLBb__A_4_pNpSXa'

export const supabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})
