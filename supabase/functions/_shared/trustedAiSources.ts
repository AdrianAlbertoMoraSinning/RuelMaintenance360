type Source={id:string;label:string;content:string;documentId?:string}
export async function trustedAiSources(caller:any,asset:{id:string;business_unit_id:string},question:string,requested:Source[]):Promise<Source[]>{
 const ids=(prefix:string)=>requested.map(s=>s.id||'').filter(s=>s.startsWith(prefix)&&/^[a-f0-9-]{36}$/i.test(s.slice(prefix.length))).map(s=>s.slice(prefix.length)).slice(0,12)
 const sources:Source[]=[]
 const chunkIds=ids('chunk:')
 if(chunkIds.length){
  const{data:docs,error:docError}=await caller.from('documents').select('id,title,metadata').eq('active',true).or(`asset_id.eq.${asset.id},and(asset_id.is.null,business_unit_id.eq.${asset.business_unit_id})`)
  if(docError)throw new Error('Unable to verify document access')
  const approved=(docs||[]).filter((d:any)=>!d.metadata?.training&&!d.metadata?.mock_only)
  if(approved.length){const{data:chunks,error}=await caller.from('document_chunks').select('id,document_id,content,page_number').in('id',chunkIds).in('document_id',approved.map((d:any)=>d.id));if(error)throw new Error('Unable to retrieve approved documents');for(const c of (chunks||[]).slice(0,6)){const doc=approved.find((d:any)=>d.id===c.document_id);sources.push({id:'chunk:'+c.id,documentId:c.document_id,label:doc.title+(c.page_number?' · page '+c.page_number:''),content:c.content})}}
 }
 const{data:observations,error:obsError}=await caller.rpc('search_observation_ai_memory',{p_asset_id:asset.id,p_query:question,p_limit:4})
 if(obsError)throw new Error('Unable to verify supervisor-accepted observation memory')
 const woIds=ids('wo:')
 if(woIds.length){
  const{data:orders,error}=await caller.from('work_orders_visible').select('id,work_order_number,title,problem_description,diagnosis,corrective_action,source_observation_id').eq('asset_id',asset.id).in('id',woIds)
  if(error)throw new Error('Unable to verify maintenance history')
  const linked=(orders||[]).map((w:any)=>w.source_observation_id).filter(Boolean)
  let accepted=new Set<string>()
  if(linked.length){const{data,error}=await caller.from('observation_ai_memory').select('observation_id').in('observation_id',linked);if(error)throw new Error('Unable to verify source observation acceptance');accepted=new Set((data||[]).map((r:any)=>r.observation_id))}
  for(const w of (orders||[]).filter((w:any)=>!/^\s*\[(MOC|MOCK|QA)/i.test(w.title)&&(!w.source_observation_id||accepted.has(w.source_observation_id))).slice(0,2))sources.push({id:'wo:'+w.id,label:'RUEL WO #'+w.work_order_number+' · '+w.title,content:[w.problem_description,w.diagnosis&&'Recorded diagnosis: '+w.diagnosis,w.corrective_action&&'Recorded action: '+w.corrective_action].filter(Boolean).join(' | ')})
 }
 for(const o of observations||[])sources.push({id:'obs:'+o.observation_id,label:'Supervisor-accepted OBS-'+o.observation_number+' · '+o.accepted_at,content:['Reviewed report: '+o.description,'Supervisor acceptance note: '+o.acceptance_note,o.resolution_notes&&'Reviewed resolution note: '+o.resolution_notes].filter(Boolean).join(' | ')})
 return sources.slice(0,12)
}
