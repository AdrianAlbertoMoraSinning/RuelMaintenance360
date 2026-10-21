import test from 'node:test'
import assert from 'node:assert/strict'
import {retryTaskRead,taskRefreshError,taskActionError} from '../src/lib/taskRefresh.ts'
test('a transient failed read retries once and returns the current server data',async()=>{
 let calls=0;const result=await retryTaskRead(async()=>++calls===1?{data:null,error:{message:'TypeError: Failed to fetch'}}:{data:['TASK-28'],error:null});assert.equal(calls,2);assert.deepEqual(result.data,['TASK-28']);assert.equal(result.error,null)
})
test('thrown network reads recover, but repeated failures remain visible and bounded',async()=>{
 let calls=0;const result=await retryTaskRead(async()=>{if(++calls===1)throw new TypeError('Failed to fetch');return {data:[25],error:null}});assert.equal(calls,2);assert.deepEqual(result.data,[25])
 calls=0;await assert.rejects(()=>retryTaskRead(async()=>{calls++;throw new TypeError('Failed to fetch')}));assert.equal(calls,2)
})
test('permission and business errors are not retried or disguised as connection problems',async()=>{
 let calls=0;const error={message:'Permission denied',code:'42501'};assert.equal((await retryTaskRead(async()=>{calls++;return {error}})).error,error);assert.equal(calls,1);assert.equal(taskRefreshError(error),'Permission denied')
})
test('refresh failures preserve the last snapshot, while uncertain writes require checking before retry',()=>{
 assert.match(taskRefreshError({message:'TypeError: Failed to fetch'}),/last loaded tasks/);assert.doesNotMatch(taskRefreshError({message:'TypeError: Failed to fetch'}),/not been sent|TypeError/)
 assert.match(taskActionError(new TypeError('Failed to fetch'),'Save failed'),/could not be confirmed/);assert.match(taskActionError(new TypeError('Failed to fetch'),'Save failed'),/before trying again/)
})
