import {createClient} from '@supabase/supabase-js'
import {validPhotoData} from '../supabase/functions/_shared/partPhotoMatching.ts'
import {engineHealth,extractFeatures,compareFeatures,usableQuery} from './localPhotoEngine.mjs'
const PROJECT_URL='https://hnqesskokhygtrjyhttb.supabase.co'
const PUBLIC_KEY='sb_publishable_VgOf2QDrKRHMdlnxLBb__A_4_pNpSXa'
const cache=new Map(),headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'https://ruelmaintenance360.netlify.app','Access-Control-Allow-Headers':'authorization, content-type','Access-Control-Allow-Methods':'GET, POST, OPTIONS'}
function reply(data,status=200){return new Response(JSON.stringify(data),{status,headers})}
class RequestFailure extends Error{constructor(message,status=400){super(message);this.status=status}}
function callerClient(token){return createClient(process.env.VITE_SUPABASE_URL||PROJECT_URL,process.env.VITE_SUPABASE_PUBLISHABLE_KEY||PUBLIC_KEY,{global:{headers:{Authorization:token},fetch:(url,options)=>fetch(url,{...options,signal:AbortSignal.timeout(10000)})},auth:{persistSession:false,autoRefreshToken:false}})}
export function createPhotoHandler({makeClient=callerClient,engine={engineHealth,extractFeatures,compareFeatures,usableQuery},featureCache=cache}={}){return async function handler(req){
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers})
 try{
 if(req.method==='GET')return reply({...await engine.engineHealth(),requires_auth:true})
 if(req.method!=='POST')return reply({error:'POST required'},405)
 const token=req.headers.get('authorization')||'';if(!/^Bearer\s+\S+$/i.test(token))return reply({error:'Sign in to compare catalogue photographs'},401)
 const client=makeClient(token),identity=await client.auth.getUser();if(identity.error||!identity.data.user)return reply({error:'Sign in to compare catalogue photographs'},401)
 const user=identity.data.user;const profile=await client.from('profiles').select('active').eq('id',user.id).single();if(profile.error||!profile.data?.active)return reply({error:'Active account required'},403)
 const raw=await req.text();if(raw.length>5500000)throw new RequestFailure('Choose a smaller photograph',413)
 let body;try{body=JSON.parse(raw)}catch{throw new RequestFailure('Invalid request')}
 if(body.action==='status'){const photos=await client.from('part_photos').select('id',{head:true,count:'exact'});if(photos.error)throw photos.error;return reply({...await engine.engineHealth(),configured:true,reference_photos:photos.count??null})}
 if(!validPhotoData(body.image_data))throw new RequestFailure('Choose a valid JPEG, PNG or WebP photograph')
 const deadline=Date.now()+45000,assetId=String(body.asset_id||'');let unitId=null,linked=null
 if(assetId){const asset=await client.from('assets').select('id,business_unit_id').eq('id',assetId).single();if(asset.error||!asset.data)throw new RequestFailure('Asset outside your authorized scope',403);unitId=asset.data.business_unit_id;const relation=await client.from('asset_part_compatibility').select('part_id').eq('asset_id',assetId);if(relation.error)throw relation.error;linked=(relation.data||[]).map(r=>r.part_id);if(!linked.length)return reply({matches:[],compared_photos:0,engine:'local_opencv_orb',external_ai:false,message:'Link catalogue parts and reference photographs to this machine first.'})}
 let query=client.from('parts_visible').select('id,part_number,description,manufacturer').eq('active',true)
 if(linked)query=query.in('id',linked)
 const keyword=String(body.catalog_query||'').replace(/[^\p{L}\p{N} _-]/gu,'').trim().slice(0,80)
 if(keyword)query=query.or(`part_number.ilike.%${keyword}%,description.ilike.%${keyword}%,manufacturer.ilike.%${keyword}%`)
 const found=await query.limit(1000);if(found.error)throw found.error;const parts=found.data||[]
 if(parts.length===1000)throw new RequestFailure('Choose a machine or enter a more specific catalogue keyword')
 if(!parts.length)return reply({matches:[],compared_photos:0,engine:'local_opencv_orb',external_ai:false,message:'No active catalogue parts match this scope.'})
 const photoRows=await client.from('part_photos').select('id,part_id,storage_path').in('part_id',parts.map(p=>p.id)).order('id').range(0,120);if(photoRows.error)throw photoRows.error;const photos=photoRows.data||[]
 if(photos.length>120)throw new RequestFailure('Choose a machine or catalogue keyword to narrow the reference photographs. Nothing was skipped.')
 if(!photos.length)return reply({matches:[],compared_photos:0,engine:'local_opencv_orb',external_ai:false,message:'No reference photographs yet. Add clear part photos before comparing.'})
 const queryBuffer=Buffer.from(body.image_data.split(',')[1],'base64'),features=await engine.extractFeatures(queryBuffer)
 if(!engine.usableQuery(features))throw new RequestFailure('The photo has too few distinctive details. Take a close, sharp photo of the markings and the complete part against a plain background.',422)
 const scored=[]
 async function reference(photo){
 if(Date.now()>deadline)throw new RequestFailure('This scope takes too long. Narrow by machine or keyword and try again.',422)
 const key=user.id+':'+photo.id+':'+photo.storage_path;let ref=featureCache.get(key)
 if(ref){featureCache.delete(key);featureCache.set(key,ref)}else{const downloaded=await client.storage.from('ruel-part-photos').download(photo.storage_path);if(downloaded.error||!downloaded.data)throw new RequestFailure('A reference photograph could not be opened. Correct the catalogue photo and retry.',409);if(downloaded.data.size>10000000)throw new RequestFailure('A reference photograph is too large. Replace it with a smaller catalogue photo.',422);ref=await engine.extractFeatures(Buffer.from(await downloaded.data.arrayBuffer()));featureCache.set(key,ref);while(featureCache.size>128)featureCache.delete(featureCache.keys().next().value)}
 const match=await engine.compareFeatures(features,ref);if(match)scored.push({photo,...match})
 }
 for(let i=0;i<photos.length;i+=4)await Promise.all(photos.slice(i,i+4).map(reference))
 if(Date.now()>deadline)throw new RequestFailure('Comparison exceeded the local processing budget. Narrow the catalogue scope and try again.',422)
 scored.sort((a,b)=>b.score-a.score);const seen=new Set(),best=scored.filter(r=>{if(seen.has(r.photo.part_id))return false;seen.add(r.photo.part_id);return true}).slice(0,5)
 if(!best.length)return reply({matches:[],compared_photos:photos.length,engine:'local_opencv_orb',external_ai:false,confirmation_required:true,message:'No supported visual match found. Try clearer markings, a similar angle and a plain background. Visually identical parts require code and dimension checks.'})
 const signed=await client.storage.from('ruel-part-photos').createSignedUrls(best.map(m=>m.photo.storage_path),600);if(signed.error||signed.data?.some(r=>!r.signedUrl)||signed.data?.length!==best.length)throw new RequestFailure('Reference previews could not be opened. Try again.',409)
 let stockQuery=client.from('inventory_stock_summary').select('part_id,location_name,position_code,quantity_available,quantity_on_order,business_unit_id').in('part_id',best.map(m=>m.photo.part_id));if(unitId)stockQuery=stockQuery.eq('business_unit_id',unitId)
 const stock=await stockQuery;if(stock.error)throw stock.error
 return reply({engine:'local_opencv_orb',external_ai:false,compared_photos:photos.length,confirmation_required:true,message:'Compared on the RUEL server without an external AI service. These are visual candidates; confirm the stamped code and dimensions.',matches:best.map((m,i)=>{const part=parts.find(p=>p.id===m.photo.part_id),positions=(stock.data||[]).filter(p=>p.part_id===part.id);return {part_id:part.id,part_number:part.part_number,description:part.description,manufacturer:part.manufacturer,reference_photo_url:signed.data[i].signedUrl,similarity:m.similarity,reason:'The reference photo has a consistent arrangement of visual details. Verify the stamped code and dimensions before selecting.',observed_markings:'',available:positions.reduce((sum,p)=>sum+Number(p.quantity_available||0),0),on_order:positions.reduce((sum,p)=>sum+Number(p.quantity_on_order||0),0),positions}})})
 }catch(e){return reply({error:e instanceof RequestFailure?e.message:'Local photo comparison could not finish. Check the image, catalogue and connection, then retry.'},e instanceof RequestFailure?e.status:400)}
}}
export default createPhotoHandler()
