import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from 'react'
import { GlobalWorkerOptions, getDocument } from 'pdfjs-dist'
import { createWorker, type Worker } from 'tesseract.js'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

GlobalWorkerOptions.workerSrc = new URL('pdfjs-dist/build/pdf.worker.min.mjs', import.meta.url).toString()

type Asset={id:string;business_unit_id:string;asset_code:string;name:string}
type DocumentRow={id:string;business_unit_id:string|null;asset_id:string|null;title:string;document_type:string;storage_path:string;version:string|null;manufacturer:string|null;effective_date:string|null;created_at:string;indexing_status:string;indexed_at:string|null;indexed_pages:number;indexing_error:string|null}
type Props={units:BusinessUnit[];userId:string;role:string}

const canUploadRoles=['super_admin','corporate_manager','unit_supervisor','technician']

function splitText(text:string,max=1800,overlap=180){
  const clean=text.replace(/\s+/g,' ').trim();if(!clean)return []
  const chunks:string[]=[];let start=0
  while(start<clean.length){let end=Math.min(clean.length,start+max);if(end<clean.length){const cut=clean.lastIndexOf(' ',end);if(cut>start+max*0.65)end=cut}chunks.push(clean.slice(start,end).trim());if(end>=clean.length)break;start=Math.max(end-overlap,start+1)}
  return chunks.filter(Boolean)
}

