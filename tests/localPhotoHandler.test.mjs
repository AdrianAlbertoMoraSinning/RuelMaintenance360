import test from 'node:test'
import assert from 'node:assert/strict'
import {createPhotoHandler} from '../server/localPhotoHandler.mjs'
const photo='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'
function fixture({empty=false,forbidden=false,match=true}={}){
 const tables={profiles:[{id:'user',active:true}],parts_visible:[{id:'part',part_number:'6205',description:'Bearing',manufacturer:'Recorded manufacturer',active:true}],part_photos:empty?[]:[{id:'photo',part_id:'part',storage_path:'part/photo.jpg'}],inventory_stock_summary:[{part_id:'part',location_name:'Shelf',position_code:'A1',quantity_available:2,quantity_on_order:1,business_unit_id:'unit'}],assets:[]};const downloads=[]
 const db={auth:{getUser:async()=>({data:{user:forbidden?null:{id:'user'}},error:null})},from(table){let rows=[...(tables[table]||[])];let count=false,single=false;const q={select(_,o){count=o?.count==='exact';return q},eq(k,v){rows=rows.filter(r=>r[k]===v);return q},in(k,v){rows=rows.filter(r=>v.includes(r[k]));return q},or(){return q},limit(n){rows=rows.slice(0,n);return q},order(){return q},range(a,b){rows=rows.slice(a,b+1);return q},single(){single=true;return q},then(ok,bad){return Promise.resolve({data:count?null:single?rows[0]||null:rows,count:rows.length,error:null}).then(ok,bad)}};return q},storage:{from(bucket){assert.equal(bucket,'ruel-part-photos');return{download:async path=>{downloads.push(path);return{data:new Blob(['private reference']),error:null}},createSignedUrls:async paths=>({data:paths.map(p=>({signedUrl:'https://private-ruel-reference/'+p})),error:null})}}}}
 const engine={engineHealth:async()=>({ready:true,external_ai:false,engine:'local_opencv_orb'}),extractFeatures:async()=>({rows:50}),usableQuery:()=>true,compareFeatures:async()=>match?{inliers:30,score:20,similarity:'high'}:null}
 return {handler:createPhotoHandler({makeClient:()=>db,engine,featureCache:new Map()}),downloads}
}
const request=body=>new Request('https://ruelmaintenance360.netlify.app/.netlify/functions/part-photo-match-local',{method:'POST',headers:{Authorization:'Bearer user-session','Content-Type':'application/json'},body:JSON.stringify(body)})
test('local status requires no AI credentials and authenticated results use only catalogue IDs and stock records',async()=>{
 const {handler,downloads}=fixture();const status=await(await handler(request({action:'status'}))).json();assert.equal(status.configured,true);assert.equal(status.external_ai,false)
 const result=await(await handler(request({image_data:photo,references:[{id:'invented',url:'https://evil.example/private'}]}))).json();assert.equal(result.matches[0].part_id,'part');assert.equal(result.matches[0].part_number,'6205');assert.equal(result.matches[0].available,2);assert.equal(result.confirmation_required,true);assert.equal(result.external_ai,false);assert.deepEqual(downloads,['part/photo.jpg']);assert.equal(result.matches[0].observed_markings,'')
})
test('anonymous or inactive identity cannot read references; empty catalogue and no-match are explicit',async()=>{
 const {handler,downloads}=fixture({forbidden:true});assert.equal((await handler(request({image_data:photo}))).status,401);assert.equal(downloads.length,0)
 const empty=fixture({empty:true});const result=await(await empty.handler(request({image_data:photo}))).json();assert.deepEqual(result.matches,[]);assert.equal(result.compared_photos,0)
 const none=fixture({match:false});const rejected=await(await none.handler(request({image_data:photo}))).json();assert.deepEqual(rejected.matches,[]);assert.equal(rejected.compared_photos,1)
})
test('remote image URLs are not accepted as a query and there is no external AI fallback',async()=>{
 const {handler,downloads}=fixture();assert.equal((await handler(request({image_data:'https://example.com/image.jpg'}))).status,400);assert.equal(downloads.length,0)
})
