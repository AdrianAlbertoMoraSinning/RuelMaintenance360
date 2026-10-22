import test from 'node:test'
import assert from 'node:assert/strict'
import{saveObservationDraft}from'../src/lib/observationOfflineStore.ts'

test('offline photos are not declared saved until IndexedDB commits, and aborts remain errors',async()=>{
 let tx,request,closed=false
 globalThis.indexedDB={open(){const opening={result:{transaction(){request={result:'draft'};tx={objectStore(){return{put(){return request}}}};return tx},close(){closed=true}}};queueMicrotask(()=>opening.onsuccess());return opening}}
 let settled=false
 const saved=saveObservationDraft({id:'draft',photos:[{blob:new Blob(['photo'])}]}).then(()=>{settled=true})
 await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);assert.equal(closed,false)
 request.onsuccess?.();await Promise.resolve();assert.equal(settled,false)
 tx.oncomplete();await saved;assert.equal(settled,true);assert.equal(closed,true)
 const aborted=saveObservationDraft({id:'abort',photos:[]})
 await new Promise(resolve=>setImmediate(resolve));tx.onabort();await assert.rejects(aborted,/aborted/)
 delete globalThis.indexedDB
})
