import test from 'node:test'
import assert from 'node:assert/strict'
import {materialReadiness} from '../src/lib/partStock.ts'
import {validPhotoData,safePhotoMatches,comparePhotoCatalogue} from '../supabase/functions/_shared/partPhotoMatching.ts'
test('material readiness uses a physical fulfillment position and keeps incoming separate',()=>{
 const positions=[{location_id:'A',location_name:'A',quantity_available:2,quantity_on_order:10},{location_id:'B',location_name:'B',quantity_available:5,quantity_on_order:0}];const before=JSON.stringify(positions)
 assert.deepEqual(materialReadiness(4,positions,'A'),{available:2,missing:2,onOrder:10,locationId:'A',locationName:'A',expectedAt:null})
 assert.equal(materialReadiness(4,positions).locationId,'B');assert.equal(materialReadiness(4,positions).missing,0);assert.equal(JSON.stringify(positions),before)
 assert.equal(materialReadiness(4,[]).missing,4)
})
test('photo input excludes remote URLs, SVGs and mislabeled image payloads',()=>{
 for(const x of ['https://example.com/photo.jpg','data:image/svg+xml;base64,PHN2Zz4=','data:image/jpeg;base64,YWJjZA==','x'])assert.equal(validPhotoData(x),false)
 assert.equal(validPhotoData('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'),true)
})
const refs=Array.from({length:17},(_,i)=>({id:'photo-'+i,part_id:'part-'+(i%7),url:'private-url-'+i,part_number:'REF-'+i,description:'Reference',caption:''}))
test('model cannot invent catalogue IDs or confidence percentages',()=>{
 const result=safePhotoMatches({matches:[{photo_id:'invented',similarity:'high',reason:'x'},{photo_id:'photo-0',similarity:'99%',reason:'x'},{photo_id:'photo-1',similarity:'medium',reason:'Visible shape'}]},refs);assert.equal(result.length,1);assert.equal(result[0].photo_id,'photo-1')
})
test('all scoped reference photos are compared in bounded batches, then distinct parts reranked',async()=>{
 const seen=new Set();const result=await comparePhotoCatalogue(refs,async batch=>{assert.ok(batch.length<=8);batch.forEach(p=>seen.add(p.id));return {matches:batch.map(p=>({photo_id:p.id,similarity:'high',reason:'Visible connection',observed_markings:''}))}})
 assert.equal(seen.size,17);assert.ok(result.length<=5);assert.equal(new Set(result.map(m=>refs.find(r=>r.id===m.photo_id).part_id)).size,result.length)
})
test('no-match remains empty; oversized scope is rejected before a model call',async()=>{
 assert.deepEqual(await comparePhotoCatalogue(refs,async()=>({matches:[]})),[])
 await assert.rejects(()=>comparePhotoCatalogue(Array.from({length:121},()=>refs[0]),async()=>{throw new Error('should not call')}),/narrow/)
})
