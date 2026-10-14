import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string;status:string;asset_category:string}
type WO={id:string;business_unit_id:string;asset_id:string;status:string;type:string;priority:string;created_at:string;completed_at:string|null;downtime_hours:number;labour_cost:number;parts_cost:number;vendor_cost:number;other_cost:number}
type Plan={id:string;asset_id:string;active:boolean;next_due_date:string|null}
type Insp={id:string;asset_id:string;result:string;inspected_at:string}
type Props={units:BusinessUnit[];openSection:(key:string)=>void}

const palette=['#1f2937','#f4c430','#6b7280','#b42318','#2563eb','#0f766e','#9a3412','#7c3aed']
function Donut({items}:{items:Array<{label:string;value:number}>}){
  const total=items.reduce((s,x)=>s+x.value,0)
  let acc=0
  const stops=items.map((x,i)=>{const start=total?acc/total*100:0;acc+=x.value;const end=total?acc/total*100:0;return `${palette[i%palette.length]} ${start}% ${end}%`}).join(',')
  return <div className="mini-chart-wrap"><div className="donut-chart" style={{background:total?`conic-gradient(${stops})`:'#ecece7'}}><span>{total}</span></div><div className="chart-legend">{items.filter(x=>x.value>0).map((x,i)=><span key={x.label}><i style={{background:palette[i%palette.length]}}/>{x.label} <b>{x.value}</b></span>)}</div></div>
}
function Bars({items,suffix='' }:{items:Array<{label:string;value:number}>;suffix?:string}){const max=Math.max(1,...items.map(x=>x.value));return <div className="bar-chart">{items.map((x,i)=><div className="bar-row" key={x.label}><span>{x.label}</span><div className="bar-track"><i style={{width:`${Math.max(2,x.value/max*100)}%`,background:palette[i%palette.length]}}/></div><b>{Number.isInteger(x.value)?x.value:x.value.toFixed(1)}{suffix}</b></div>)}</div>}
function ageBand(date:string){const days=Math.floor((Date.now()-new Date(date).getTime())/86400000);if(days<=7)return'0–7d';if(days<=14)return'8–14d';if(days<=30)return'15–30d';return'>30d'}

