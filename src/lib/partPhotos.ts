import {supabase} from './supabase'
export const PART_PHOTO_BUCKET='ruel-part-photos'
export async function preparePartPhoto(file:File):Promise<Blob>{
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw new Error('Choose a JPEG, PNG or WebP photograph.')
 if(file.size>10*1024*1024)throw new Error('Choose a photograph smaller than 10 MB.')
 const url=URL.createObjectURL(file)
 try{const img=new Image();img.src=url;await img.decode();const ratio=Math.min(1,1600/Math.max(img.naturalWidth,img.naturalHeight));const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.naturalWidth*ratio));canvas.height=Math.max(1,Math.round(img.naturalHeight*ratio));const context=canvas.getContext('2d');if(!context)throw new Error('Unable to prepare photograph.');context.drawImage(img,0,0,canvas.width,canvas.height);return await new Promise<Blob>((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Unable to prepare photograph.')),'image/jpeg',0.86))}finally{URL.revokeObjectURL(url)}
}
export function imageDataUrl(blob:Blob):Promise<string>{return new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result));r.onerror=()=>reject(new Error('Unable to read photograph.'));r.readAsDataURL(blob)})}
export async function uploadPartPhoto(partId:string,file:File,caption=''){
 const blob=await preparePartPhoto(file);const{data:{user},error:authError}=await supabase.auth.getUser();if(authError||!user)throw new Error('Sign in before uploading photographs.')
 const path=partId+'/'+crypto.randomUUID()+'.jpg';const{error}=await supabase.storage.from(PART_PHOTO_BUCKET).upload(path,blob,{contentType:'image/jpeg',upsert:false});if(error)throw error
 const result=await supabase.from('part_photos').insert({part_id:partId,storage_path:path,caption:caption.trim().slice(0,500),uploaded_by:user.id})
 if(result.error){await supabase.storage.from(PART_PHOTO_BUCKET).remove([path]);throw result.error}
}
