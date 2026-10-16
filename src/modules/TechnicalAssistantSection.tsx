import { FormEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { openControlledDocument } from '../lib/openControlledDocument'
import type { BusinessUnit } from './AssetsSection'
import './asset-profile.css'

type Asset={id:string;business_unit_id:string;asset_code:string;name:string;asset_category:string;manufacturer:string|null;model:string|null}
type DocumentRow={id:string;asset_id:string|null;business_unit_id:string|null;title:string;document_type:string;version:string|null;manufacturer:string|null;storage_path:string}
type Chunk={id:string;document_id:string;page_number:number|null;section_title:string|null;content:string}
type WorkOrder={id:string;asset_id:string;work_order_number:number;title:string;problem_description:string|null;diagnosis:string|null;corrective_action:string|null;status:string;created_at:string}
type Source={id:string;label:string;content:string;kind:'manual'|'work_order';documentId?:string}
type Props={units:BusinessUnit[];userId:string}

export default function TechnicalAssistantSection({units,userId}:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [documents,setDocuments]=useState<DocumentRow[]>([])
  const [orders,setOrders]=useState<WorkOrder[]>([])
  const [assetId,setAssetId]=useState('')
  const [question,setQuestion]=useState('')
  const [chunks,setChunks]=useState<Chunk[]>([])
  const [answer,setAnswer]=useState('')
  const [answerMode,setAnswerMode]=useState('')
  const [answerSources,setAnswerSources]=useState<Source[]>([])
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

  function docTitle(id:string){const d=documents.find(x=>x.id===id);return d?.title||'Indexed document'}
  function matchingWorkOrders(q:string){const terms=q.toLowerCase().split(/\s+/).map(x=>x.replace(/[^\p{L}\p{N}_-]/gu,'')).filter(x=>x.length>2);if(!terms.length)return [];return assetOrders.filter(w=>{const text=`${w.title} ${w.problem_description||''} ${w.diagnosis||''} ${w.corrective_action||''}`.toLowerCase();return terms.some(t=>text.includes(t))}).slice(0,6)}

  function buildSources(found:Chunk[],related:WorkOrder[]){
    const manual:Source[]=found.slice(0,8).map(c=>({id:`chunk:${c.id}`,kind:'manual',documentId:c.document_id,label:`${docTitle(c.document_id)}${c.page_number?` · page ${c.page_number}`:''}`,content:c.content}))
    const history:Source[]=related.slice(0,4).map(w=>({id:`wo:${w.id}`,kind:'work_order',label:`RUEL WO #${w.work_order_number} · ${w.title}`,content:[w.problem_description,w.diagnosis&&`Diagnosis: ${w.diagnosis}`,w.corrective_action&&`Action: ${w.corrective_action}`].filter(Boolean).join(' | ')}))
    return [...manual,...history]
  }

  function extractiveAnswer(sources:Source[]){
    if(!sources.length)return 'No approved manual evidence or related RUEL maintenance history was found for this question. Add or index the correct technical documents before relying on the assistant.'
    const manual=sources.filter(s=>s.kind==='manual').slice(0,3);const history=sources.filter(s=>s.kind==='work_order').slice(0,2)
    const lines=['Evidence found for this asset:']
    manual.forEach(s=>lines.push(`\n[S${sources.indexOf(s)+1}] ${s.content.slice(0,520)}${s.content.length>520?'…':''}`))
    if(history.length){lines.push('\nRUEL maintenance history:');history.forEach(s=>lines.push(`\n[S${sources.indexOf(s)+1}] ${s.content.slice(0,420)}${s.content.length>420?'…':''}`))}
    lines.push('\n\nThis is an evidence-first extractive answer. Review the cited source before performing work; follow OEM instructions, RUEL safety requirements and LOTO.')
    return lines.join('')
  }

  async function retrieveChunks(docIds:string[],q:string){
    if(!docIds.length)return [] as Chunk[]
    const {data,error}=await supabase.rpc('search_document_chunks_multilingual',{p_document_ids:docIds,p_query:q,p_limit:20})
    if(!error&&data?.length)return (data as any[]).map(x=>({id:x.id,document_id:x.document_id,page_number:x.page_number,section_title:x.section_title,content:x.content})) as Chunk[]
    const terms=q.toLowerCase().split(/\s+/).map(x=>x.replace(/[^\p{L}\p{N}_-]/gu,'')).filter(x=>x.length>2).slice(0,6)
    if(!terms.length)return []
    const or=terms.map(t=>`content.ilike.%${t}%`).join(',')
    const fallback=await supabase.from('document_chunks').select('id,document_id,page_number,section_title,content').in('document_id',docIds).or(or).limit(20)
    return (fallback.data||[]) as Chunk[]
  }

  async function search(e:FormEvent){
    e.preventDefault();if(!assetId||!question.trim()||!selected)return
    setSearching(true);setMessage('');setSearched(true);setAnswer('');setAnswerSources([])
    const docIds=assetDocuments.map(d=>d.id);const found=await retrieveChunks(docIds,question.trim())
    setChunks(found)
    const related=matchingWorkOrders(question);const sources=buildSources(found,related);setAnswerSources(sources)
    let finalAnswer=extractiveAnswer(sources);let mode='extractive_cited'
    if(sources.length){
      const {data,error}=await supabase.functions.invoke('technical-assistant-answer',{body:{question:question.trim(),asset:`${selected.asset_code} — ${selected.name}`,sources:sources.map(s=>({id:s.id,label:s.label,content:s.content}))}})
      if(!error&&data?.answer){finalAnswer=String(data.answer);mode=String(data.mode||'ai_cited')}
    }
    setAnswer(finalAnswer);setAnswerMode(mode)
    await supabase.from('technical_assistant_queries').insert({user_id:userId,asset_id:assetId,question:question.trim(),evidence_count:sources.length,answer_text:finalAnswer,answer_mode:mode,citations:sources.map((s,i)=>({marker:`S${i+1}`,id:s.id,label:s.label,kind:s.kind}))})
    setSearching(false)
  }

  const matchingOrders=searched?matchingWorkOrders(question):[]
  async function openDocument(documentId:string){const d=documents.find(x=>x.id===documentId);if(!d)return;setMessage('');await openControlledDocument(d,setMessage)}
  function unitName(id:string){return units.find(u=>u.id===id)?.name||'Assigned unit'}

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Grounded Technical Intelligence</span><h1>Technical Assistant</h1><p className="muted">Ask in English or Spanish by asset and receive a source-cited answer grounded in controlled manuals, OCR evidence and actual RUEL maintenance history.</p></div></div>
    <div className="warning-box"><strong>Safety boundary</strong><p>This workspace does not authorize repairs, override lockout/tagout, replace qualified-person judgment, or declare equipment safe. Follow OEM procedures and RUEL safety rules.</p></div>
    {message&&<div className="error-box">{message}</div>}
    <form className="data-form assistant-query" onSubmit={search}>
      <div className="form-grid">
        <label>Asset<select required value={assetId} onChange={e=>{setAssetId(e.target.value);setSearched(false);setChunks([]);setAnswer('');setAnswerSources([])}}><option value="">Select asset</option>{assets.map(a=><option key={a.id} value={a.id}>{a.asset_code} — {a.name}</option>)}</select></label>
        <label className="span-2">Technical question<input required value={question} onChange={e=>setQuestion(e.target.value)} placeholder="e.g. What does the OEM manual say about this hydraulic pressure fault? / ¿Qué indica el manual sobre esta falla?"/></label>
      </div>
      <div className="form-actions"><button className="primary-button action-button" disabled={searching||loading}>{searching?'Building cited answer…':'Ask Technical Assistant'}</button></div>
    </form>
    {selected&&<div className="summary-strip"><span><b>{selected.asset_code}</b> {selected.name}</span><span>{unitName(selected.business_unit_id)} · {selected.asset_category.replaceAll('_',' ')} · {[selected.manufacturer,selected.model].filter(Boolean).join(' ')||'technical details pending'}</span></div>}
    {selected&&<div className="assistant-source-grid"><article className="stat-card"><span>Linked / unit documents</span><strong>{assetDocuments.length}</strong><small>Approved records in this asset context</small></article><article className="stat-card"><span>Maintenance history</span><strong>{assetOrders.length}</strong><small>RUEL work orders available for context</small></article><article className="stat-card"><span>Evidence sources</span><strong>{searched?answerSources.length:'—'}</strong><small>Manual/OCR and history sources used</small></article></div>}
    {searched&&<>
      <section className="profile-panel assistant-answer-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Grounded answer</span><h3>Technical response</h3></div><span className="count-chip">{answerMode==='ai_cited'?'AI + citations':'Evidence extract + citations'}</span></div><div className="assistant-answer-text">{answer||'No answer available.'}</div><div className="assistant-citations"><strong>Sources used</strong>{answerSources.length===0?<p className="muted">No approved sources matched.</p>:answerSources.map((s,i)=><button key={s.id} className="citation-card" onClick={()=>s.documentId&&openDocument(s.documentId)} disabled={!s.documentId}><b>[S{i+1}]</b><span>{s.label}</span><small>{s.kind==='manual'?'Controlled technical document':'RUEL maintenance history'}</small></button>)}</div></section>
      <div className="assistant-evidence-grid">
        <section className="profile-panel"><div className="section-heading small-heading"><div><span className="eyebrow">Manual evidence</span><h3>Indexed excerpts</h3></div><span className="count-chip">{chunks.length}</span></div>{chunks.length===0?<div className="empty-table compact">No indexed manual excerpt matched this question.</div>:<div className="profile-list">{chunks.map(c=><button className="profile-list-row evidence-row" key={c.id} onClick={()=>openDocument(c.document_id)}><span><strong>{docTitle(c.document_id)}</strong><small>{c.section_title||'Indexed evidence'}{c.page_number?` · page ${c.page_number}`:''}</small><p>{c.content.slice(0,420)}{c.content.length>420?'…':''}</p></span><b>Source →</b></button>)}</div>}</section>
        <section className="profile-panel"><div className="section-heading small-heading"><div><span className="eyebrow">RUEL history</span><h3>Related work orders</h3></div><span className="count-chip">{matchingOrders.length}</span></div>{matchingOrders.length===0?<div className="empty-table compact">No prior work-order text matched the question.</div>:<div className="timeline">{matchingOrders.map(w=><div className="timeline-item" key={w.id}><span className="timeline-type work_order">WO #{w.work_order_number}</span><div><strong>{w.title}</strong><small>{new Date(w.created_at).toLocaleDateString()} · {w.status.replaceAll('_',' ')}</small>{w.diagnosis&&<p><b>Diagnosis:</b> {w.diagnosis}</p>}{w.corrective_action&&<p><b>Action:</b> {w.corrective_action}</p>}{!w.diagnosis&&!w.corrective_action&&w.problem_description&&<p>{w.problem_description}</p>}</div></div>)}</div>}</section>
      </div>
    </>}
    <div className="phase-banner">Retrieval uses a language-neutral indexed search for English/Spanish technical terms, with controlled virtual MOC previews when no storage object exists. The answer engine never answers from memory alone; if the external AI provider is not configured, it falls back to an extractive cited answer instead of inventing a response.</div>
  </div>
}
