import {useEffect,useRef,useState} from 'react'
import {supabase} from '../lib/supabase'
type Evidence={id:string;storage_path:string;file_name:string;mime_type:string;caption:string|null}
type Item=Evidence&{url:string|null}
export default function ObservationEvidence({observationId,userId}:{observationId:string;userId:string}){
 const[items,setItems]=useState<Item[]>([]),[busy,setBusy]=useState(true),[error,setError]=useState(''),[failed,setFailed]=useState<string[]>([])
 const epoch=useRef(0)
 async function load(){
  const run=++epoch.current;setBusy(true);setError('');setFailed([])
  try{
   const{data,error:failure}=await supabase.from('field_observation_evidence').select('id,storage_path,file_name,mime_type,caption').eq('observation_id',observationId).order('created_at')
   if(failure)throw failure
   const rows=await Promise.all(((data||[]) as Evidence[]).map(async row=>{try{const{data:signed,error:problem}=await supabase.storage.from('ruel-observation-evidence').createSignedUrl(row.storage_path,900);return {...row,url:problem?null:signed?.signedUrl||null}}catch{return {...row,url:null}}}))
   if(run!==epoch.current)return
   setItems(rows);if(rows.some(row=>!row.url))setError('Some attachments could not be opened. Refresh photos to try again.')
  }catch(e){if(run===epoch.current)setError((e as {message?:string}).message||'Unable to load the attachments. Refresh photos to try again.')}
  finally{if(run===epoch.current)setBusy(false)}
 }
 useEffect(()=>{setItems([]);void load();return()=>{epoch.current++}},[observationId,userId])
 return <section className="observation-evidence" aria-label="Observation photos and attachments"><div className="section-heading small-heading"><h3>Photos & attachments</h3><button type="button" className="secondary-outline" disabled={busy} onClick={()=>void load()}>{busy?'Loading…':'Refresh photos'}</button></div>{error&&<p className="warning-box" role="status">{error}</p>}{!busy&&!error&&!items.length&&<p className="field-help">No attachments have reached the server for this report. If photos are queued on the reporting phone, open Field Observations there and tap Sync now.</p>}<ObservationEvidenceGallery items={items} failed={failed} onImageError={id=>setFailed(v=>[...v,id])}/></section>
}

export function ObservationEvidenceGallery({items,failed,onImageError}:{items:Item[];failed:string[];onImageError:(id:string)=>void}){return <div className="observation-evidence-grid">{items.map(item=><figure key={item.id}>{item.url&&!failed.includes(item.id)?<>{item.mime_type.startsWith('image/')&&<a href={item.url} target="_blank" rel="noopener noreferrer"><img src={item.url} alt={item.caption||'Observation photo'} onError={()=>onImageError(item.id)}/></a>}<a href={item.url} target="_blank" rel="noopener noreferrer">{item.mime_type.startsWith('image/')?'Open full photo':`Open ${item.file_name}`}</a></>:<p role="status">Attachment unavailable. Tap Refresh photos to retry.</p>}{item.caption&&<figcaption>{item.caption}</figcaption>}</figure>)}</div>}