export default function DocumentsSection({units,userId,role}:Props){
  const [assets,setAssets]=useState<Asset[]>([])
  const [rows,setRows]=useState<DocumentRow[]>([])
  const [loading,setLoading]=useState(true)
  const [showForm,setShowForm]=useState(false)
  const [file,setFile]=useState<File|null>(null)
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')
  const [progress,setProgress]=useState('')
  const [query,setQuery]=useState('')
  const [unitFilter,setUnitFilter]=useState('all')
  const [form,setForm]=useState({business_unit_id:'',asset_id:'',title:'',document_type:'OEM Manual',version:'',manufacturer:'',effective_date:''})
  const canUpload=canUploadRoles.includes(role)

  async function load(){
    setLoading(true)
    const [{data:a},{data:d}]=await Promise.all([
      supabase.from('assets').select('id,business_unit_id,asset_code,name').order('asset_code'),
      supabase.from('documents').select('id,business_unit_id,asset_id,title,document_type,storage_path,version,manufacturer,effective_date,created_at,indexing_status,indexed_at,indexed_pages,indexing_error').eq('active',true).order('created_at',{ascending:false})
    ])
    setAssets((a||[]) as Asset[]);setRows((d||[]) as DocumentRow[]);setLoading(false)
  }
  useEffect(()=>{load()},[])

  const filteredAssets=useMemo(()=>assets.filter(a=>!form.business_unit_id||a.business_unit_id===form.business_unit_id),[assets,form.business_unit_id])
  const visible=useMemo(()=>rows.filter(r=>{
    const q=query.trim().toLowerCase();const unitOk=unitFilter==='all'||r.business_unit_id===unitFilter;const text=`${r.title} ${r.document_type} ${r.version||''} ${r.manufacturer||''} ${r.indexing_status}`.toLowerCase();return unitOk&&(!q||text.includes(q))
  }),[rows,query,unitFilter])

  function assetLabel(id:string|null){const a=assets.find(x=>x.id===id);return a?`${a.asset_code} — ${a.name}`:'General / unit document'}
  function unitName(id:string|null){return units.find(u=>u.id===id)?.name||'Corporate'}

  async function getOcrWorker(existing:Worker|null){return existing||await createWorker('eng')}

  async function indexDocument(documentId:string,sourceFile:File){
    const lower=sourceFile.name.toLowerCase();let chunkIndex=0;let pages=0;const inserts:any[]=[];let worker:Worker|null=null;let usedOcr=false
    try{
      setProgress('Preparing document…')
      await supabase.from('document_chunks').delete().eq('document_id',documentId)
      if(sourceFile.type==='text/plain'||lower.endsWith('.txt')){
        const text=await sourceFile.text();const chunks=splitText(text);chunks.forEach(content=>inserts.push({document_id:documentId,chunk_index:chunkIndex++,page_number:null,section_title:null,content,metadata:{source:'txt'}}));pages=chunks.length?1:0
      }else if(sourceFile.type==='application/pdf'||lower.endsWith('.pdf')){
        const pdf=await getDocument({data:new Uint8Array(await sourceFile.arrayBuffer())}).promise;pages=pdf.numPages
        for(let pageNo=1;pageNo<=pdf.numPages;pageNo++){
          setProgress(`Indexing page ${pageNo} of ${pdf.numPages}…`)
          const page=await pdf.getPage(pageNo);const textContent=await page.getTextContent();let text=textContent.items.map((item:any)=>typeof item.str==='string'?item.str:'').join(' ').replace(/\s+/g,' ').trim();let source='pdf_text'
          if(text.length<80){
            usedOcr=true;worker=await getOcrWorker(worker);setProgress(`OCR page ${pageNo} of ${pdf.numPages}…`)
            const viewport=page.getViewport({scale:1.8});const canvas=document.createElement('canvas');canvas.width=Math.ceil(viewport.width);canvas.height=Math.ceil(viewport.height);const ctx=canvas.getContext('2d');if(!ctx)throw new Error('Unable to create OCR canvas.')
            await page.render({canvasContext:ctx,viewport}).promise;const result=await worker.recognize(canvas);text=result.data.text.replace(/\s+/g,' ').trim();source='ocr_pdf'
          }
          splitText(text).forEach(content=>inserts.push({document_id:documentId,chunk_index:chunkIndex++,page_number:pageNo,section_title:null,content,metadata:{source,page:pageNo,ocr:source==='ocr_pdf'}}))
        }
      }else if(/^image\//.test(sourceFile.type)||/\.(jpe?g|png|webp)$/i.test(lower)){
        usedOcr=true;worker=await getOcrWorker(worker);setProgress('Running OCR on image…');const url=URL.createObjectURL(sourceFile)
        try{const result=await worker.recognize(url);const text=result.data.text.replace(/\s+/g,' ').trim();splitText(text).forEach(content=>inserts.push({document_id:documentId,chunk_index:chunkIndex++,page_number:1,section_title:null,content,metadata:{source:'ocr_image',page:1,ocr:true}}));pages=text?1:0}finally{URL.revokeObjectURL(url)}
      }else{
        await supabase.from('documents').update({indexing_status:'unsupported',indexing_error:'Automatic indexing supports PDF, TXT, JPG, PNG and WEBP. DOCX/XLSX remain controlled originals.'}).eq('id',documentId);return 'unsupported'
      }
      if(!inserts.length)throw new Error('No readable text was found. Try a clearer scan or higher-resolution source.')
      setProgress(`Saving ${inserts.length} searchable evidence chunk(s)…`)
      for(let i=0;i<inserts.length;i+=100){const {error}=await supabase.from('document_chunks').insert(inserts.slice(i,i+100));if(error)throw error}
      await supabase.from('documents').update({indexing_status:'indexed',indexed_at:new Date().toISOString(),indexed_pages:pages,indexing_error:null}).eq('id',documentId)
      return usedOcr?'ocr_indexed':'indexed'
    }catch(err){
      const text=err instanceof Error?err.message:'Indexing failed';await supabase.from('documents').update({indexing_status:'failed',indexing_error:text}).eq('id',documentId);return 'failed'
    }finally{if(worker)await worker.terminate();setProgress('')}
  }

  async function upload(e:FormEvent){
    e.preventDefault();if(!file||!form.business_unit_id)return
    setSaving(true);setMessage('')
    const safe=file.name.replace(/[^a-zA-Z0-9._-]/g,'_');const storagePath=`${form.business_unit_id}/${form.asset_id||'general'}/${Date.now()}_${safe}`
    const {error:storageError}=await supabase.storage.from('ruel-documents').upload(storagePath,file,{upsert:false})
    if(storageError){setMessage(storageError.message);setSaving(false);return}
    const {data:doc,error:metaError}=await supabase.from('documents').insert({business_unit_id:form.business_unit_id,asset_id:form.asset_id||null,title:form.title.trim(),document_type:form.document_type,storage_path:storagePath,version:form.version.trim()||null,manufacturer:form.manufacturer.trim()||null,effective_date:form.effective_date||null,uploaded_by:userId,indexing_status:'pending'}).select('id').single()
    if(metaError){setMessage(metaError.message)} else {
      const result=await indexDocument(doc.id,file)
      setMessage(result==='ocr_indexed'?'Document uploaded and OCR-indexed successfully.':result==='indexed'?'Document uploaded and indexed successfully.':result==='unsupported'?'Document uploaded as a controlled original. Automatic indexing is not supported for this file type.':'Document uploaded, but indexing failed. The original file is still available.')
      setShowForm(false);setFile(null);setForm({business_unit_id:'',asset_id:'',title:'',document_type:'OEM Manual',version:'',manufacturer:'',effective_date:''});await load()
    }
    setSaving(false)
  }

  async function retryIndex(row:DocumentRow){
    setSaving(true);setMessage('')
    try{
      const {data,error}=await supabase.storage.from('ruel-documents').download(row.storage_path);if(error||!data)throw error||new Error('Unable to download source file.')
      const filename=row.storage_path.split('/').pop()||'document.pdf';let mime=data.type;if(!mime){mime=filename.toLowerCase().endsWith('.pdf')?'application/pdf':/\.(jpe?g|png|webp)$/i.test(filename)?'image/jpeg':'text/plain'}
      const source=new File([data],filename,{type:mime});const result=await indexDocument(row.id,source);setMessage(result==='ocr_indexed'?'Document OCR-indexed successfully.':result==='indexed'?'Document indexed successfully.':result==='unsupported'?'Automatic indexing is not supported for this file type.':'Indexing failed.');await load()
    }catch(err){setMessage(err instanceof Error?err.message:'Unable to index document.')}
    setSaving(false)
  }

  async function openDocument(row:DocumentRow){setMessage('');const {data,error}=await supabase.storage.from('ruel-documents').createSignedUrl(row.storage_path,120);if(error||!data?.signedUrl){setMessage(error?.message||'Unable to open document.');return}window.open(data.signedUrl,'_blank','noopener,noreferrer')}
  function fileChanged(e:ChangeEvent<HTMLInputElement>){setFile(e.target.files?.[0]||null)}

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Controlled Technical Library</span><h1>Documents & Manuals</h1><p className="muted">OEM manuals, procedures, certificates and drawings linked to the correct unit and asset, with text extraction and OCR evidence for the Technical Assistant.</p></div>{canUpload&&<button className="primary-button action-button" onClick={()=>setShowForm(!showForm)}>+ Upload document</button>}</div>
    {message&&<div className={/successfully|controlled original/i.test(message)?'success-box':'error-box'}>{message}</div>}
    {progress&&<div className="phase-banner">{progress} Scanned manuals can take several minutes depending on page count.</div>}
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
        <label className="span-2">File<input required type="file" onChange={fileChanged} accept=".pdf,.jpg,.jpeg,.png,.webp,.docx,.xlsx,.txt"/><small className="field-help">PDF/TXT are indexed directly. Scanned PDF/JPG/PNG/WEBP automatically use OCR when readable text is not present.</small></label>
      </div>
      <div className="form-actions"><button type="button" className="secondary-outline" onClick={()=>setShowForm(false)}>Cancel</button><button className="primary-button action-button" disabled={saving}>{saving?'Uploading / indexing…':'Upload document'}</button></div>
    </form>}
    <div className="toolbar"><input className="search-input" placeholder="Search title, type, revision, indexing status…" value={query} onChange={e=>setQuery(e.target.value)}/><select value={unitFilter} onChange={e=>setUnitFilter(e.target.value)}><option value="all">All business units</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select><span className="count-chip">{visible.length} documents</span></div>
    {loading?<div className="loading-panel">Loading document library…</div>:visible.length===0?<div className="empty-table">No documents recorded for the current filter.</div>:<div className="table-wrap"><table className="data-table"><thead><tr><th>Document</th><th>Unit</th><th>Asset</th><th>Type</th><th>Revision</th><th>Indexing</th><th></th></tr></thead><tbody>{visible.map(r=><tr key={r.id}><td><strong>{r.title}</strong><small>{r.manufacturer||'Manufacturer not specified'}</small></td><td>{unitName(r.business_unit_id)}</td><td>{assetLabel(r.asset_id)}</td><td>{r.document_type}</td><td>{r.version||'—'}</td><td><span className={`status-pill ${r.indexing_status==='indexed'?'active':r.indexing_status==='failed'?'out_of_service':'standby'}`}>{r.indexing_status}</span><small>{r.indexing_status==='indexed'?`${r.indexed_pages} page(s) searchable`:r.indexing_error||'Awaiting processing'}</small></td><td><div className="row-actions"><button className="secondary-outline mini" onClick={()=>openDocument(r)}>Open</button>{canUpload&&r.indexing_status!=='indexed'&&<button className="secondary-outline mini" disabled={saving} onClick={()=>retryIndex(r)}>Index / OCR</button>}</div></td></tr>)}</tbody></table></div>}
    <div className="phase-banner">OCR is active for scanned PDFs and image documents. Searchable chunks retain document and page references so Technical Assistant answers can cite the controlled source.</div>
  </div>
}
