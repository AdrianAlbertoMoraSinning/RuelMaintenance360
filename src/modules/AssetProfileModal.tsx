import AssetComponents from './AssetComponents'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import PersonAvatar from '../components/PersonAvatar'
import './asset-profile.css'

type Asset={
  id:string;business_unit_id:string;asset_code:string;name:string;asset_category:string;
  manufacturer:string|null;model:string|null;serial_number:string|null;year:number|null;
  status:string;criticality:number;odometer_km:number|null;hour_meter:number|null;notes:string|null
}
type Person={id:string;full_name:string|null;email:string|null;position_title:string|null;role:string;avatar_url:string|null}
type Assignment={id:string;user_id:string;responsibility:string;starts_on:string;ends_on:string|null;active:boolean}
type HistoryRow={asset_id:string;event_at:string;event_type:string;title:string;detail:string;source_id:string}
type DocumentRow={id:string;title:string;document_type:string;storage_path:string;version:string|null;manufacturer:string|null;effective_date:string|null;created_at:string}
type Props={asset:Asset;role:string;onClose:()=>void}

const teamRoles=['operator','manager','technician','inspector']

export default function AssetProfileModal({asset,role,onClose}:Props){
  const [people,setPeople]=useState<Person[]>([])
  const [assignments,setAssignments]=useState<Assignment[]>([])
  const [history,setHistory]=useState<HistoryRow[]>([])
  const [documents,setDocuments]=useState<DocumentRow[]>([])
  const [loading,setLoading]=useState(true)
  const [personId,setPersonId]=useState('')
  const [responsibility,setResponsibility]=useState('operator')
  const [message,setMessage]=useState('')
  const canAssign=['super_admin','corporate_manager','unit_supervisor'].includes(role)

  async function load(){
    setLoading(true)
    const [{data:p},{data:a},{data:h},{data:d}]=await Promise.all([
      supabase.from('profiles').select('id,full_name,email,position_title,role,avatar_url').eq('active',true).order('full_name'),
      supabase.from('asset_assignments').select('id,user_id,responsibility,starts_on,ends_on,active').eq('asset_id',asset.id).order('created_at',{ascending:false}),
      supabase.from('asset_history').select('asset_id,event_at,event_type,title,detail,source_id').eq('asset_id',asset.id).order('event_at',{ascending:false}).limit(100),
      supabase.from('documents').select('id,title,document_type,storage_path,version,manufacturer,effective_date,created_at').eq('asset_id',asset.id).eq('active',true).order('created_at',{ascending:false})
    ])
    setPeople((p||[]) as Person[]);setAssignments((a||[]) as Assignment[]);setHistory((h||[]) as HistoryRow[]);setDocuments((d||[]) as DocumentRow[]);setLoading(false)
  }
  useEffect(()=>{load()},[asset.id])

  function personFor(id:string){return people.find(x=>x.id===id)||null}
  function personName(id:string){const p=personFor(id);return p?.full_name||p?.email||'Assigned user'}
  const activeAssignments=useMemo(()=>assignments.filter(a=>a.active),[assignments])
  const primary=activeAssignments.find(a=>a.responsibility==='primary')
  const primaryPerson=primary?personFor(primary.user_id):null

  async function addAssignment(e:FormEvent){
    e.preventDefault();if(!canAssign||!personId)return
    setMessage('')
    const duplicate=activeAssignments.find(a=>a.user_id===personId&&a.responsibility===responsibility)
    if(duplicate){setMessage('That active responsibility already exists.');return}
    const {error}=await supabase.from('asset_assignments').insert({asset_id:asset.id,user_id:personId,responsibility,active:true})
    if(error)setMessage(error.message);else{setMessage('Asset team responsibility added.');setPersonId('');await load()}
  }

  async function endAssignment(row:Assignment){
    if(!canAssign||row.responsibility==='primary')return
    const {error}=await supabase.from('asset_assignments').update({active:false,ends_on:new Date().toISOString().slice(0,10)}).eq('id',row.id)
    if(error)setMessage(error.message);else{setMessage('Responsibility ended.');await load()}
  }

  async function openDocument(row:DocumentRow){
    const {data,error}=await supabase.storage.from('ruel-documents').createSignedUrl(row.storage_path,120)
    if(error||!data?.signedUrl){setMessage(error?.message||'Unable to open document.');return}
    window.open(data.signedUrl,'_blank','noopener,noreferrer')
  }

  return <div className="modal-backdrop asset-profile-backdrop" onClick={onClose}>
    <section className="asset-profile-card" onClick={e=>e.stopPropagation()}>
      <div className="form-title"><div><span className="eyebrow">Asset dossier</span><h2>{asset.asset_code} — {asset.name}</h2><p className="muted">Technical identity, accountability, controlled documents and maintenance history in one place.</p></div><button className="icon-button" onClick={onClose}>×</button></div>
      <div className="asset-owner-banner"><PersonAvatar avatarPath={primaryPerson?.avatar_url} name={primaryPerson?.full_name||primaryPerson?.email||'Unassigned'} size="lg"/><div><span className="eyebrow">Primary responsible</span><h3>{primaryPerson?personName(primaryPerson.id):'Unassigned'}</h3><p>{primaryPerson?.position_title||'Assign a responsible person for maintenance accountability.'}</p></div></div>
      <div className="asset-profile-summary">
        <span><small>Category</small><b>{asset.asset_category.replaceAll('_',' ')}</b></span>
        <span><small>Manufacturer / model</small><b>{[asset.manufacturer,asset.model].filter(Boolean).join(' · ')||'Pending'}</b></span>
        <span><small>Serial / VIN</small><b>{asset.serial_number||'Pending'}</b></span>
        <span><small>Criticality</small><b>C{asset.criticality}</b></span>
        <span><small>Hours</small><b>{asset.hour_meter??'—'}</b></span>
        <span><small>Odometer</small><b>{asset.odometer_km!=null?`${asset.odometer_km} km`:'—'}</b></span>
      </div>
      {message&&<div className={message.includes('added')||message.includes('ended')?'success-box':'error-box'}>{message}</div>}
      {loading?<div className="loading-panel">Loading asset dossier…</div>:<div className="asset-profile-grid">
        <div className="profile-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Accountability</span><h3>Asset team</h3></div><span className="count-chip">{activeAssignments.length} active</span></div>
          <div className="access-list">{activeAssignments.length===0?<div className="empty-table compact">No active asset responsibilities.</div>:activeAssignments.map(a=>{const p=personFor(a.user_id);return <div className="access-card" key={a.id}><div className="person-cell"><PersonAvatar avatarPath={p?.avatar_url} name={p?.full_name||p?.email} size="sm"/><span><strong>{personName(a.user_id)}</strong><small>{a.responsibility.replaceAll('_',' ')} · since {a.starts_on}</small></span></div>{canAssign&&a.responsibility!=='primary'&&<button className="icon-button small" onClick={()=>endAssignment(a)}>×</button>}</div>})}</div>
          {canAssign&&<form className="access-form" onSubmit={addAssignment}><label>Person<select required value={personId} onChange={e=>setPersonId(e.target.value)}><option value="">Select person</option>{people.map(p=><option key={p.id} value={p.id}>{p.full_name||p.email} — {p.position_title||p.role.replaceAll('_',' ')}</option>)}</select></label><label>Responsibility<select value={responsibility} onChange={e=>setResponsibility(e.target.value)}>{teamRoles.map(r=><option key={r} value={r}>{r}</option>)}</select></label><button className="primary-button action-button">Add responsibility</button></form>}
        </div>

        <div className="profile-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Controlled records</span><h3>Documents</h3></div><span className="count-chip">{documents.length}</span></div>{documents.length===0?<div className="empty-table compact">No asset-specific documents uploaded yet.</div>:<div className="profile-list">{documents.map(d=><button className="profile-list-row" key={d.id} onClick={()=>openDocument(d)}><span><strong>{d.title}</strong><small>{d.document_type} · {d.version||'no revision'} · {d.manufacturer||'manufacturer n/a'}</small></span><b>Open →</b></button>)}</div>}</div>

        <AssetComponents assetId={asset.id} role={role}/><div className="profile-panel history-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Lifecycle record</span><h3>History</h3></div><span className="count-chip">{history.length} events</span></div>{history.length===0?<div className="empty-table compact">No maintenance history recorded yet.</div>:<div className="timeline">{history.map((h,i)=><div className="timeline-item" key={`${h.event_type}-${h.source_id}-${i}`}><span className={`timeline-type ${h.event_type}`}>{h.event_type.replaceAll('_',' ')}</span><div><strong>{h.title}</strong><small>{new Date(h.event_at).toLocaleString()}</small>{h.detail&&<p>{h.detail}</p>}</div></div>)}</div>}</div>
      </div>}
    </section>
  </div>
}
