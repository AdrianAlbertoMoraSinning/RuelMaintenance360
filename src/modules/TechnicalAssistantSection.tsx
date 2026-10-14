import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'
import './asset-profile.css'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string;asset_category:string;manufacturer:string|null;model:string|null}
type DocumentRow={id:string;asset_id:string|null;business_unit_id:string|null;title:string;document_type:string;version:string|null;manufacturer:string|null;storage_path:string}
type Chunk={id:string;document_id:string;page_number:number|null;section_title:string|null;content:string}
type WorkOrder={id:string;asset_id:string;work_order_number:number;title:string;problem_description:string|null;diagnosis:string|null;corrective_action:string|null;status:string;created_at:string}
type Props={units:BusinessUnit[];userId:string}

export default function TechnicalAssistantSection({units,userId}:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [documents,setDocuments]=useState<DocumentRow[]>([])
  const [orders,setOrders]=useState<WorkOrder[]>([])
  const [assetId,setAssetId]=useState('')
  const [question,setQuestion]=useState('')
  const [chunks,setChunks]=useState<Chunk[]>([])
  const [searched,setSearched]=useState(false)
  const [loading,setLoading]=useState(true)
  const [searching,setSearching]=useState(false)
  const [message,setMessage]=useState('')

  useEffect(()=>{async function load(){setLoading(true);const [{data:a},{data:d},{data:w}]=await Promise.all([
    supabase.from('assets').select('id,business_unit_id,asset_code,name,asset_category,manufacturer,model').order('asset_code'),
    supabase.from('documents').select('id,asset_id,business_unit_id,title,document_type,version,manufacturer,storage_path').eq('active',true),
    supabase.from('work_orders').select('id,asset_id,work_order_number,title,problem_description,diagnosis,corrective_action,status,created_at').order('created_at',{ascending:false}).limit(500)
  ]);setAssets((a||[]) as Asset[]);setDocuments((d||[]) as DocumentRow[]);setOrders((w||[]) as WorkOrder[]);setLoading(false)}load()},[])

  const selected=assets.find(a=>a.id===assetId)||null
  const assetDocuments=useMemo(()=>documents.filter(d=>d.asset_id===assetId||(!d.asset_id&&d.business_unit_id===selected?.business_unit_id)),[documents,assetId,selected?.business_unit_id])
  const assetOrders=useMemo(()=>orders.filter(w=>w.asset_id===assetId),[orders,assetId])

  async function search(e:FormEvent){
    e.preventDefault();if(!assetId||!question.trim())return
    setSearching(true);setMessage('');setSearched(true)
    const docIds=assetDocuments.map(d=>d.id)
    let found:Chunk[]=[]
    if(docIds.length){
      const terms=question.trim().split(/\s+/).filter(x=>x.length>2).slice(0,5)
      const query=terms.length?terms.join(' '):question.trim()
      const {data,error}=await supabase.from('document_chunks').select('id,document_id,page_number,section_title,content').in('document_id',docIds).textSearch('content',query,{type:'websearch',config:'english'}).limit(20)
      if(error){
        const fallback=await supabase.from('document_chunks').select('id,document_id,page_number,section_title,content').in('document_id',docIds).ilike('content',`%${question.trim().slice(0,80)}%`).limit(20)
        found=(fallback.data||[]) as Chunk[]
      }else found=(data||[]) as Chunk[]
    }
    setChunks(found)
    await supabase.from('technical_assistant_queries').insert({user_id:userId,asset_id:assetId,question:question.trim(),evidence_count:found.length})
    setSearching(false)
  }

  function docTitle(id:string){const d=documents.find(x=>x.id===id);return d?.title||'Indexed document'}
  function orderMatches(w:WorkOrder){const q=question.toLowerCase().split(/\s+/).filter(x=>x.length>2);if(!q.length)return false;const text=`${w.title} ${w.problem_description||''} ${w.diagnosis||''} ${w.corrective_action||''}`.toLowerCase();return q.some(t=>text.includes(t))}
  const matchingOrders=searched?assetOrders.filter(orderMatches).slice(0,10):[]

  async function openDocument(documentId:string){const d=documents.find(x=>x.id===documentId);if(!d)return;const {data,error}=await supabase.storage.from('ruel-documents').createSignedUrl(d.storage_path,120);if(error||!data?.signedUrl){setMessage(error?.message||'Unable to open source document.');return}window.open(data.signedUrl,'_blank','noopener,noreferrer')}
  function unitName(id:string){return units.find(u=>u.id===id)?.name||'Assigned unit'}

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Grounded Technical Intelligence</span><h1>Technical Assistant</h1><p className="muted">Search approved manuals and actual maintenance history by asset. Evidence is shown before any future AI-generated recommendation.</p></div></div>
    <div className="warning-box"><strong>Safety boundary</strong><p>This workspace does not authorize repairs, override lockout/tagout, or declare equipment safe. Follow OEM procedures, RUEL safety rules and qualified-person requirements.</p></div>
    {message&&<div className="error-box">{message}</div>}
    <form className="data-form assistant-query" onSubmit={search}>
      <div className="form-grid">
        <label>Asset<select required value={assetId} onChange={e=>{setAssetId(e.target.value);setSearched(false);setChunks([])}}><option value="">Select asset</option>{assets.map(a=><option key={a.id} value={a.id}>{a.asset_code} — {a.name}</option>)}</select></label>
        <label className="span-2">Technical question<input required value={question} onChange={e=>setQuestion(e.target.value)} placeholder="e.g. hydraulic pressure fault, recurring drum issue, service interval..."/></label>
      </div>
      <div className="form-actions"><button className="primary-button action-button" disabled={searching||loading}>{searching?'Searching evidence…':'Search approved evidence'}</button></div>
    </form>
    {selected&&<div className="summary-strip"><span><b>{selected.asset_code}</b> {selected.name}</span><span>{unitName(selected.business_unit_id)} · {selected.asset_category.replaceAll('_',' ')} · {[selected.manufacturer,selected.model].filter(Boolean).join(' ')||'technical details pending'}</span></div>}
    {selected&&<div className="assistant-source-grid">
      <article className="stat-card"><span>Linked / unit documents</span><strong>{assetDocuments.length}</strong><small>Approved records available to this asset context</small></article>
      <article className="stat-card"><span>Maintenance history</span><strong>{assetOrders.length}</strong><small>Work orders available for recurrence and repair context</small></article>
      <article className="stat-card"><span>Indexed evidence hits</span><strong>{searched?chunks.length:'—'}</strong><small>Document chunks matching the current question</small></article>
    </div>}
    {searched&&<div className="assistant-evidence-grid">
      <section className="profile-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Manual evidence</span><h3>Indexed excerpts</h3></div><span className="count-chip">{chunks.length}</span></div>{chunks.length===0?<div className="empty-table compact">No indexed manual excerpt matched this question yet. The document library may still require text indexing.</div>:<div className="profile-list">{chunks.map(c=><button className="profile-list-row evidence-row" key={c.id} onClick={()=>openDocument(c.document_id)}><span><strong>{docTitle(c.document_id)}</strong><small>{c.section_title||'Section not tagged'}{c.page_number?` · page ${c.page_number}`:''}</small><p>{c.content.slice(0,420)}{c.content.length>420?'…':''}</p></span><b>Source →</b></button>)}</div>}</section>
      <section className="profile-panel"><div className="section-heading small-heading"><div><span className="eyebrow">RUEL history</span><h3>Related work orders</h3></div><span className="count-chip">{matchingOrders.length}</span></div>{matchingOrders.length===0?<div className="empty-table compact">No prior work order text matched the current question.</div>:<div className="timeline">{matchingOrders.map(w=><div className="timeline-item" key={w.id}><span className="timeline-type work_order">WO #{w.work_order_number}</span><div><strong>{w.title}</strong><small>{new Date(w.created_at).toLocaleDateString()} · {w.status.replaceAll('_',' ')}</small>{w.diagnosis&&<p><b>Diagnosis:</b> {w.diagnosis}</p>}{w.corrective_action&&<p><b>Action:</b> {w.corrective_action}</p>}{!w.diagnosis&&!w.corrective_action&&w.problem_description&&<p>{w.problem_description}</p>}</div></div>)}</div>}</section>
    </div>}
    <div className="phase-banner">RAG foundation active: asset context, controlled documents, searchable document chunks, work-order history and query audit are connected. Automated document extraction/indexing and the final cited AI answer layer are the next integration step.</div>
  </div>
}
