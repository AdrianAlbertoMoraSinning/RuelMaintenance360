import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'

type Category={code:string;name:string}
type Item={item:string;critical:boolean;required:boolean}
type Template={id:string;asset_category:string;inspection_type:string;name:string;checklist:Item[];active:boolean;version:number}
type Props={role:string}

export default function InspectionTemplateAdmin({role}:Props){
  const canEdit=['super_admin','corporate_manager'].includes(role)
  const [categories,setCategories]=useState<Category[]>([])
  const [templates,setTemplates]=useState<Template[]>([])
  const [selected,setSelected]=useState('')
  const [draft,setDraft]=useState<Template|null>(null)
  const [message,setMessage]=useState('')
  const [saving,setSaving]=useState(false)
  async function load(){const [{data:c},{data:t}]=await Promise.all([supabase.from('asset_categories').select('code,name').eq('active',true).order('name'),supabase.from('inspection_templates').select('id,asset_category,inspection_type,name,checklist,active,version').order('asset_category').order('inspection_type')]);setCategories((c||[]) as Category[]);setTemplates((t||[]) as Template[])}
  useEffect(()=>{load()},[])
  useEffect(()=>{const t=templates.find(x=>x.id===selected);setDraft(t?{...t,checklist:(t.checklist||[]).map(i=>({...i}))}:null)},[selected,templates])
  const categoryName=(code:string)=>categories.find(c=>c.code===code)?.name||code
  const grouped=useMemo(()=>templates.filter(t=>t.active),[templates])
  function updateItem(index:number,patch:Partial<Item>){if(!draft)return;setDraft({...draft,checklist:draft.checklist.map((x,i)=>i===index?{...x,...patch}:x)})}
  function addItem(){if(!draft)return;setDraft({...draft,checklist:[...draft.checklist,{item:'',critical:false,required:true}]})}
  function removeItem(index:number){if(!draft)return;setDraft({...draft,checklist:draft.checklist.filter((_,i)=>i!==index)})}
  async function save(){if(!draft||!canEdit)return;const cleaned=draft.checklist.map(i=>({...i,item:i.item.trim()})).filter(i=>i.item);if(!cleaned.length){setMessage('At least one checklist item is required.');return}setSaving(true);setMessage('');const {error}=await supabase.from('inspection_templates').update({name:draft.name.trim(),inspection_type:draft.inspection_type,checklist:cleaned,version:draft.version+1,updated_at:new Date().toISOString()}).eq('id',draft.id);if(error)setMessage(error.message);else{setMessage('Inspection template saved. New inspections will use the updated version.');await load()}setSaving(false)}
  return <section className="profile-panel template-admin-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Field governance</span><h3>Inspection Template Administration</h3></div><span className="count-chip">{grouped.length} active</span></div><p className="muted">Controlled checklist library by asset category. Critical items automatically force a failed inspection when marked failed.</p>{message&&<div className={message.includes('saved')?'success-box':'error-box'}>{message}</div>}<div className="template-admin-grid"><div><label>Template<select value={selected} onChange={e=>setSelected(e.target.value)}><option value="">Select template</option>{grouped.map(t=><option key={t.id} value={t.id}>{categoryName(t.asset_category)} — {t.inspection_type.replaceAll('_',' ')} — v{t.version}</option>)}</select></label>{draft&&<div className="detail-list"><span>Category <b>{categoryName(draft.asset_category)}</b></span><span>Version <b>{draft.version}</b></span></div>}</div>{draft&&<div className="template-editor"><label>Template name<input disabled={!canEdit} value={draft.name} onChange={e=>setDraft({...draft,name:e.target.value})}/></label><label>Inspection type<select disabled={!canEdit} value={draft.inspection_type} onChange={e=>setDraft({...draft,inspection_type:e.target.value})}><option value="pre_shift">Pre-shift</option><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="post_repair">Post-repair</option><option value="safety">Safety</option></select></label><div className="checklist-card"><h3>Checklist items</h3>{draft.checklist.map((item,i)=><div className="template-item-row" key={i}><input disabled={!canEdit} value={item.item} onChange={e=>updateItem(i,{item:e.target.value})} placeholder="Inspection item"/><label className="check-row"><input disabled={!canEdit} type="checkbox" checked={item.required} onChange={e=>updateItem(i,{required:e.target.checked})}/><span>Required</span></label><label className="check-row"><input disabled={!canEdit} type="checkbox" checked={item.critical} onChange={e=>updateItem(i,{critical:e.target.checked})}/><span>Critical</span></label>{canEdit&&<button type="button" className="icon-button small" onClick={()=>removeItem(i)}>×</button>}</div>)}{canEdit&&<button type="button" className="secondary-outline mini" onClick={addItem}>+ Add item</button>}</div>{canEdit&&<div className="form-actions"><button className="primary-button action-button" disabled={saving} onClick={save}>{saving?'Saving…':'Save template'}</button></div>}</div>}</div></section>
}
