import test from 'node:test'
import assert from 'node:assert/strict'
import {readEntryActivity,hasEntryActivity,entryActivityText,entryActivationGate} from '../src/lib/entryActivity.ts'

test('entry summary includes task chats, observation replies and other notifications',async()=>{
 const result=await readEntryActivity({tasks:async()=>({data:[{id:'task'}],count:1,error:null}),chats:async()=>({data:[{observation_id:'obs'}],count:1,error:null}),alerts:async()=>({count:5,error:null})})
 assert.deepEqual(result,{tasks:1,chats:1,alerts:5,taskId:'task',observationId:'obs',partial:false})
 assert.equal(hasEntryActivity(result),true)
 assert.match(entryActivityText(result),/1 task has new activity/)
 assert.match(entryActivityText(result),/1 unread observation message/)
 assert.match(entryActivityText(result),/5 other alerts/)
})
test('exact counts are used beyond preview limits and multiple items open their list',async()=>{
 const result=await readEntryActivity({tasks:async()=>({data:[{id:'task'}],count:150,error:null}),chats:async()=>({data:[{observation_id:'obs'}],count:2,error:null}),alerts:async()=>({count:0,error:null})})
 assert.equal(result.tasks,150);assert.equal(result.taskId,undefined);assert.equal(result.observationId,undefined)
})
test('empty or unavailable reads never create a false unread reminder',async()=>{
 const result=await readEntryActivity({tasks:()=>{throw Error('Offline')},chats:async()=>({count:null,error:Error('Denied')}),alerts:async()=>({count:0,error:null})})
 assert.equal(hasEntryActivity(result),false);assert.equal(result.partial,true)
 const partial=await readEntryActivity({tasks:async()=>({count:1,error:null}),chats:async()=>({count:0,error:null}),alerts:()=>Promise.reject(Error('Offline'))})
 assert.equal(partial.tasks,1);assert.equal(partial.partial,true)
})
test('activation events are coalesced without hiding reminders on a later activation',()=>{
 const allow=entryActivationGate()
 assert.equal(allow(0),true);assert.equal(allow(20),false);assert.equal(allow(900),false);assert.equal(allow(1600),true)
})
