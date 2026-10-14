import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type AssetLite = { id:string; business_unit_id:string; asset_code:string; name:string }
type WorkOrder = {
  id:string; work_order_number:number; business_unit_id:string; asset_id:string; type:string; status:string; priority:string;
  title:string; problem_description:string|null; assigned_to:string|null; scheduled_for:string|null; created_at:string;
}
type Props = { units:BusinessUnit[]; userId:string; role:string }

export default function WorkOrdersSection({ units, userId, role }:Props) {
  const [orders,setOrders] = useState<WorkOrder[]>([])
  const [assets,setAssets] = useState<AssetLite[]>([])
  const [showForm,setShowForm] = useState(false)
  const [loading,setLoading] = useState(true)
  const [message,setMessage] = useState('')
  const [filter,setFilter] = useState('open')
  const [form,setForm] = useState({ business_unit_id:'',asset_id:'',type:'corrective',priority:'medium',title:'',problem_description:'',scheduled_for:'' })
  const canCreate = ['super_admin','corporate_manager','unit_supervisor','technician','operator'].includes(role)

  async function load(){
    setLoading(true)
    const [{data:o},{data:a}] = await Promise.all([
      supabase.from('work_orders').select('id,work_order_number,business_unit_id,asset_id,type,status,priority,title,problem_description,assigned_to,scheduled_for,created_at').order('created_at',{ascending:false}),
      supabase.from('assets').select('id,business_unit_id,asset_code,name').order('asset_code')
    ])
    if(o) setOrders(o as WorkOrder[])
    if(a) setAssets(a as AssetLite[])
    setLoading(false)
  }
  useEffect(()=>{load()},[])

  const visible = useMemo(()=> orders.filter(o=>filter==='all' ? true : filter==='open' ? !['completed','cancelled'].includes(o.status) : o.status===filter),[orders,filter])
  const formAssets = assets.filter(a=>!form.business_unit_id || a.business_unit_id===form.business_unit_id)
  const assetLabel = (id:string)=>{ const a=assets.find(x=>x.id===id); return a ? `${a.asset_code} · ${a.name}` : 'Asset' }
  const unitLabel = (id:string)=>units.find(u=>u.id===id)?.name || 'Business unit'

  async function createOrder(e:FormEvent){
    e.preventDefault(); setMessage('')
    const { error } = await supabase.from('work_orders').insert({
      business_unit_id:form.business_unit_id, asset_id:form.asset_id, type:form.type, priority:form.priority,
      title:form.title.trim(), problem_description:form.problem_description.trim() || null,
      requested_by:userId, scheduled_for:form.scheduled_for ? new Date(form.scheduled_for).toISOString() : null
    })
    if(error) setMessage(error.message)
    else { setMessage('Work order created successfully.'); setShowForm(false); setForm({business_unit_id:'',asset_id:'',type:'corrective',priority:'medium',title:'',problem_description:'',scheduled_for:''}); await load() }
  }

  async function advance(order:WorkOrder){
    const next:Record<string,string> = {open:'assigned',assigned:'in_progress',in_progress:'completed',waiting_parts:'in_progress',waiting_vendor:'in_progress'}
    const status = next[order.status]
    if(!status) return
    const payload:any = {status}
    if(status==='in_progress') payload.started_at = new Date().toISOString()
    if(status==='completed') payload.completed_at = new Date().toISOString()
    const {error}=await supabase.from('work_orders').update(payload).eq('id',order.id)
    if(error) setMessage(error.message); else await load()
  }

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Execution Control</span><h1>Work Orders</h1><p className="muted">Corrective, preventive and predictive work with accountable ownership, time, cost and closure.</p></div>{canCreate&&<button className="primary-button action-button" onClick={()=>setShowForm(!showForm)}>+ New work order</button>}</div>
    {message&&<div className={message.includes('successfully')?'success-box':'error-box'}>{message}</div>}
    {showForm&&<form className="data-form" onSubmit={createOrder}>
      <div className="form-title"><div><span className="eyebrow">Maintenance request</span><h2>Create work order</h2></div><button type="button" className="icon-button" onClick={()=>setShowForm(false)}>×</button></div>
      <div className="form-grid">
        <label>Business unit<select required value={form.business_unit_id} onChange={e=>setForm({...form,business_unit_id:e.target.value,asset_id:''})}><option value="">Select unit</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
        <label>Asset<select required value={form.asset_id} onChange={e=>setForm({...form,asset_id:e.target.value})}><option value="">Select asset</option>{formAssets.map(a=><option key={a.id} value={a.id}>{a.asset_code} · {a.name}</option>)}</select></label>
        <label>Type<select value={form.type} onChange={e=>setForm({...form,type:e.target.value})}><option value="corrective">Corrective</option><option value="preventive">Preventive</option><option value="predictive">Predictive</option><option value="inspection">Inspection</option></select></label>
        <label>Priority<select value={form.priority} onChange={e=>setForm({...form,priority:e.target.value})}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option><option value="critical">Critical</option></select></label>
        <label className="span-2">Title<input required value={form.title} onChange={e=>setForm({...form,title:e.target.value})} placeholder="Describe the maintenance task" /></label>
        <label className="span-2">Problem / scope<textarea rows={4} value={form.problem_description} onChange={e=>setForm({...form,problem_description:e.target.value})}/></label>
        <label>Scheduled for<input type="datetime-local" value={form.scheduled_for} onChange={e=>setForm({...form,scheduled_for:e.target.value})}/></label>
      </div>
      <div className="form-actions"><button type="button" className="secondary-outline" onClick={()=>setShowForm(false)}>Cancel</button><button className="primary-button action-button">Create work order</button></div>
    </form>}
    <div className="toolbar"><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="open">Active work</option><option value="all">All work orders</option><option value="completed">Completed</option><option value="waiting_parts">Waiting parts</option><option value="waiting_vendor">Waiting vendor</option></select><span className="count-chip">{visible.length} orders</span></div>
    {loading?<div className="loading-panel">Loading work orders…</div>:visible.length===0?<div className="empty-table">No work orders match this view.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>WO</th><th>Asset</th><th>Task</th><th>Type</th><th>Priority</th><th>Status</th><th></th></tr></thead><tbody>{visible.map(o=><tr key={o.id}><td><strong>#{String(o.work_order_number).padStart(5,'0')}</strong><small>{unitLabel(o.business_unit_id)}</small></td><td>{assetLabel(o.asset_id)}</td><td><strong>{o.title}</strong><small>{o.problem_description||'No additional scope entered'}</small></td><td>{o.type}</td><td><span className={`priority-pill ${o.priority}`}>{o.priority}</span></td><td><span className={`status-pill ${o.status}`}>{o.status.replaceAll('_',' ')}</span></td><td>{!['completed','cancelled'].includes(o.status)&&<button className="secondary-outline mini" onClick={()=>advance(o)}>Advance</button>}</td></tr>)}</tbody></table></div>}
  </div>
}
