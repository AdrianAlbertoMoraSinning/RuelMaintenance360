import { supabase } from './supabase'

type ControlledDocumentRef={id:string;title:string;storage_path:string;document_type?:string;version?:string|null;manufacturer?:string|null}

function addText(doc:Document,tag:string,text:string,className?:string){const el=doc.createElement(tag);el.textContent=text;if(className)el.className=className;doc.body.appendChild(el);return el}

export async function openControlledDocument(row:ControlledDocumentRef,onError?:(message:string)=>void){
  const popup=window.open('','_blank')
  if(!popup){onError?.('Browser blocked the document window. Allow pop-ups for RUEL Maintenance 360 and try again.');return}
  popup.opener=null
  popup.document.title=row.title
  popup.document.body.textContent='Loading controlled document…'
  if(row.storage_path.startsWith('moc-training/')){
    const{data,error}=await supabase.from('document_chunks').select('chunk_index,page_number,section_title,content').eq('document_id',row.id).order('chunk_index')
    if(error||!data?.length){popup.close();onError?.(error?.message||'No training preview content is available for this virtual document.');return}
    const d=popup.document;d.head.textContent='';d.body.textContent='';const style=d.createElement('style');style.textContent='body{font-family:Arial,sans-serif;max-width:900px;margin:0 auto;padding:36px;line-height:1.55;color:#181818}h1{margin-bottom:4px}.meta{color:#666;margin-bottom:24px}.banner{background:#fff5cc;border:1px solid #e1c14b;padding:14px 16px;margin:20px 0;border-radius:8px}.chunk{border-top:1px solid #ddd;padding:18px 0}.chunk small{display:block;color:#666;margin-bottom:8px;white-space:pre-wrap}.chunk p{white-space:pre-wrap;margin:0}';d.head.appendChild(style)
    addText(d,'h1',row.title);addText(d,'div',[row.document_type,row.manufacturer,row.version&&`Rev ${row.version}`].filter(Boolean).join(' · '),'meta');addText(d,'div','MOC TRAINING PREVIEW — simulated technical content for training only. It is not an OEM manual and must not be used as production repair authority.','banner')
    for(const c of data as any[]){const box=d.createElement('section');box.className='chunk';const meta=d.createElement('small');meta.textContent=[c.page_number?`Page ${c.page_number}`:null,c.section_title||null,`Chunk ${Number(c.chunk_index)+1}`].filter(Boolean).join(' · ');const p=d.createElement('p');p.textContent=String(c.content||'');box.append(meta,p);d.body.appendChild(box)}
    return
  }
  const{data,error}=await supabase.storage.from('ruel-documents').createSignedUrl(row.storage_path,120)
  if(error||!data?.signedUrl){popup.close();onError?.(error?.message||'Unable to open controlled document.');return}
  popup.location.replace(data.signedUrl)
}
