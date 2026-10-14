import { FormEvent, useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './lib/supabase'
import AssetsSection, { type BusinessUnit } from './modules/AssetsSection'
import WorkOrdersSection from './modules/WorkOrdersSection'

type Profile = {
  id: string
  email: string | null
  phone: string | null
  full_name: string | null
  role: string
}

type SectionManual = {
  section_key: string
  title: string
  purpose: string
  quick_start: string
  workflow: string[]
  warnings: string | null
}

type DashboardMetrics = {
  assets: number
  openOrders: number
  pmDue: number
  criticalAlerts: number
  downtime: number
  unitAssetCounts: Record<string, number>
  unitOpenCounts: Record<string, number>
}

const sections = [
  ['dashboard', 'Dashboard', '01'],
  ['business_units', 'Business Units', '02'],
  ['assets', 'Assets', '03'],
  ['maintenance', 'Maintenance Plans', '04'],
  ['work_orders', 'Work Orders', '05'],
  ['inspections', 'Inspections', '06'],
  ['vendors', 'Vendors', '07'],
  ['inventory', 'Parts & Inventory', '08'],
  ['documents', 'Documents', '09'],
  ['analytics', 'Analytics & KPIs', '10'],
  ['ai_assistant', 'Technical Assistant', 'AI'],
  ['admin', 'Administration', 'AD'],
] as const

function Login() {
  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function submit(event: FormEvent) {
    event.preventDefault()
    setLoading(true)
    setError('')
    const credentials = identifier.includes('@')
      ? { email: identifier.trim(), password }
      : { phone: identifier.trim(), password }
    const { error: authError } = await supabase.auth.signInWithPassword(credentials)
    if (authError) setError(authError.message)
    setLoading(false)
  }

  return (
    <main className="login-page">
      <div className="industrial-backdrop" aria-hidden="true">
        <div className="plant plant-left">ASPHALT</div>
        <div className="fleet">HEAVY FLEET · MIXERS · PUMPS</div>
        <div className="plant plant-right">CONCRETE</div>
      </div>
      <section className="login-card">
        <Brand label="MAINTENANCE 360" />
        <p className="eyebrow">Enterprise Asset & Maintenance Management</p>
        <h1>Operations Control</h1>
        <p className="muted">Sign in with your assigned email address or mobile number.</p>
        <form onSubmit={submit}>
          <label>Email or mobile number<input value={identifier} onChange={(e) => setIdentifier(e.target.value)} autoComplete="username" required /></label>
          <label>Password<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required /></label>
          {error && <div className="error-box">{error}</div>}
          <button className="primary-button" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
        </form>
        <div className="login-footer">Authorized RUEL personnel only · Access is logged</div>
      </section>
    </main>
  )
}

function Brand({ label }: { label: string }) {
  return <div className="brand" aria-label={`RUEL ${label}`}><span className="brand-ruel">RUEL</span><span className="brand-label">{label}</span></div>
}

function ManualDrawer({ manual, onClose }: { manual: SectionManual | null; onClose: () => void }) {
  if (!manual) return null
  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <aside className="manual-drawer" onClick={(e) => e.stopPropagation()}>
        <div className="manual-head"><div><span className="eyebrow">Context Help</span><h2>{manual.title}</h2></div><button className="icon-button" onClick={onClose} aria-label="Close manual">×</button></div>
        <div className="manual-block"><h3>Purpose</h3><p>{manual.purpose}</p></div>
        <div className="manual-block"><h3>Quick start</h3><p>{manual.quick_start}</p></div>
        <div className="manual-block"><h3>Recommended workflow</h3><ol>{(manual.workflow || []).map((step, i) => <li key={i}>{step}</li>)}</ol></div>
        {manual.warnings && <div className="warning-box"><strong>Important</strong><p>{manual.warnings}</p></div>}
        <p className="manual-note">This manual is contextual to the current screen and your assigned access level.</p>
      </aside>
    </div>
  )
}

