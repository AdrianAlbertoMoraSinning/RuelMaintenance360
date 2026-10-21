import test from 'node:test'
import assert from 'node:assert/strict'
import {taskDay,taskMatches,taskScheduledAt} from '../src/lib/taskModel.ts'
test('Alberta day boundaries include overdue work and avoid browser timezone dependence',()=>{
 assert.equal(taskDay('2026-10-22T01:00:00Z'),'2026-10-21')
 assert.equal(taskDay('2026-01-22T06:59:59Z'),'2026-01-21')
 assert.equal(taskDay('2026-01-22T07:00:00Z'),'2026-01-22')
 assert.equal(taskMatches({status:'pending',due_at:'2026-10-22T01:00:00Z'},'today','2026-10-21'),true)
 assert.equal(taskMatches({status:'blocked',due_at:'2026-10-01T19:00:00Z'},'today','2026-10-21'),true)
 assert.equal(taskMatches({status:'pending',due_at:'2026-10-23T01:00:00Z'},'upcoming','2026-10-21'),true)
})
test('only terminal tasks leave pending views; awaiting supervisor review stays active',()=>{
 for(const status of ['pending','in_progress','blocked','completion_requested'])assert.equal(taskMatches({status,due_at:'2026-10-21T19:00:00Z'},'all'),true)
 for(const status of ['completed','cancelled']){
 const task={status,due_at:'2026-10-21T19:00:00Z'}
 assert.equal(taskMatches(task,'all'),false);assert.equal(taskMatches(task,'archive'),true)
 }
})
test('entered schedule uses the plant timezone rather than the viewer’s timezone',()=>{
 assert.equal(taskScheduledAt('2026-10-21','17:00'),'2026-10-21 17:00 America/Edmonton')
 assert.throws(()=>taskScheduledAt('','17:00'))
})