export default function BusinessUnitsPerformance({units,openSection}:Props){
  const [assets,setAssets]=useState<Asset[]>([]);const [orders,setOrders]=useState<WO[]>([]);const [plans,setPlans]=useState<Plan[]>([]);const [inspections,setInspections]=useState<Insp[]>([]);const [loading,setLoading]=useState(true)
  useEffect(()=>{async function load(){setLoading(true);const since=new Date(Date.now()-180*86400000).toISOString();const [{data:a},{data:o},{data:p},{data:i}]=await Promise.all([
    supabase.from('assets').select('id,business_unit_id,asset_code,name,status,asset_category'),
    supabase.from('work_orders').select('id,business_unit_id,asset_id,status,type,priority,created_at,completed_at,downtime_hours,labour_cost,parts_cost,vendor_cost,other_cost').gte('created_at',since),
    supabase.from('maintenance_plans').select('id,asset_id,active,next_due_date').eq('active',true),
    supabase.from('inspections').select('id,asset_id,result,inspected_at').gte('inspected_at',since)
  ]);setAssets((a||[]) as Asset[]);setOrders((o||[]) as WO[]);setPlans((p||[]) as Plan[]);setInspections((i||[]) as Insp[]);setLoading(false)}load()},[])
  const nowDay=new Date().toISOString().slice(0,10)
  const cards=useMemo(()=>units.map(u=>{
    const ua=assets.filter(a=>a.business_unit_id===u.id);const ids=new Set(ua.map(a=>a.id));const wo=orders.filter(o=>o.business_unit_id===u.id);const open=wo.filter(o=>!['completed','cancelled'].includes(o.status));const pmDue=plans.filter(p=>ids.has(p.asset_id)&&p.next_due_date&&p.next_due_date<=nowDay).length;const critical=open.filter(o=>o.priority==='critical').length;const downtime=wo.reduce((s,o)=>s+Number(o.downtime_hours||0),0);const cost=wo.reduce((s,o)=>s+Number(o.labour_cost||0)+Number(o.parts_cost||0)+Number(o.vendor_cost||0)+Number(o.other_cost||0),0)
    const statusNames=['open','assigned','in_progress','waiting_parts','waiting_vendor','awaiting_approval','completed'];const statusItems=statusNames.map(x=>({label:x.replaceAll('_',' '),value:wo.filter(o=>o.status===x).length}))
    const costItems=[{label:'Labour',value:wo.reduce((s,o)=>s+Number(o.labour_cost||0),0)},{label:'Parts',value:wo.reduce((s,o)=>s+Number(o.parts_cost||0),0)},{label:'Vendor',value:wo.reduce((s,o)=>s+Number(o.vendor_cost||0),0)},{label:'Other',value:wo.reduce((s,o)=>s+Number(o.other_cost||0),0)}]
    const insp=inspections.filter(i=>ids.has(i.asset_id));const inspectionItems=['pass','pass_with_observations','fail'].map(x=>({label:x.replaceAll('_',' '),value:insp.filter(i=>i.result===x).length}))
    const backlog=['0–7d','8–14d','15–30d','>30d'].map(label=>({label,value:open.filter(o=>ageBand(o.created_at)===label).length}))
    const months=Array.from({length:6},(_,idx)=>{const d=new Date();d.setMonth(d.getMonth()-(5-idx));const key=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;return{label:d.toLocaleDateString(undefined,{month:'short'}),value:wo.filter(o=>o.created_at.startsWith(key)).reduce((s,o)=>s+Number(o.downtime_hours||0),0)}})
    const health=critical>0?'Critical':pmDue>0||open.length>5?'Warning':'Healthy'
    return{u,assets:ua.length,open:open.length,pmDue,critical,downtime,cost,statusItems,costItems,inspectionItems,backlog,months,health}
  }),[units,assets,orders,plans,inspections,nowDay])
  return <div><div className="hero-row compact-hero"><div><span className="eyebrow">Operational Performance by Unit</span><h1>Business Units</h1><p className="muted">A visual maintenance-performance view for every RUEL operation, using live authorized records.</p></div></div>
    {loading?<div className="loading-panel">Building unit performance dashboards…</div>:<div className="performance-unit-stack">{cards.map(c=><section className="unit-performance-card" key={c.u.id}><div className="unit-performance-head"><div><span className="eyebrow">RUEL {c.u.brand_label}</span><h2>{c.u.name}</h2><p>{c.u.address||'Location details pending'}</p></div><span className={`health-pill ${c.health.toLowerCase()}`}>{c.health}</span></div>
      <div className="unit-kpis"><span><b>{c.assets}</b> Assets</span><span><b>{c.open}</b> Open WO</span><span><b>{c.pmDue}</b> PM due</span><span><b>{c.critical}</b> Critical</span><span><b>{c.downtime.toFixed(1)} h</b> Downtime</span><span><b>${c.cost.toLocaleString(undefined,{maximumFractionDigits:0})}</b> Cost / 180d</span></div>
      <div className="unit-chart-grid"><article><h3>Work order status</h3><Donut items={c.statusItems}/></article><article><h3>Backlog aging</h3><Bars items={c.backlog}/></article><article><h3>Downtime trend · 6 months</h3><Bars items={c.months} suffix=" h"/></article><article><h3>Maintenance cost breakdown</h3><Donut items={c.costItems.map(x=>({...x,value:Math.round(x.value)}))}/></article><article><h3>Inspection results · 180 days</h3><Donut items={c.inspectionItems}/></article><article className="unit-actions-panel"><h3>Act on this unit</h3><p className="muted">Open the operational records behind these indicators.</p><div className="unit-quick-actions"><button onClick={()=>openSection('assets')}>Assets</button><button onClick={()=>openSection('work_orders')}>Work Orders</button><button onClick={()=>openSection('inspections')}>Inspections</button><button onClick={()=>openSection('reports')}>Reports</button></div></article></div>
    </section>)}</div>}
  </div>
}
