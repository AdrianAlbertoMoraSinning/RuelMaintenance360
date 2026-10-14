import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Asset = { id:string; business_unit_id:string; asset_code:string; name:string; asset_category:string }
type Plan = {
  id:string; asset_id:string; plan_type:string; title:string; description:string|null; trigger_basis:string;
  interval_days:number|null; interval_km:number|null; interval_hours:number|null; next_due_date:string|null;
  next_due_km:number|null; next_due_hours:number|null; active:boolean
}

type Props = { units:BusinessUnit[]; role:string }

const blank = { asset_id:'', plan_type:'preventive', title:'', description:'', trigger_basis:'calendar', interval_days:'', interval_km:'', interval_hours:'', next_due_date:'', next_due_km:'', next_due_hours:'' }

export default function MaintenancePlansSection({ units, role }:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [plans,setPlans]=useState<Plan[]>([])
  const [loading,setLoading]=useState(true)
  const [showForm,setShowForm]=useState(false)
  const [form,setForm]=useState(blank)
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')
  const [unitFilter,setUnitFilter]=useState('all')
  const [query,setQuery]=useState('')

  const canEdit=['super_admin','corporate_manager','unit_supervisor','technician'].includes(role)

  async function load(){
    setLoading(true)
    const [{data:a},{data:p}] = await Promise.all([
      supabase.from('assets').select('id,business_unit_id,asset_code,name,asset_category').order('asset_code'),
      supabase.from('maintenance_plans').select('id,asset_id,plan_type,title,description,trigger_basis,interval_days,interval_km,interval_hours,next_due_date,next_due_km,next_due_hours,active').order('title')
    ])
    setAssets((a||[]) as Asset[]); setPlans((p||[]) as Plan[]); setLoading(false)
  }
  useEffect(()=>{load()},[])

  function assetFor(id:string){return assets.find(a=>a.id===id)}
  function unitName(id:string){return units.find(u=>u.id===id)?.name||'Assigned unit'}

  const visible=useMemo(()=>{
    const q=query.trim().toLowerCase()
    return plans.filter(p=>{
      const a=assetFor(p.asset_id)
      const unitOk=unitFilter==='all'||a?.business_unit_id===unitFilter
      const text=`${p.title} ${p.plan_type} ${p.trigger_basis} ${a?.asset_code||''} ${a?.name||''}`.toLowerCase()
      return unitOk&&(!q||text.includes(q))
    })
  },[plans,assets,unitFilter,query])

  async function save(e:FormEvent){
    e.preventDefault(); setSaving(true); setMessage('')
    const payload={
      asset_id:form.asset_id, plan_type:form.plan_type, title:form.title.trim(), description:form.description.trim()||null,
      trigger_basis:form.trigger_basis, interval_days:form.interval_days?Number(form.interval_days):null,
      interval_km:form.interval_km?Number(form.interval_km):null, interval_hours:form.interval_hours?Number(form.interval_hours):null,
      next_due_date:form.next_due_date||null, next_due_km:form.next_due_km?Number(form.next_due_km):null,
      next_due_hours:form.next_due_hours?Number(form.next_due_hours):null
    }
    const {error}=await supabase.from('maintenance_plans').insert(payload)
    if(error)setMessage(error.message)
    else {setMessage('Maintenance plan created successfully.'); setForm(blank); setShowForm(false); await load()}
    setSaving(false)
  }

  const today=new Date().toISOString().slice(0,10)
  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Reliability Program</span><h1>Maintenance Plans</h1><p className="muted">Calendar, hour-meter and kilometre based maintenance with clear next-due points for every asset.</p></div>{canEdit&&<button className="primary-button action-button" onClick={()=>setShowForm(!showForm)}>+ New plan</button>}</div>
    {message&&<div className={message.includes('successfully')?'success-box':'error-box'}>{message}</div>}
    {showForm&&<form className="data-form" onSubmit={save}><div className="form-title"><div><span className="eyebrow">Maintenance strategy</span><h2>Create plan</h2></div><button type="button" className="icon-button" onClick={()=>setShowForm(false)}>×</button></div>
      <div className="form-grid">
        <label>Asset<select required value={form.asset_id} onChange={e=>setForm({...form,asset_id:e.target.value})}><option value="">Select asset</option>{assets.map(a=><option key={a.id} value={a.id}>{a.asset_code} — {a.name}</option>)}</select></label>
        <label>Plan type<select value={form.plan_type} onChange={e=>setForm({...form,plan_type:e.target.value})}><option value="preventive">Preventive</option><option value="predictive">Predictive / condition</option><option value="inspection">Inspection</option><option value="corrective">Corrective standard</option></select></label>
        <label>Trigger basis<select value={form.trigger_basis} onChange={e=>setForm({...form,trigger_basis:e.target.value})}><option value="calendar">Calendar</option><option value="hours">Operating hours</option><option value="km">Kilometres</option><option value="condition">Condition</option><option value="mixed">Mixed</option></select></label>
        <label className="span-2">Plan title<input required value={form.title} onChange={e=>setForm({...form,title:e.target.value})} placeholder="e.g. 250 h engine service" /></label>
        <label>Interval days<input type="number" min="1" value={form.interval_days} onChange={e=>setForm({...form,interval_days:e.target.value})}/></label>
        <label>Interval hours<input type="number" min="0" step="0.1" value={form.interval_hours} onChange={e=>setForm({...form,interval_hours:e.target.value})}/></label>
        <label>Interval km<input type="number" min="0" step="1" value={form.interval_km} onChange={e=>setForm({...form,interval_km:e.target.value})}/></label>
        <label>Next due date<input type="date" value={form.next_due_date} onChange={e=>setForm({...form,next_due_date:e.target.value})}/></label>
        <label>Next due hours<input type="number" min="0" step="0.1" value={form.next_due_hours} onChange={e=>setForm({...form,next_due_hours:e.target.value})}/></label>
        <label>Next due km<input type="number" min="0" step="1" value={form.next_due_km} onChange={e=>setForm({...form,next_due_km:e.target.value})}/></label>
        <label className="span-2">Procedure / scope<textarea rows={4} value={form.description} onChange={e=>setForm({...form,description:e.target.value})} placeholder="Describe checks, service scope and reference manual section."/></label>
      </div><div className="form-actions"><button type="button" className="secondary-outline" onClick={()=>setShowForm(false)}>Cancel</button><button className="primary-button action-button" disabled={saving}>{saving?'Saving…':'Create plan'}</button></div>
    </form>}
    <div className="toolbar"><input className="search-input" placeholder="Search plan or asset…" value={query} onChange={e=>setQuery(e.target.value)}/><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select><span className="count-chip">{visible.length} plans</span></div>
    {loading?<div className="loading-panel">Loading maintenance plans…</div>:visible.length===0?<div className="empty-table">No maintenance plans recorded for this filter.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>Plan</th><th>Asset</th><th>Business unit</th><th>Type</th><th>Trigger</th><th>Next due</th><th>Status</th></tr></thead><tbody>{visible.map(p=>{const a=assetFor(p.asset_id); const overdue=!!p.next_due_date&&p.next_due_date<today; return <tr key={p.id}><td><strong>{p.title}</strong><small>{p.description||'Scope pending'}</small></td><td><strong>{a?.asset_code||'—'}</strong><small>{a?.name||''}</small></td><td>{a?unitName(a.business_unit_id):'—'}</td><td><span className="status-pill active">{p.plan_type}</span></td><td>{p.trigger_basis}<small>{[p.interval_days&&`${p.interval_days} d`,p.interval_hours&&`${p.interval_hours} h`,p.interval_km&&`${p.interval_km} km`].filter(Boolean).join(' · ')||'Condition based'}</small></td><td>{p.next_due_date||'—'}<small>{[p.next_due_hours&&`${p.next_due_hours} h`,p.next_due_km&&`${p.next_due_km} km`].filter(Boolean).join(' · ')}</small></td><td><span className={`priority-pill ${overdue?'critical':'low'}`}>{overdue?'Overdue':'Active'}</span></td></tr>})}</tbody></table></div>}
  </div>
}
