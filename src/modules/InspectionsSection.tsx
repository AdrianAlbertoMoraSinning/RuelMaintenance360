import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string;asset_category:string;hour_meter:number|null;odometer_km:number|null}
type Inspection={id:string;asset_id:string;inspection_type:string;result:string;observations:string|null;meter_km:number|null;meter_hours:number|null;inspected_at:string;checklist:any[]}
type Template={id:string;asset_category:string;inspection_type:string;name:string;checklist:Array<{item:string;required?:boolean;critical?:boolean}>;version:number}
type Props={units:BusinessUnit[];userId:string;role:string}

type CheckState={item:string;required:boolean;critical:boolean;pass:boolean}
const blank={asset_id:'',inspection_type:'pre_shift',result:'pass',observations:'',meter_hours:'',meter_km:''}

export default function InspectionsSection({units,userId,role}:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [rows,setRows]=useState<Inspection[]>([])
  const [templates,setTemplates]=useState<Template[]>([])
  const [loading,setLoading]=useState(true)
  const [showForm,setShowForm]=useState(false)
  const [form,setForm]=useState(blank)
  const [checks,setChecks]=useState<CheckState[]>([])
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')
  const [unitFilter,setUnitFilter]=useState('all')
  const canCreate=['super_admin','corporate_manager','unit_supervisor','technician','operator'].includes(role)

  async function load(){setLoading(true);const [{data:a},{data:i},{data:t}]=await Promise.all([
    supabase.from('assets').select('id,business_unit_id,asset_code,name,asset_category,hour_meter,odometer_km').order('asset_code'),
    supabase.from('inspections').select('id,asset_id,inspection_type,result,observations,meter_km,meter_hours,inspected_at,checklist').order('inspected_at',{ascending:false}).limit(200),
    supabase.from('inspection_templates').select('id,asset_category,inspection_type,name,checklist,version').eq('active',true).order('asset_category').order('inspection_type')
  ]);setAssets((a||[]) as Asset[]);setRows((i||[]) as Inspection[]);setTemplates((t||[]) as Template[]);setLoading(false)}
  useEffect(()=>{load()},[])

  function assetFor(id:string){return assets.find(a=>a.id===id)}
  function unitName(id:string){return units.find(u=>u.id===id)?.name||'Assigned unit'}
  const visible=useMemo(()=>rows.filter(r=>{const a=assetFor(r.asset_id);return unitFilter==='all'||a?.business_unit_id===unitFilter}),[rows,assets,unitFilter])
  const selectedAsset=assetFor(form.asset_id)
  const availableTypes=useMemo(()=>templates.filter(t=>t.asset_category===selectedAsset?.asset_category),[templates,selectedAsset?.asset_category])
  const activeTemplate=useMemo(()=>availableTypes.find(t=>t.inspection_type===form.inspection_type)||availableTypes[0]||null,[availableTypes,form.inspection_type])

  useEffect(()=>{
    if(!selectedAsset){setChecks([]);return}
    const template=activeTemplate
    if(template){
      if(form.inspection_type!==template.inspection_type)setForm(prev=>({...prev,inspection_type:template.inspection_type}))
      setChecks(template.checklist.map(x=>({item:x.item,required:x.required!==false,critical:Boolean(x.critical),pass:true})))
    }else{
      setChecks([
        {item:'Leaks / fluid condition',required:true,critical:true,pass:true},
        {item:'Safety devices / guards / warning devices',required:true,critical:true,pass:true},
        {item:'Structural / visible damage',required:true,critical:true,pass:true},
        {item:'General operational condition',required:true,critical:false,pass:true}
      ])
    }
  },[form.asset_id,activeTemplate?.id])

  function chooseAsset(id:string){
    const a=assetFor(id)
    setForm(prev=>({...prev,asset_id:id,inspection_type:'pre_shift',meter_hours:a?.hour_meter?.toString()||'',meter_km:a?.odometer_km?.toString()||''}))
  }

  async function submit(e:FormEvent){
    e.preventDefault();if(!selectedAsset)return
    setSaving(true);setMessage('')
    const failed=checks.some(x=>!x.pass)
    const criticalFailed=checks.some(x=>x.critical&&!x.pass)
    let finalResult=form.result
    if(criticalFailed)finalResult='fail'
    else if(failed&&finalResult==='pass')finalResult='pass_with_observations'
    const checklist=checks.map(x=>({item:x.item,pass:x.pass,required:x.required,critical:x.critical}))
    const payload={asset_id:form.asset_id,inspected_by:userId,inspection_type:form.inspection_type,result:finalResult,checklist,observations:form.observations.trim()||null,meter_hours:form.meter_hours?Number(form.meter_hours):null,meter_km:form.meter_km?Number(form.meter_km):null}
    const {data:inspection,error}=await supabase.from('inspections').insert(payload).select('id').single()
    if(error)setMessage(error.message)
    else{
      if(form.meter_hours)await supabase.from('assets').update({hour_meter:Number(form.meter_hours)}).eq('id',selectedAsset.id)
      if(form.meter_km)await supabase.from('assets').update({odometer_km:Number(form.meter_km)}).eq('id',selectedAsset.id)
      if(finalResult==='fail'){
        await supabase.from('work_orders').insert({business_unit_id:selectedAsset.business_unit_id,asset_id:selectedAsset.id,type:'corrective',priority:criticalFailed?'critical':'high',title:`Failed inspection — ${selectedAsset.asset_code}`,problem_description:form.observations.trim()||'Inspection failed. Review checklist and isolate equipment as required.',requested_by:userId})
      }
      setMessage(finalResult==='fail'?'Inspection saved. A corrective work order was created.':'Inspection saved successfully.')
      setForm(blank);setChecks([]);setShowForm(false);await load()
    }
    setSaving(false)
  }

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Field Compliance</span><h1>Inspections</h1><p className="muted">Mobile checks driven by the controlled asset category, with meter readings and automatic escalation of failed critical items.</p></div>{canCreate&&<button className="primary-button action-button" onClick={()=>setShowForm(!showForm)}>+ New inspection</button>}</div>
    {message&&<div className={message.includes('saved')?'success-box':'error-box'}>{message}</div>}
    {showForm&&<form className="data-form inspection-form" onSubmit={submit}><div className="form-title"><div><span className="eyebrow">Mobile field check</span><h2>New inspection</h2></div><button type="button" className="icon-button" onClick={()=>setShowForm(false)}>×</button></div>
      <div className="form-grid">
        <label>Asset<select required value={form.asset_id} onChange={e=>chooseAsset(e.target.value)}><option value="">Select asset</option>{assets.map(a=><option key={a.id} value={a.id}>{a.asset_code} — {a.name}</option>)}</select></label>
        <label>Inspection type<select value={form.inspection_type} onChange={e=>setForm({...form,inspection_type:e.target.value})}>{availableTypes.length?availableTypes.map(t=><option key={t.id} value={t.inspection_type}>{t.name}</option>):<><option value="pre_shift">Pre-shift</option><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="post_repair">Post-repair</option><option value="safety">Safety</option></>}</select></label>
        <label>Overall result<select value={form.result} onChange={e=>setForm({...form,result:e.target.value})}><option value="pass">Pass</option><option value="pass_with_observations">Pass with observations</option><option value="fail">Fail / remove from service</option></select></label>
        <label>Hour meter<input type="number" min="0" step="0.1" value={form.meter_hours} onChange={e=>setForm({...form,meter_hours:e.target.value})}/></label>
        <label>Odometer km<input type="number" min="0" step="1" value={form.meter_km} onChange={e=>setForm({...form,meter_km:e.target.value})}/></label>
      </div>
      {selectedAsset&&<div className="summary-strip"><span><b>{selectedAsset.asset_code}</b> {selectedAsset.name}</span><span>Category: {selectedAsset.asset_category.replaceAll('_',' ')} · Template v{activeTemplate?.version||1}</span></div>}
      <div className="checklist-card"><h3>{activeTemplate?.name||'Required checklist'}</h3>{checks.map((check,index)=><label className={`check-row ${check.critical?'critical-check':''}`} key={`${check.item}-${index}`}><input type="checkbox" checked={check.pass} onChange={e=>setChecks(prev=>prev.map((x,i)=>i===index?{...x,pass:e.target.checked}:x))}/><span>{check.item}{check.critical&&<small> Critical item</small>}</span></label>)}</div>
      <div className="warning-box"><strong>Inspection control</strong><p>A failed critical checklist item automatically changes the inspection result to FAIL and creates a critical corrective work order. This checklist does not replace OEM or regulatory inspection requirements.</p></div>
      <label>Observations / defect description<textarea rows={4} value={form.observations} onChange={e=>setForm({...form,observations:e.target.value})} placeholder="Describe abnormal condition, location, symptoms and immediate action."/></label>
      <div className="form-actions"><button type="button" className="secondary-outline" onClick={()=>setShowForm(false)}>Cancel</button><button className="primary-button action-button" disabled={saving||!form.asset_id}>{saving?'Saving…':'Submit inspection'}</button></div>
    </form>}
    <div className="toolbar"><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select><span className="count-chip">{visible.length} recent</span></div>
    {loading?<div className="loading-panel">Loading inspections…</div>:visible.length===0?<div className="empty-table">No inspections recorded yet.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Asset</th><th>Business unit</th><th>Type</th><th>Result</th><th>Meters</th><th>Observations</th></tr></thead><tbody>{visible.map(r=>{const a=assetFor(r.asset_id);return <tr key={r.id}><td>{new Date(r.inspected_at).toLocaleDateString()}<small>{new Date(r.inspected_at).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}</small></td><td><strong>{a?.asset_code||'—'}</strong><small>{a?.name||''}</small></td><td>{a?unitName(a.business_unit_id):'—'}</td><td>{r.inspection_type.replaceAll('_',' ')}</td><td><span className={`priority-pill ${r.result==='fail'?'critical':r.result==='pass_with_observations'?'high':'low'}`}>{r.result.replaceAll('_',' ')}</span></td><td>{r.meter_hours!=null?`${r.meter_hours} h`:'—'}<small>{r.meter_km!=null?`${r.meter_km} km`:''}</small></td><td>{r.observations||'—'}</td></tr>})}</tbody></table></div>}
  </div>
}
