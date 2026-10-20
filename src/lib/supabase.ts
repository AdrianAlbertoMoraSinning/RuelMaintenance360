import {readForwardedInvitation} from './phoneOnboarding'
import { createClient } from '@supabase/supabase-js'
import { readAuthReturn } from './authFlow'

// GoTrue consumes the URL fragment during initialization. Capture intent first.
export const initialAuthReturn = readAuthReturn(window.location.search, window.location.hash)
export const initialOperatorInvite = readForwardedInvitation(window.location.search,window.location.hash)
if(new URLSearchParams(window.location.search).get('setup')==='forwarded'&&window.location.hash)window.history.replaceState(null,'',window.location.pathname+window.location.search)


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
