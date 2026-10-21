export type ReferencePhoto={id:string;part_id:string;url:string;part_number:string;description:string;caption:string}
export type PhotoMatch={photo_id:string;similarity:'high'|'medium'|'low';reason:string;observed_markings:string}
export function validPhotoData(value:unknown):value is string{
 if(typeof value!=='string'||value.length>7_000_000)return false
 const match=value.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+={0,2})$/);if(!match)return false
 try{const bytes=atob(match[2].slice(0,48));return match[1]==='jpeg'?bytes.charCodeAt(0)===255&&bytes.charCodeAt(1)===216:match[1]==='png'?bytes.startsWith('\x89PNG\r\n\x1a\n'):bytes.startsWith('RIFF')&&bytes.slice(8,12)==='WEBP'}catch{return false}
}
export function safePhotoMatches(raw:unknown,references:ReferencePhoto[]):PhotoMatch[]{
 const value=raw as any;const allowed=new Set(references.map(p=>p.id));const seen=new Set<string>();const result:PhotoMatch[]=[]
 for(const m of Array.isArray(value?.matches)?value.matches:[]){if(typeof m?.photo_id!=='string'||!allowed.has(m.photo_id)||seen.has(m.photo_id)||!['high','medium','low'].includes(m.similarity)||typeof m.reason!=='string')continue;seen.add(m.photo_id);result.push({photo_id:m.photo_id,similarity:m.similarity,reason:m.reason.slice(0,500),observed_markings:typeof m.observed_markings==='string'?m.observed_markings.slice(0,200):''})}return result
}
export async function comparePhotoCatalogue(references:ReferencePhoto[],compare:(refs:ReferencePhoto[])=>Promise<unknown>):Promise<PhotoMatch[]>{
 if(!references.length)return []
 if(references.length>120)throw new Error('Choose an asset or enter a catalogue keyword to narrow the photo library before comparing.')
 const batches:ReferencePhoto[][]=[];for(let i=0;i<references.length;i+=8)batches.push(references.slice(i,i+8))
 const matches:PhotoMatch[]=[]
 for(let i=0;i<batches.length;i+=3){const results=await Promise.all(batches.slice(i,i+3).map(async batch=>safePhotoMatches(await compare(batch),batch)));results.forEach(r=>matches.push(...r))}
 const score={high:3,medium:2,low:1};const ranked=matches.filter(m=>m.similarity!=='low').sort((a,b)=>score[b.similarity]-score[a.similarity]);const top:ReferencePhoto[]=[];const parts=new Set<string>()
 for(const m of ranked){const ref=references.find(p=>p.id===m.photo_id)!;if(!parts.has(ref.part_id)){parts.add(ref.part_id);top.push(ref)}if(top.length===8)break}
 if(!top.length)return []
 const final=top.length>1?safePhotoMatches(await compare(top),top):ranked.filter(m=>m.photo_id===top[0].id)
 return final.filter(m=>m.similarity!=='low').slice(0,5)
}
