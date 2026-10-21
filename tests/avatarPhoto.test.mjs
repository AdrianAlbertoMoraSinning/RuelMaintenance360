import test from 'node:test'
import assert from 'node:assert/strict'
import {avatarPhotoLayout,prepareAvatarPhoto} from '../src/lib/avatarPhoto.ts'
test('complete portrait, landscape and square images fit inside the circular mask without stretching or clipping',()=>{
 for(const[width,height]of[[1165,1536],[1000,1000],[3000,1500],[400,2400]]){
  const box=avatarPhotoLayout(width,height);assert.equal(box.size,640);assert.ok(Math.abs(box.width/box.height-width/height)<1e-10)
  for(const[x,y]of[[box.x,box.y],[box.x+box.width,box.y],[box.x,box.y+box.height],[box.x+box.width,box.y+box.height]])assert.ok(Math.hypot(x-320,y-320)<320*.93)
  assert.equal(box.x*2+box.width,640);assert.equal(box.y*2+box.height,640)
 }
 assert.throws(()=>avatarPhotoLayout(0,100));assert.throws(()=>avatarPhotoLayout(100,NaN))
})
test('upload draws the complete source rather than cropping it and releases its decoded bitmap',async()=>{
 const originalBitmap=globalThis.createImageBitmap,originalDocument=globalThis.document,draws=[];let closed=false
 const bitmap={width:1165,height:1536,close(){closed=true}},ctx={drawImage(...args){draws.push(args)},getImageData(){return{data:[0,0,0,255]}},fillRect(){}}
 globalThis.createImageBitmap=async()=>bitmap;globalThis.document={createElement:()=>({getContext:()=>ctx,toBlob:callback=>callback(new Blob(['photo'],{type:'image/jpeg'}))})}
 try{const blob=await prepareAvatarPhoto({});assert.equal(blob.type,'image/jpeg');assert.equal(closed,true);const draw=draws.at(-1);assert.equal(draw.length,5);assert.equal(draw[0],bitmap);assert.equal(ctx.fillStyle,'rgb(0,0,0)')}finally{globalThis.createImageBitmap=originalBitmap;globalThis.document=originalDocument}
})
