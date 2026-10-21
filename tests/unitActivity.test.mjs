import test from 'node:test'
import assert from 'node:assert/strict'
import {unitPending,dueTiming,observationTiming,activityPages} from '../src/lib/unitActivity.ts'
const now=Date.parse('2026-10-22T00:00:00Z')
test('unit counts exclude other units, corporate tasks and completed records, but retain review and WO follow-up',()=>{
 const observations=[{id:'1',business_unit_id:'plant',status:'work_order_created'},{id:'2',business_unit_id:'plant',status:'resolved'},{id:'3',business_unit_id:'shop',status:'submitted'}]
 const tasks=[{id:'a',business_unit_id:'plant',status:'completion_requested'},{id:'b',business_unit_id:'plant',status:'completed'},{id:'c',business_unit_id:null,status:'pending'},{id:'d',business_unit_id:'shop',status:'pending'},{id:'e',business_unit_id:'plant',status:'cancelled'}]
 const result=unitPending('plant',observations,tasks);assert.deepEqual(result.observations.map(x=>x.id),['1']);assert.deepEqual(result.tasks.map(x=>x.id),['a'])
})
test('deadlines compare exact instants, including Alberta timestamps; missing deadlines are never labelled on time',()=>{
 assert.equal(dueTiming('2026-10-21T17:00:00-06:00',now),'overdue');assert.equal(dueTiming('2026-10-21T19:00:00-06:00',now),'on_time');assert.equal(dueTiming('2026-10-22T00:00:00Z',now),'on_time');assert.equal(dueTiming(null,now),'no_due_date');assert.equal(dueTiming('invalid',now),'no_due_date')
})
test('observation urgency follows pending actions, disregards closed actions and prevents cross-observation contamination',()=>{
 const actions=[{id:'1',observation_id:'obs',status:'pending',due_at:'2026-10-23T00:00:00Z'},{id:'2',observation_id:'obs',status:'completed',due_at:'2026-10-19T00:00:00Z'},{id:'3',observation_id:'other',status:'pending',due_at:'2026-10-19T00:00:00Z'}]
 assert.equal(observationTiming('obs',actions,now),'on_time');assert.equal(observationTiming('none',actions,now),'no_due_date');actions.push({id:'4',observation_id:'obs',status:'pending',due_at:'2026-10-20T00:00:00Z'});assert.equal(observationTiming('obs',actions,now),'overdue')
})
test('activity pagination reads beyond the default API limit and propagates failures instead of reporting zero',async()=>{
 const source=Array.from({length:1203},(_,id)=>({id})),calls=[];const rows=await activityPages(async(a,b)=>{calls.push([a,b]);return{data:source.slice(a,b+1),error:null}})
 assert.equal(rows.length,1203);assert.deepEqual(calls,[[0,499],[500,999],[1000,1499]]);await assert.rejects(()=>activityPages(async()=>({data:null,error:new Error('denied')})),/denied/)
})