function Dashboard({ units, openSection }: { units: BusinessUnit[]; openSection:(key:string)=>void }) {
  const [metrics,setMetrics] = useState<DashboardMetrics>({assets:0,openOrders:0,pmDue:0,criticalAlerts:0,downtime:0,unitAssetCounts:{},unitOpenCounts:{}})
  const [loading,setLoading] = useState(true)

  useEffect(()=>{
    async function load(){
      const now = new Date().toISOString().slice(0,10)
      const [{data:assets},{data:orders},{data:plans},{data:failures}] = await Promise.all([
        supabase.from('assets').select('id,business_unit_id'),
        supabase.from('work_orders').select('business_unit_id,status,downtime_hours,priority'),
        supabase.from('maintenance_plans').select('next_due_date,active').eq('active',true).lte('next_due_date',now),
        supabase.from('failure_events').select('severity,resolved_at').eq('severity','critical').is('resolved_at',null)
      ])
      const unitAssetCounts:Record<string,number> = {}
      const unitOpenCounts:Record<string,number> = {}
      ;(assets||[]).forEach((a:any)=>unitAssetCounts[a.business_unit_id]=(unitAssetCounts[a.business_unit_id]||0)+1)
      const activeOrders=(orders||[]).filter((o:any)=>!['completed','cancelled'].includes(o.status))
      activeOrders.forEach((o:any)=>unitOpenCounts[o.business_unit_id]=(unitOpenCounts[o.business_unit_id]||0)+1)
      setMetrics({
        assets:(assets||[]).length,
        openOrders:activeOrders.length,
        pmDue:(plans||[]).length,
        criticalAlerts:(failures||[]).length,
        downtime:(orders||[]).reduce((sum:number,o:any)=>sum+Number(o.downtime_hours||0),0),
        unitAssetCounts,unitOpenCounts
      })
      setLoading(false)
    }
    load()
  },[])

  const stats = [
    ['Registered Assets', loading?'—':String(metrics.assets), 'Visible within your authorized scope'],
    ['Open Work Orders', loading?'—':String(metrics.openOrders), 'Active corrective / planned work'],
    ['PM Due', loading?'—':String(metrics.pmDue), 'Due or overdue preventive plans'],
    ['Critical Alerts', loading?'—':String(metrics.criticalAlerts), 'Unresolved critical failures'],
  ]

  return <>
    <div className="hero-row"><div><span className="eyebrow">Corporate Overview</span><h1>Maintenance Command Center</h1><p className="muted">One operational view across RUEL business units, assets and maintenance activity.</p></div><div className="status-chip"><span className="status-dot" /> System online</div></div>
    <div className="stat-grid">{stats.map(([title,value,detail])=><article className="stat-card" key={title}><span>{title}</span><strong>{value}</strong><small>{detail}</small></article>)}</div>
    <div className="summary-strip"><span><b>{metrics.downtime.toFixed(1)} h</b> Recorded downtime</span><span>Live figures are based on authorized database records.</span></div>
    <div className="section-heading"><div><span className="eyebrow">Business Units</span><h2>Operations</h2></div><span className="count-chip">{units.length} configured</span></div>
    <div className="unit-grid">{units.map(unit=><article className="unit-card" key={unit.id}>
      <div className="unit-top"><Brand label={unit.brand_label} /><span className="unit-code">{unit.code}</span></div>
      <h3>{unit.name}</h3><p>{unit.address||'Location details pending'}</p>
      <div className="unit-metrics"><span><b>{metrics.unitAssetCounts[unit.id]||0}</b> Assets</span><span><b>{metrics.unitOpenCounts[unit.id]||0}</b> Open</span><span><b>—</b> Due</span></div>
      <button className="secondary-button" onClick={()=>openSection('assets')}>Open assets →</button>
    </article>)}</div>
  </>
}

function BusinessUnitsSection({units}:{units:BusinessUnit[]}){
  return <div><div className="hero-row compact-hero"><div><span className="eyebrow">Organization Structure</span><h1>Business Units</h1><p className="muted">Locations and operational areas that own assets, supervisors, maintenance plans and performance.</p></div></div>
    <div className="unit-grid">{units.map(u=><article className="unit-card" key={u.id}><div className="unit-top"><Brand label={u.brand_label}/><span className="unit-code">{u.code}</span></div><h3>{u.name}</h3><p>{u.address||'Address / GPS pending'}</p><div className="detail-list"><span>Type <b>{u.unit_type}</b></span><span>Brand <b>RUEL {u.brand_label}</b></span></div></article>)}</div>
  </div>
}

