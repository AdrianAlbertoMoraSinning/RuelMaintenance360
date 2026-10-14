import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'

type Part={id:string;part_number:string;description:string;unit_of_measure:string;standard_cost:number;active:boolean}
type Location={id:string;business_unit_id:string;name:string}
type Stock={location_id:string|null;part_id:string|null;quantity_on_hand:number|null}
type Tx={id:string;part_id:string;location_id:string;transaction_type:string;quantity:number;unit_cost:number;recorded_at:string;reference:string|null;notes:string|null}
type Vendor={id:string;name:string;contact_name:string|null;phone:string|null;email:string|null;active:boolean}
type WorkVendor={work_order_id:string;vendor_id:string;quoted_amount:number|null;invoiced_amount:number|null;response_hours:number|null;completion_rating:number|null;notes:string|null}
type Props={workOrderId:string;businessUnitId:string;userId:string;canManage:boolean;onChanged:()=>void}

export default function WorkOrderResources({workOrderId,businessUnitId,userId,canManage,onChanged}:Props){
  const [parts,setParts]=useState<Part[]>([])
  const [locations,setLocations]=useState<Location[]>([])
  const [stock,setStock]=useState<Stock[]>([])
  const [transactions,setTransactions]=useState<Tx[]>([])
  const [vendors,setVendors]=useState<Vendor[]>([])
  const [linkedVendors,setLinkedVendors]=useState<WorkVendor[]>([])
  const [message,setMessage]=useState('')
  const [saving,setSaving]=useState(false)
  const [partForm,setPartForm]=useState({part_id:'',location_id:'',quantity:'',unit_cost:'',reference:'',notes:'',transaction_type:'issue'})
  const [vendorForm,setVendorForm]=useState({vendor_id:'',quoted_amount:'',invoiced_amount:'',response_hours:'',completion_rating:'',notes:''})

  async function load(){
    const [{data:p},{data:l},{data:s},{data:t},{data:v},{data:wv}]=await Promise.all([
      supabase.from('parts').select('id,part_number,description,unit_of_measure,standard_cost,active').eq('active',true).order('part_number'),
      supabase.from('inventory_locations').select('id,business_unit_id,name').eq('business_unit_id',businessUnitId).eq('active',true).order('name'),
      supabase.from('inventory_on_hand').select('location_id,part_id,quantity_on_hand').eq('business_unit_id',businessUnitId),
      supabase.from('inventory_transactions').select('id,part_id,location_id,transaction_type,quantity,unit_cost,recorded_at,reference,notes').eq('work_order_id',workOrderId).order('recorded_at',{ascending:false}),
      supabase.from('vendors').select('id,name,contact_name,phone,email,active').eq('active',true).order('name'),
      supabase.from('work_order_vendors').select('work_order_id,vendor_id,quoted_amount,invoiced_amount,response_hours,completion_rating,notes').eq('work_order_id',workOrderId)
    ])
    setParts((p||[]) as Part[]);setLocations((l||[]) as Location[]);setStock((s||[]) as Stock[]);setTransactions((t||[]) as Tx[]);setVendors((v||[]) as Vendor[]);setLinkedVendors((wv||[]) as WorkVendor[])
  }
  useEffect(()=>{load()},[workOrderId,businessUnitId])

  function part(id:string){return parts.find(p=>p.id===id)}
  function location(id:string){return locations.find(l=>l.id===id)}
  function vendor(id:string){return vendors.find(v=>v.id===id)}
  function onHand(partId:string,locationId:string){return Number(stock.find(s=>s.part_id===partId&&s.location_id===locationId)?.quantity_on_hand||0)}

  const issuedCost=useMemo(()=>transactions.reduce((sum,t)=>{
    if(t.transaction_type==='issue')return sum+Math.abs(Number(t.quantity))*Number(t.unit_cost||0)
    if(t.transaction_type==='return')return sum-Math.abs(Number(t.quantity))*Number(t.unit_cost||0)
    return sum
  },0),[transactions])
  const vendorCost=useMemo(()=>linkedVendors.reduce((sum,v)=>sum+Number(v.invoiced_amount??v.quoted_amount??0),0),[linkedVendors])

  async function savePart(e:FormEvent){
    e.preventDefault();if(!canManage)return
    const qty=Math.abs(Number(partForm.quantity||0));if(!qty){setMessage('Quantity must be greater than zero.');return}
    const p=part(partForm.part_id);if(!p)return
    if(partForm.transaction_type==='issue'&&qty>onHand(partForm.part_id,partForm.location_id)){setMessage('Issue quantity exceeds current stock at this location.');return}
    setSaving(true);setMessage('')
    const {error}=await supabase.from('inventory_transactions').insert({part_id:partForm.part_id,location_id:partForm.location_id,work_order_id:workOrderId,transaction_type:partForm.transaction_type,quantity:qty,unit_cost:partForm.unit_cost?Number(partForm.unit_cost):Number(p.standard_cost||0),reference:partForm.reference.trim()||null,notes:partForm.notes.trim()||null,recorded_by:userId})
    if(error)setMessage(error.message);else{setMessage(partForm.transaction_type==='issue'?'Part issued to work order.':'Part returned from work order.');setPartForm({part_id:'',location_id:'',quantity:'',unit_cost:'',reference:'',notes:'',transaction_type:'issue'});await load();onChanged()}
    setSaving(false)
  }

  function editVendor(row:WorkVendor){setVendorForm({vendor_id:row.vendor_id,quoted_amount:row.quoted_amount?.toString()||'',invoiced_amount:row.invoiced_amount?.toString()||'',response_hours:row.response_hours?.toString()||'',completion_rating:row.completion_rating?.toString()||'',notes:row.notes||''})}

  async function saveVendor(e:FormEvent){
    e.preventDefault();if(!canManage||!vendorForm.vendor_id)return
    setSaving(true);setMessage('')
    const payload={work_order_id:workOrderId,vendor_id:vendorForm.vendor_id,quoted_amount:vendorForm.quoted_amount?Number(vendorForm.quoted_amount):null,invoiced_amount:vendorForm.invoiced_amount?Number(vendorForm.invoiced_amount):null,response_hours:vendorForm.response_hours?Number(vendorForm.response_hours):null,completion_rating:vendorForm.completion_rating?Number(vendorForm.completion_rating):null,notes:vendorForm.notes.trim()||null}
    const {error}=await supabase.from('work_order_vendors').upsert(payload,{onConflict:'work_order_id,vendor_id'})
    if(error)setMessage(error.message);else{setMessage('Vendor linkage saved.');setVendorForm({vendor_id:'',quoted_amount:'',invoiced_amount:'',response_hours:'',completion_rating:'',notes:''});await load();onChanged()}
    setSaving(false)
  }

  return <div className="wo-resources">
    {message&&<div className={/issued|returned|saved/i.test(message)?'success-box':'error-box'}>{message}</div>}
    <div className="section-heading small-heading"><div><span className="eyebrow">Materials & external services</span><h3>Work order resources</h3></div><span className="count-chip">Parts ${Math.max(issuedCost,0).toFixed(2)} · Vendors ${vendorCost.toFixed(2)}</span></div>
    <div className="wo-resource-grid">
      <section className="profile-panel">
        <div className="section-heading small-heading"><div><span className="eyebrow">Inventory</span><h3>Parts used</h3></div><span className="count-chip">{transactions.length}</span></div>
        {transactions.length===0?<div className="empty-table compact">No parts linked to this work order.</div>:<div className="profile-list">{transactions.map(t=>{const p=part(t.part_id);return <div className="profile-list-row static-row" key={t.id}><span><strong>{p?.part_number||'Part'} — {p?.description||''}</strong><small>{t.transaction_type} · {Math.abs(Number(t.quantity))} {p?.unit_of_measure||''} · {location(t.location_id)?.name||'Location'} · ${Number(t.unit_cost||0).toFixed(2)}/unit</small></span><b>{t.transaction_type==='return'?'-':'$'}{(Math.abs(Number(t.quantity))*Number(t.unit_cost||0)).toFixed(2)}</b></div>})}</div>}
        {canManage&&<form className="resource-form" onSubmit={savePart}>
          <label>Movement<select value={partForm.transaction_type} onChange={e=>setPartForm({...partForm,transaction_type:e.target.value})}><option value="issue">Issue to WO</option><option value="return">Return from WO</option></select></label>
          <label>Part<select required value={partForm.part_id} onChange={e=>{const p=part(e.target.value);setPartForm({...partForm,part_id:e.target.value,unit_cost:p?.standard_cost?.toString()||''})}}><option value="">Select part</option>{parts.map(p=><option key={p.id} value={p.id}>{p.part_number} — {p.description}</option>)}</select></label>
          <label>Location<select required value={partForm.location_id} onChange={e=>setPartForm({...partForm,location_id:e.target.value})}><option value="">Select location</option>{locations.map(l=><option key={l.id} value={l.id}>{l.name}{partForm.part_id?` — ${onHand(partForm.part_id,l.id).toFixed(2)} on hand`:''}</option>)}</select></label>
          <label>Quantity<input required type="number" min="0.01" step="0.01" value={partForm.quantity} onChange={e=>setPartForm({...partForm,quantity:e.target.value})}/></label>
          <label>Unit cost CAD<input type="number" min="0" step="0.01" value={partForm.unit_cost} onChange={e=>setPartForm({...partForm,unit_cost:e.target.value})}/></label>
          <label>Reference<input value={partForm.reference} onChange={e=>setPartForm({...partForm,reference:e.target.value})} placeholder="PO / invoice / slip"/></label>
          <label className="span-2">Notes<input value={partForm.notes} onChange={e=>setPartForm({...partForm,notes:e.target.value})}/></label>
          <button className="primary-button action-button" disabled={saving}>{saving?'Saving…':'Record part movement'}</button>
        </form>}
      </section>

      <section className="profile-panel">
        <div className="section-heading small-heading"><div><span className="eyebrow">External service</span><h3>Vendors</h3></div><span className="count-chip">{linkedVendors.length}</span></div>
        {linkedVendors.length===0?<div className="empty-table compact">No vendor linked to this work order.</div>:<div className="profile-list">{linkedVendors.map(v=>{const x=vendor(v.vendor_id);return <button type="button" className="profile-list-row" key={v.vendor_id} onClick={()=>editVendor(v)}><span><strong>{x?.name||'Vendor'}</strong><small>{x?.contact_name||x?.email||x?.phone||'Contact not recorded'} · quoted ${Number(v.quoted_amount||0).toFixed(2)} · invoiced ${Number(v.invoiced_amount||0).toFixed(2)}</small></span><b>Edit →</b></button>})}</div>}
        {canManage&&<form className="resource-form" onSubmit={saveVendor}>
          <label className="span-2">Vendor<select required value={vendorForm.vendor_id} onChange={e=>setVendorForm({...vendorForm,vendor_id:e.target.value})}><option value="">Select vendor</option>{vendors.map(v=><option key={v.id} value={v.id}>{v.name}</option>)}</select></label>
          <label>Quoted CAD<input type="number" min="0" step="0.01" value={vendorForm.quoted_amount} onChange={e=>setVendorForm({...vendorForm,quoted_amount:e.target.value})}/></label>
          <label>Invoiced CAD<input type="number" min="0" step="0.01" value={vendorForm.invoiced_amount} onChange={e=>setVendorForm({...vendorForm,invoiced_amount:e.target.value})}/></label>
          <label>Response hours<input type="number" min="0" step="0.1" value={vendorForm.response_hours} onChange={e=>setVendorForm({...vendorForm,response_hours:e.target.value})}/></label>
          <label>Completion rating<input type="number" min="0" max="5" step="0.1" value={vendorForm.completion_rating} onChange={e=>setVendorForm({...vendorForm,completion_rating:e.target.value})}/></label>
          <label className="span-2">Notes<input value={vendorForm.notes} onChange={e=>setVendorForm({...vendorForm,notes:e.target.value})}/></label>
          <button className="primary-button action-button" disabled={saving}>{saving?'Saving…':'Save vendor'}</button>
        </form>}
      </section>
    </div>
  </div>
}
