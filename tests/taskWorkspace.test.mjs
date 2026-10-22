import test from 'node:test'
import assert from 'node:assert/strict'
import {settleTaskWorkspace} from '../src/lib/taskWorkspace.ts'
const ok=data=>async()=>({data,error:null})
test('inbox and optional-plan failures do not hide successfully loaded subordinate recipients',async()=>{
 const recipients=[{id:'dj',full_name:'DJ'}]
 const r=await settleTaskWorkspace({tasks:async()=>{throw new Error('Failed to fetch')},recipients:ok(recipients),assets:ok([{id:'asset'}]),plans:async()=>({data:null,error:{message:'Denied'}})})
 assert.deepEqual(r.recipients.data,recipients);assert.equal(r.recipients.error,null);assert.equal(r.assets.data[0].id,'asset');assert.match(r.tasks.error.message,/Failed to fetch/);assert.equal(r.plans.error.message,'Denied')
})
test('recipient errors remain explicit and are never replaced with unauthorized fallback recipients',async()=>{
 const r=await settleTaskWorkspace({tasks:ok([{id:'task'}]),recipients:async()=>{throw Error('Denied')},assets:ok([]),plans:ok([])})
 assert.equal(r.recipients.data,null);assert.equal(r.recipients.error.message,'Denied');assert.deepEqual(r.tasks.data,[{id:'task'}])
})
