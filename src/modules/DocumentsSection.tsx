import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string}
type DocumentRow={id:string;business_unit_id:string|null;asset_id:string|null;title:string;document_type:string;storage_path:string;version:string|null;manufacturer:string|null;effective_date:string|null;created_at:string}
type Props={units:BusinessUnit[];userId:string;role:string}

const canUploadRoles=['super_admin','corporate_manager','unit_supervisor','technician']

export default function DocumentsSection({units,userId,role}:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [rows,setRows]=useState<DocumentRow[]>([])
  const [loading,setLoading]=useState(true)
  const [showForm,setShowForm]=useState(false)
  const [file,setFile]=useState<File|null>(null)
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')
  const [query,setQuery]=useState('')
  const [unitFilter,setUnitFilter]=useState('all')
  const [form,setForm]=useState({business_unit_id:'',asset_id:'',title:'',document_type:'OEM Manual',version:'',manufacturer:'',effective_date:''})
  const canUpload=canUploadRoles.includes(role)

  async function load(){
    setLoading(true)
    const [{data:a},{data:d}]=await Promise.all([
      supabase.from('assets').select('id,business_unit_id,asset_code,name').order('asset_code'),
      supabase.from('documents').select('id,business_unit_id,asset_id,title,document_type,storage_path,version,manufacturer,effective_date,created_at').eq('active',true).order('created_at',{ascending:false})
    ])
    setAssets((a||[]) as Asset[]);setRows((d||[]) as DocumentRow[]);setLoading(false)
  }
  useEffect(()=>{load()},[])

  const filteredAssets=useMemo(()=>assets.filter(a=>!form.business_unit_id||a.business_unit_id===form.business_unit_id),[assets,form.business_unit_id])
  const visible=useMemo(()=>rows.filter(r=>{
    const q=query.trim().toLowerCase()
    const unitOk=unitFilter==='all'||r.business_unit_id===unitFilter
    const text=`${r.title} ${r.document_type} ${r.version||''} ${r.manufacturer||''}`.toLowerCase()
    return unitOk&&(!q||text.includes(q))
  }),[rows,query,unitFilter])

  function assetLabel(id:string|null){const a=assets.find(x=>x.id===id);return a?`${a.asset_code} — ${a.name}`:'General / unit document'}
  function unitName(id:string|null){return units.find(u=>u.id===id)?.name||'Corporate'}

  async function upload(e:FormEvent){
    e.preventDefault();if(!file||!form.business_unit_id)return
    setSaving(true);setMessage('')
    const safe=file.name.replace(/[^a-zA-Z0-9._-]/g,'_')
    const storagePath=`${form.business_unit_id}/${form.asset_id||'general'}/${Date.now()}_${safe}`
    const {error:storageError}=await supabase.storage.from('ruel-documents').upload(storagePath,file,{upsert:false})
    if(storageError){setMessage(storageError.message);setSaving(false);return}
    const {error:metaError}=await supabase.from('documents').insert({
      business_unit_id:form.business_unit_id,asset_id:form.asset_id||null,title:form.title.trim(),document_type:form.document_type,
      storage_path:storagePath,version:form.version.trim()||null,manufacturer:form.manufacturer.trim()||null,effective_date:form.effective_date||null,uploaded_by:userId
    })
    if(metaError){setMessage(metaError.message)} else {
      setMessage('Document uploaded successfully.');setShowForm(false);setFile(null);setForm({business_unit_id:'',asset_id:'',title:'',document_type:'OEM Manual',version:'',manufacturer:'',effective_date:''});await load()
    }
    setSaving(false)
  }

  async function openDocument(row:DocumentRow){
    setMessage('')
    const {data,error}=await supabase.storage.from('ruel-documents').createSignedUrl(row.storage_path,120)
    if(error||!data?.signedUrl){setMessage(error?.message||'Unable to open document.');return}
    window.open(data.signedUrl,'_blank','noopener,noreferrer')
  }

  function fileChanged(e:ChangeEvent<HTMLInputElement>){setFile(e.target.files?.[0]||null)}

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Controlled Technical Library</span><h1>Documents & Manuals</h1><p className="muted">OEM manuals, procedures, certificates, drawings and technical references linked to the correct unit and asset.</p></div>{canUpload&&<button className="primary-button action-button" onClick={()=>setShowForm(!showForm)}>+ Upload document</button>}</div>
    {message&&<div className={message.includes('successfully')?'success-box':'error-box'}>{message}</div>}
    {showForm&&<form className="data-form" onSubmit={upload}>
      <div className="form-title"><div><span className="eyebrow">Controlled document</span><h2>Upload document</h2></div><button className="icon-button" type="button" onClick={()=>setShowForm(false)}>×</button></div>
      <div className="form-grid">
        <label>Business unit<select required value={form.business_unit_id} onChange={e=>setForm({...form,business_unit_id:e.target.value,asset_id:''})}><option value="">Select unit</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
        <label>Asset<select value={form.asset_id} onChange={e=>setForm({...form,asset_id:e.target.value})}><option value="">General / unit document</option>{filteredAssets.map(a=><option key={a.id} value={a.id}>{a.asset_code} — {a.name}</option>)}</select></label>
        <label>Document type<select value={form.document_type} onChange={e=>setForm({...form,document_type:e.target.value})}><option>OEM Manual</option><option>Service Procedure</option><option>Safety Procedure</option><option>Electrical Diagram</option><option>Hydraulic Diagram</option><option>Calibration Certificate</option><option>Inspection Certificate</option><option>Parts Manual</option><option>Other</option></select></label>
        <label>Title<input required value={form.title} onChange={e=>setForm({...form,title:e.target.value})}/></label>
        <label>Manufacturer<input value={form.manufacturer} onChange={e=>setForm({...form,manufacturer:e.target.value})}/></label>
        <label>Version / revision<input value={form.version} onChange={e=>setForm({...form,version:e.target.value})}/></label>
        <label>Effective date<input type="date" value={form.effective_date} onChange={e=>setForm({...form,effective_date:e.target.value})}/></label>
        <label className="span-2">File<input required type="file" onChange={fileChanged} accept=".pdf,.jpg,.jpeg,.png,.webp,.docx,.xlsx,.txt"/></label>
      </div>
      <div className="form-actions"><button type="button" className="secondary-outline" onClick={()=>setShowForm(false)}>Cancel</button><button className="primary-button action-button" disabled={saving}>{saving?'Uploading…':'Upload document'}</button></div>
    </form>}
    <div className="toolbar"><input className="search-input" placeholder="Search title, type, revision…" value={query} onChange={e=>setQuery(e.target.value)}/><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select><span className="count-chip">{visible.length} documents</span></div>
    {loading?<div className="loading-panel">Loading document library…</div>:visible.length===0?<div className="empty-table">No documents recorded for the current filter.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>Document</th><th>Unit</th><th>Asset</th><th>Type</th><th>Revision</th><th>Date</th><th></th></tr></thead><tbody>{visible.map(r=><tr key={r.id}><td><strong>{r.title}</strong><small>{r.manufacturer||'Manufacturer not specified'}</small></td><td>{unitName(r.business_unit_id)}</td><td>{assetLabel(r.asset_id)}</td><td>{r.document_type}</td><td>{r.version||'—'}</td><td>{r.effective_date||new Date(r.created_at).toLocaleDateString()}</td><td><button className="secondary-outline mini" onClick={()=>openDocument(r)}>Open</button></td></tr>)}</tbody></table></div>}
  </div>
}
