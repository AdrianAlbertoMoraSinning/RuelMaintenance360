import test from 'node:test'
import assert from 'node:assert/strict'
import sharp from 'sharp'
import {extractFeatures,compareFeatures,usableQuery,engineHealth} from '../server/localPhotoEngine.mjs'
const bearingSvg='<svg width="600" height="600" xmlns="http://www.w3.org/2000/svg"><rect width="600" height="600" fill="white"/><circle cx="300" cy="300" r="220" fill="#aaa" stroke="black" stroke-width="8"/><circle cx="300" cy="300" r="160" fill="white" stroke="black" stroke-width="6"/><text x="160" y="300" font-size="55">BEARING</text><text x="200" y="365" font-size="45">6205 ZZ</text>'+Array.from({length:18},(_,i)=>`<rect x="${80+(i%6)*80}" y="${90+Math.floor(i/6)*160}" width="${10+i}" height="${20+i*2}" fill="#333" transform="rotate(${i*5} 300 300)"/>`).join('')+'</svg>'
const reference=await sharp(Buffer.from(bearingSvg)).png().toBuffer()
test('bundled OpenCV/Sharp compare rotated and re-encoded images with network access disabled',async()=>{
 const original=globalThis.fetch;globalThis.fetch=()=>{throw Error('External network forbidden in local engine')}
 try{const query=await sharp(reference).rotate(12,{background:'white'}).jpeg({quality:75}).toBuffer();const a=await extractFeatures(query),b=await extractFeatures(reference),match=await compareFeatures(a,b);assert.ok(usableQuery(a));assert.ok(match?.inliers>=24);assert.equal(match.similarity,'high');const health=await engineHealth();assert.equal(health.ready,true);assert.equal(health.external_ai,false)}finally{globalThis.fetch=original}
})
test('blank images do not produce a part match and a different visual arrangement is rejected',async()=>{
 const blank=await sharp({create:{width:600,height:600,channels:3,background:'white'}}).png().toBuffer();const b=await extractFeatures(blank),r=await extractFeatures(reference);assert.equal(usableQuery(b),false);assert.equal(await compareFeatures(b,r),null)
 const svg='<svg width="600" height="600" xmlns="http://www.w3.org/2000/svg"><rect width="600" height="600" fill="white"/>'+Array.from({length:40},(_,i)=>`<polygon points="${(i*137)%570},${(i*73)%570} ${(i*137+30)%600},${(i*73+65)%600} ${(i*137+75)%600},${(i*73+20)%600}" fill="${i%2?'black':'gray'}"/>`).join('')+'</svg>'
 const different=await extractFeatures(await sharp(Buffer.from(svg)).png().toBuffer());assert.equal(await compareFeatures(different,r),null)
})