function PlaceholderSection({ title, section }: { title: string; section: string }) {
  const descriptions: Record<string, string> = {
    maintenance: 'Configure corrective, preventive and predictive maintenance strategies by asset.', inspections: 'Mobile-first field inspections, checklists, meter readings, observations and evidence.', vendors: 'Service-provider directory, rates, contacts, history, cost and performance.', inventory: 'Parts, consumables, stock, critical spares and work-order consumption.', documents: 'OEM manuals, certificates, procedures, drawings and controlled technical documents.', analytics: 'Availability, MTBF, MTTR, compliance, downtime, cost, backlog and trend analysis.', ai_assistant: 'Asset-aware technical assistant grounded in approved manuals and maintenance history.', admin: 'Users, roles, access assignments, configuration and audit controls.'
  }
  return <div className="empty-state"><div className="empty-number">{sections.find(([key])=>key===section)?.[2]}</div><span className="eyebrow">Module Foundation Ready</span><h1>{title}</h1><p>{descriptions[section]}</p><div className="phase-banner">Foundation active · Database, role security and Operations Manual are already in place for this module.</div></div>
}

function AppShell({ session }: { session: Session }) {
  const [profile, setProfile] = useState<Profile | null>(null)
  const [units, setUnits] = useState<BusinessUnit[]>([])
  const [section, setSection] = useState('dashboard')
  const [manuals, setManuals] = useState<Record<string, SectionManual>>({})
  const [manualOpen, setManualOpen] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)

  useEffect(() => {
    async function load() {
      const [{ data: profileData }, { data: unitData }, { data: manualData }] = await Promise.all([
        supabase.from('profiles').select('id,email,phone,full_name,role').eq('id', session.user.id).single(),
        supabase.from('business_units').select('id,code,name,unit_type,brand_label,address').order('name'),
        supabase.from('section_manuals').select('section_key,title,purpose,quick_start,workflow,warnings').eq('active', true),
      ])
      if (profileData) setProfile(profileData as Profile)
      if (unitData) setUnits(unitData as BusinessUnit[])
      if (manualData) setManuals(Object.fromEntries((manualData as SectionManual[]).map((m) => [m.section_key, m])))
    }
    load()
  }, [session.user.id])

  const activeTitle = useMemo(() => sections.find(([key]) => key === section)?.[1] || 'Dashboard', [section])
  async function signOut() { await supabase.auth.signOut() }
  function navigate(key:string){setSection(key);setMenuOpen(false);setManualOpen(false)}

  function renderSection(){
    if(section==='dashboard') return <Dashboard units={units} openSection={navigate}/>
    if(section==='business_units') return <BusinessUnitsSection units={units}/>
    if(section==='assets') return <AssetsSection units={units} userId={session.user.id} role={profile?.role||'viewer'}/>
    if(section==='work_orders') return <WorkOrdersSection units={units} userId={session.user.id} role={profile?.role||'viewer'}/>
    return <PlaceholderSection title={activeTitle} section={section}/>
  }

  return <div className="app-shell">
    <aside className={`sidebar ${menuOpen ? 'open' : ''}`}><div className="sidebar-brand"><Brand label="MAINTENANCE 360" /></div><nav>{sections.map(([key,label,number])=><button key={key} className={section===key?'active':''} onClick={()=>navigate(key)}><span className="nav-number">{number}</span><span>{label}</span></button>)}</nav><div className="sidebar-user"><div className="avatar">{(profile?.full_name||session.user.email||'U').slice(0,1).toUpperCase()}</div><div><strong>{profile?.full_name||'RUEL User'}</strong><small>{profile?.role?.replaceAll('_',' ')||'loading…'}</small></div></div></aside>
    <main className="workspace"><header className="topbar"><button className="mobile-menu" onClick={()=>setMenuOpen(!menuOpen)}>☰</button><div><span className="topbar-path">RUEL / {activeTitle}</span></div><div className="topbar-actions"><button className="manual-button" onClick={()=>setManualOpen(true)}>▣ Operations Manual</button><button className="signout-button" onClick={signOut}>Sign out</button></div></header><section className="content">{renderSection()}</section></main>
    <ManualDrawer manual={manualOpen ? (manuals[section]||null):null} onClose={()=>setManualOpen(false)}/>
  </div>
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(false)
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setReady(true) })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => { setSession(nextSession); setReady(true) })
    return () => listener.subscription.unsubscribe()
  }, [])
  if (!ready) return <div className="boot-screen"><Brand label="MAINTENANCE 360" /><span>Loading secure workspace…</span></div>
  return session ? <AppShell session={session} /> : <Login />
}
