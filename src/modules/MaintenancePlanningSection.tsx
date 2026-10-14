import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string}
type Plan={id:string;asset_id:string;title:string;next_due_date:string|null;active:boolean;plan_type:string}
type WO={id:string;work_order_number:number;business_unit_id:string;asset_id:string;title:string;status:string;priority:string;scheduled_for:string|null;created_at:string;estimated_cost:number|null}
type Props={units:BusinessUnit[]}
function age(date:string){return Math.max(0,Math.floor((Date.now()-new Date(date).getTime())/86400000))}

export default function MaintenancePlanningSection({units}:Props){
  const [assets,setAssets]=useState<Asset[]>([]);const [plans,setPlans]=useState<Plan[]>([]);const [orders,setOrders]=useState<WO[]>([]);const [loading,setLoading]=useState(true);const [unitFilter,setUnitFilter]=useState('all')
  useEffect(()=>{async function load(){setLoading(true);const [{data:a},{data:p},{data:o}]=await Promise.all([
    supabase.from('assets').select('id,business_unit_id,asset_code,name'),
    supabase.from('maintenance_plans').select('id,asset_id,title,next_due_date,active,plan_type').eq('active',true),
    supabase.from('work_orders').select('id,work_order_number,business_unit_id,asset_id,title,status,priority,scheduled_for,created_at,estimated_cost').not('status','in','("completed","cancelled")')]);setAssets((a||[]) as Asset[]);setPlans((p||[]) as Plan[]);setOrders((o||[]) as WO[]);setLoading(false)}load()},[])
  function asset(id:string){return assets.find(a=>a.id===id)}function unitName(id:string){return units.find(u=>u.id===id)?.name||'Unit'}
  const filteredOrders=useMemo(()=>orders.filter(o=>unitFilter==='all'||o.business_unit_id===unitFilter),[orders,unitFilter])
  const filteredPlans=useMemo(()=>plans.filter(p=>{const a=asset(p.asset_id);return unitFilter==='all'||a?.business_unit_id===unitFilter}),[plans,assets,unitFilter])
  const start=new Date();start.setHours(0,0,0,0);const days=Array.from({length:35},(_,i)=>{const d=new Date(start);d.setDate(d.getDate()+i);return d})
  const backlogBands=[{label:'0–7d',min:0,max:7},{label:'8–14d',min:8,max:14},{label:'15–30d',min:15,max:30},{label:'>30d',min:31,max:99999}].map(b=>({...b,count:filteredOrders.filter(o=>{const a=age(o.created_at);return a>=b.min&&a<=b.max}).length}))
  const max=Math.max(1,...backlogBands.map(x=>x.count))
  const highRisk=filteredOrders.filter(o=>['high','critical'].includes(o.priority)).length
  const unscheduled=filteredOrders.filter(o=>!o.scheduled_for).length
  const exposure=filteredOrders.reduce((s,o)=>s+Number(o.estimated_cost||0),0)
  return <div><div className="hero-row compact-hero"><div><span className="eyebrow">Maintenance Planning</span><h1>Calendar & Backlog</h1><p className="muted">Upcoming PM, scheduled work and backlog aging in one planning workspace.</p></div></div>
    <div className="toolbar"><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></div>
    <div className="stat-grid"><article className="stat-card"><span>Open backlog</span><strong>{filteredOrders.length}</strong><small>Active non-completed work</small></article><article className="stat-card"><span>High / Critical</span><strong>{highRisk}</strong><small>Priority work</small></article><article className="stat-card"><span>Unscheduled</span><strong>{unscheduled}</strong><small>Needs planning</small></article><article className="stat-card"><span>Estimated exposure</span><strong>${exposure.toLocaleString(undefined,{maximumFractionDigits:0})}</strong><small>Current backlog value</small></article></div>
    <section className="planning-grid"><article className="profile-panel"><span className="eyebrow">Backlog aging</span><h3>Open work by age</h3><div className="approval-aging-chart">{backlogBands.map(x=><div key={x.label}><span>{x.label}</span><i><b style={{width:`${x.count/max*100}%`}}/></i><strong>{x.count}</strong></div>)}</div></article><article className="profile-panel"><span className="eyebrow">Planning indicators</span><h3>Schedule quality</h3><div className="detail-list"><span>Scheduled <b>{filteredOrders.length-unscheduled}</b></span><span>Unscheduled <b>{unscheduled}</b></span><span>PM records active <b>{filteredPlans.length}</b></span><span>Due in next 35 days <b>{filteredPlans.filter(p=>p.next_due_date&&new Date(p.next_due_date)>=start&&new Date(p.next_due_date)<=days[days.length-1]).length}</b></span></div></article></section>
    <div className="section-heading"><div><span className="eyebrow">35-day horizon</span><h2>Maintenance Calendar</h2></div></div>
    {loading?<div className="loading-panel">Loading planning data…</div>:<div className="calendar-grid">{days.map(d=>{const key=d.toISOString().slice(0,10);const due=filteredPlans.filter(p=>p.next_due_date===key);const scheduled=filteredOrders.filter(o=>o.scheduled_for?.slice(0,10)===key);return <div className={`calendar-day ${due.length||scheduled.length?'has-work':''}`} key={key}><div className="calendar-date"><b>{d.toLocaleDateString(undefined,{weekday:'short'})}</b><span>{d.getDate()}</span></div>{due.slice(0,3).map(p=>{const a=asset(p.asset_id);return <div className="calendar-event pm" key={p.id}><b>PM</b> {a?.asset_code||''}<small>{p.title}</small></div>})}{scheduled.slice(0,3).map(o=><div className={`calendar-event wo ${o.priority}`} key={o.id}><b>WO</b> #{o.work_order_number}<small>{asset(o.asset_id)?.asset_code} · {o.title}</small></div>)}{due.length+scheduled.length>6&&<small>+{due.length+scheduled.length-6} more</small>}</div>})}</div>}
    <div className="section-heading"><div><span className="eyebrow">Backlog detail</span><h2>Oldest active work</h2></div></div>
    <div className="table-wrap"><table className="data-table"><thead><tr><th>WO</th><th>Unit</th><th>Asset</th><th>Task</th><th>Priority</th><th>Age</th><th>Scheduled</th><th>Estimate</th></tr></thead><tbody>{[...filteredOrders].sort((a,b)=>new Date(a.created_at).getTime()-new Date(b.created_at).getTime()).slice(0,25).map(o=><tr key={o.id}><td>#{String(o.work_order_number).padStart(5,'0')}</td><td>{unitName(o.business_unit_id)}</td><td>{asset(o.asset_id)?.asset_code||'—'}</td><td><strong>{o.title}</strong></td><td><span className={`priority-pill ${o.priority}`}>{o.priority}</span></td><td>{age(o.created_at)} d</td><td>{o.scheduled_for?new Date(o.scheduled_for).toLocaleDateString():'Unscheduled'}</td><td>${Number(o.estimated_cost||0).toLocaleString()}</td></tr>)}</tbody></table></div>
  </div>
}
