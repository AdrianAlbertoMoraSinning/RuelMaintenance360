import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Order={id:string;business_unit_id:string;asset_id:string|null;status:string;type:string;priority:string;downtime_hours:number|null;labour_hours:number|null;labour_cost:number|null;parts_cost:number|null;vendor_cost:number|null;other_cost:number|null;created_at:string;started_at:string|null;completed_at:string|null}
type Plan={id:string;asset_id:string;next_due_date:string|null;active:boolean}
type Asset={id:string;business_unit_id:string;asset_category:string}
type Inspection={id:string;asset_id:string;result:string;inspected_at:string}
type Category={code:string;name:string;sort_order:number}
type Props={units:BusinessUnit[]}

export default function AnalyticsSection({units}:Props){
  const [orders,setOrders]=useState<Order[]>([])
  const [plans,setPlans]=useState<Plan[]>([])
  const [assets,setAssets]=useState<Asset[]>([])
  const [inspections,setInspections]=useState<Inspection[]>([])
  const [categories,setCategories]=useState<Category[]>([])
  const [loading,setLoading]=useState(true)
  const [unitFilter,setUnitFilter]=useState('all')
  const [categoryFilter,setCategoryFilter]=useState('all')

  useEffect(()=>{async function load(){setLoading(true);const [{data:o},{data:p},{data:a},{data:i},{data:c}]=await Promise.all([
    supabase.from('work_orders').select('id,business_unit_id,asset_id,status,type,priority,downtime_hours,labour_hours,labour_cost,parts_cost,vendor_cost,other_cost,created_at,started_at,completed_at'),
    supabase.from('maintenance_plans').select('id,asset_id,next_due_date,active').eq('active',true),
    supabase.from('assets').select('id,business_unit_id,asset_category'),
    supabase.from('inspections').select('id,asset_id,result,inspected_at'),
    supabase.from('asset_categories').select('code,name,sort_order').eq('active',true).order('sort_order')
  ]);setOrders((o||[]) as Order[]);setPlans((p||[]) as Plan[]);setAssets((a||[]) as Asset[]);setInspections((i||[]) as Inspection[]);setCategories((c||[]) as Category[]);setLoading(false)}load()},[])

  const scopedAssets=useMemo(()=>assets.filter(a=>(unitFilter==='all'||a.business_unit_id===unitFilter)&&(categoryFilter==='all'||a.asset_category===categoryFilter)),[assets,unitFilter,categoryFilter])
  const assetIds=useMemo(()=>new Set(scopedAssets.map(a=>a.id)),[scopedAssets])

  const data=useMemo(()=>{
    const o=orders.filter(x=>(unitFilter==='all'||x.business_unit_id===unitFilter)&&(!x.asset_id||assetIds.has(x.asset_id)))
    const p=plans.filter(x=>assetIds.has(x.asset_id))
    const ins=inspections.filter(x=>assetIds.has(x.asset_id))
    const open=o.filter(x=>!['completed','cancelled'].includes(x.status));const completed=o.filter(x=>x.status==='completed')
    const today=new Date().toISOString().slice(0,10);const due=p.filter(x=>x.next_due_date&&x.next_due_date<=today)
    const mttrValues=completed.filter(x=>x.started_at&&x.completed_at).map(x=>(new Date(x.completed_at!).getTime()-new Date(x.started_at!).getTime())/3600000).filter(x=>x>=0)
    const mttr=mttrValues.length?mttrValues.reduce((a,b)=>a+b,0)/mttrValues.length:0
    const downtime=o.reduce((s,x)=>s+Number(x.downtime_hours||0),0)
    const cost=o.reduce((s,x)=>s+Number(x.labour_cost||0)+Number(x.parts_cost||0)+Number(x.vendor_cost||0)+Number(x.other_cost||0),0)
    const failures=o.filter(x=>x.type==='corrective').length
    const passed=ins.filter(x=>x.result==='pass').length
    const inspectionPass=ins.length?passed/ins.length*100:0
    return {assets:assetIds.size,open:open.length,completed:completed.length,due:due.length,mttr,downtime,cost,failures,inspectionPass,critical:open.filter(x=>x.priority==='critical').length}
  },[orders,plans,inspections,assetIds,unitFilter])

  const categoryBreakdown=useMemo(()=>categories.map(c=>{
    const ids=new Set(assets.filter(a=>(unitFilter==='all'||a.business_unit_id===unitFilter)&&a.asset_category===c.code).map(a=>a.id))
    const relatedOrders=orders.filter(o=>o.asset_id&&ids.has(o.asset_id))
    return {code:c.code,name:c.name,assets:ids.size,open:relatedOrders.filter(o=>!['completed','cancelled'].includes(o.status)).length,downtime:relatedOrders.reduce((s,o)=>s+Number(o.downtime_hours||0),0),cost:relatedOrders.reduce((s,o)=>s+Number(o.labour_cost||0)+Number(o.parts_cost||0)+Number(o.vendor_cost||0)+Number(o.other_cost||0),0)}
  }).filter(x=>x.assets>0||x.open>0),[categories,assets,orders,unitFilter])

  const cards=[['Assets in scope',data.assets.toString(),'Current authorized asset population'],['Open backlog',data.open.toString(),'Orders not completed or cancelled'],['PM due / overdue',data.due.toString(),'Active plans at or past due date'],['Critical open WOs',data.critical.toString(),'Immediate management attention'],['Recorded downtime',`${data.downtime.toFixed(1)} h`,'Cumulative downtime entered in work orders'],['MTTR',`${data.mttr.toFixed(1)} h`,'Average completed repair duration'],['Maintenance cost',`$${data.cost.toFixed(0)}`,'Labour + parts + vendor + other recorded cost'],['Inspection pass rate',`${data.inspectionPass.toFixed(1)}%`,'Pass results among recorded inspections']]

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Reliability & Cost Intelligence</span><h1>Analytics & KPIs</h1><p className="muted">Operational maintenance indicators calculated from recorded work orders, plans and inspections.</p></div></div>
    <div className="toolbar"><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">Corporate — all authorized units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select><select value={categoryFilter} onChange={e=>setCategoryFilter(e.target.value)}><option value="all">All asset categories</option>{categories.map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select></div>
    {loading?<div className="loading-panel">Calculating maintenance indicators…</div>:<>
      <div className="stat-grid analytics-grid">{cards.map(([t,v,d])=><article className="stat-card" key={t}><span>{t}</span><strong>{v}</strong><small>{d}</small></article>)}</div>
      <div className="section-heading"><div><span className="eyebrow">Category reporting foundation</span><h2>Performance by Asset Category</h2></div></div>
      {categoryBreakdown.length===0?<div className="empty-table">No category data recorded yet.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>Category</th><th>Assets</th><th>Open WOs</th><th>Downtime</th><th>Recorded Cost</th></tr></thead><tbody>{categoryBreakdown.map(r=><tr key={r.code}><td><strong>{r.name}</strong><small>{r.code}</small></td><td>{r.assets}</td><td>{r.open}</td><td>{r.downtime.toFixed(1)} h</td><td>${r.cost.toFixed(0)}</td></tr>)}</tbody></table></div>}
      <div className="summary-strip"><span><b>{data.failures}</b> corrective work orders recorded</span><span><b>{data.completed}</b> completed work orders</span></div>
      <div className="phase-banner">Formal report generation and email distribution are part of the reporting phase. The category master and filters implemented here provide the controlled data needed for those scheduled/exportable reports.</div>
    </>}
  </div>
}
