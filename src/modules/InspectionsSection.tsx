import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string;asset_category:string;hour_meter:number|null;odometer_km:number|null}
type Inspection={id:string;asset_id:string;inspection_type:string;result:string;observations:string|null;meter_km:number|null;meter_hours:number|null;inspected_at:string;checklist:any[]}
type Props={units:BusinessUnit[];userId:string;role:string}

const blank={asset_id:'',inspection_type:'pre_shift',result:'pass',observations:'',meter_hours:'',meter_km:'',check1:true,check2:true,check3:true,check4:true}

export default function InspectionsSection({units,userId,role}:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [rows,setRows]=useState<Inspection[]>([])
  const [loading,setLoading]=useState(true)
  const [showForm,setShowForm]=useState(false)
  const [form,setForm]=useState(blank)
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')
  const [unitFilter,setUnitFilter]=useState('all')
  const canCreate=['super_admin','corporate_manager','unit_supervisor','technician','operator'].includes(role)

  async function load(){setLoading(true);const [{data:a},{data:i}]=await Promise.all([
    supabase.from('assets').select('id,business_unit_id,asset_code,name,asset_category,hour_meter,odometer_km').order('asset_code'),
    supabase.from('inspections').select('id,asset_id,inspection_type,result,observations,meter_km,meter_hours,inspected_at,checklist').order('inspected_at',{ascending:false}).limit(200)
  ]);setAssets((a||[]) as Asset[]);setRows((i||[]) as Inspection[]);setLoading(false)}
  useEffect(()=>{load()},[])

  function assetFor(id:string){return assets.find(a=>a.id===id)}
  function unitName(id:string){return units.find(u=>u.id===id)?.name||'Assigned unit'}
  const visible=useMemo(()=>rows.filter(r=>{const a=assetFor(r.asset_id);return unitFilter==='all'||a?.business_unit_id===unitFilter}),[rows,assets,unitFilter])

  async function submit(e:FormEvent){
    e.preventDefault();setSaving(true);setMessage('')
    const checklist=[
      {item:'Leaks / fluid condition',pass:form.check1},{item:'Tires / tracks / running gear',pass:form.check2},
      {item:'Safety devices / guards / lights',pass:form.check3},{item:'General operational condition',pass:form.check4}
    ]
    const failed=checklist.some(x=>!x.pass)
    const finalResult=failed&&form.result==='pass'?'pass_with_observations':form.result
    const payload={asset_id:form.asset_id,inspected_by:userId,inspection_type:form.inspection_type,result:finalResult,checklist,observations:form.observations.trim()||null,meter_hours:form.meter_hours?Number(form.meter_hours):null,meter_km:form.meter_km?Number(form.meter_km):null}
    const {error}=await supabase.from('inspections').insert(payload)
    if(error)setMessage(error.message)
    else{
      if(finalResult==='fail'){
        const a=assetFor(form.asset_id)
        if(a) await supabase.from('work_orders').insert({business_unit_id:a.business_unit_id,asset_id:a.id,type:'corrective',priority:'high',title:`Failed inspection — ${a.asset_code}`,problem_description:form.observations.trim()||'Inspection failed. Review checklist and isolate equipment as required.',requested_by:userId})
      }
      setMessage(finalResult==='fail'?'Inspection saved. A corrective work order was created.':'Inspection saved successfully.')
      setForm(blank);setShowForm(false);await load()
    }
    setSaving(false)
  }

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Field Compliance</span><h1>Inspections</h1><p className="muted">Fast mobile checks with equipment identity, meter readings, findings and automatic escalation of failed inspections.</p></div>{canCreate&&<button className="primary-button action-button" onClick={()=>setShowForm(!showForm)}>+ New inspection</button>}</div>
    {message&&<div className={message.includes('saved')?'success-box':'error-box'}>{message}</div>}
    {showForm&&<form className="data-form inspection-form" onSubmit={submit}><div className="form-title"><div><span className="eyebrow">Mobile field check</span><h2>New inspection</h2></div><button type="button" className="icon-button" onClick={()=>setShowForm(false)}>×</button></div>
      <div className="form-grid">
        <label>Asset<select required value={form.asset_id} onChange={e=>{const a=assetFor(e.target.value);setForm({...form,asset_id:e.target.value,meter_hours:a?.hour_meter?.toString()||'',meter_km:a?.odometer_km?.toString()||''})}}><option value="">Select asset</option>{assets.map(a=><option key={a.id} value={a.id}>{a.asset_code} — {a.name}</option>)}</select></label>
        <label>Inspection type<select value={form.inspection_type} onChange={e=>setForm({...form,inspection_type:e.target.value})}><option value="pre_shift">Pre-shift</option><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="post_repair">Post-repair</option><option value="safety">Safety</option></select></label>
        <label>Overall result<select value={form.result} onChange={e=>setForm({...form,result:e.target.value})}><option value="pass">Pass</option><option value="pass_with_observations">Pass with observations</option><option value="fail">Fail / remove from service</option></select></label>
        <label>Hour meter<input type="number" min="0" step="0.1" value={form.meter_hours} onChange={e=>setForm({...form,meter_hours:e.target.value})}/></label>
        <label>Odometer km<input type="number" min="0" step="1" value={form.meter_km} onChange={e=>setForm({...form,meter_km:e.target.value})}/></label>
      </div>
      <div className="checklist-card"><h3>Required checklist</h3>{[
        ['check1','Leaks / fluid condition'],['check2','Tires / tracks / running gear'],['check3','Safety devices / guards / lights'],['check4','General operational condition']
      ].map(([key,label])=><label className="check-row" key={key}><input type="checkbox" checked={(form as any)[key]} onChange={e=>setForm({...form,[key]:e.target.checked})}/><span>{label}</span></label>)}</div>
      <label>Observations / defect description<textarea rows={4} value={form.observations} onChange={e=>setForm({...form,observations:e.target.value})} placeholder="Describe abnormal condition, location, symptoms and immediate action."/></label>
      <div className="form-actions"><button type="button" className="secondary-outline" onClick={()=>setShowForm(false)}>Cancel</button><button className="primary-button action-button" disabled={saving}>{saving?'Saving…':'Submit inspection'}</button></div>
    </form>}
    <div className="toolbar"><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select><span className="count-chip">{visible.length} recent</span></div>
    {loading?<div className="loading-panel">Loading inspections…</div>:visible.length===0?<div className="empty-table">No inspections recorded yet.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Asset</th><th>Business unit</th><th>Type</th><th>Result</th><th>Meters</th><th>Observations</th></tr></thead><tbody>{visible.map(r=>{const a=assetFor(r.asset_id);return <tr key={r.id}><td>{new Date(r.inspected_at).toLocaleDateString()}<small>{new Date(r.inspected_at).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}</small></td><td><strong>{a?.asset_code||'—'}</strong><small>{a?.name||''}</small></td><td>{a?unitName(a.business_unit_id):'—'}</td><td>{r.inspection_type.replaceAll('_',' ')}</td><td><span className={`priority-pill ${r.result==='fail'?'critical':r.result==='pass_with_observations'?'high':'low'}`}>{r.result.replaceAll('_',' ')}</span></td><td>{r.meter_hours!=null?`${r.meter_hours} h`:'—'}<small>{r.meter_km!=null?`${r.meter_km} km`:''}</small></td><td>{r.observations||'—'}</td></tr>})}</tbody></table></div>}
  </div>
}
