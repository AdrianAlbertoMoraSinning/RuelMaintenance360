import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import ts from 'typescript'
import React from 'react'
import {renderToStaticMarkup} from 'react-dom/server'
import {mergeTaskMessages,prepareTaskMessage,readTaskMessageDraft,saveTaskMessageDraft} from '../src/lib/taskConversation.ts'
const message=(id,body='Message')=>({id,task_id:'task',actor_id:'assigner',author_name:'Don McDonald',body,created_at:'2026-10-21T16:00:00Z',client_message_id:null})
test('polling and earlier-message pages merge in chronological order without duplicates',()=>{
 const current=[message(2),message(3)]
 assert.deepEqual(mergeTaskMessages(current,[message(1),message(3),message(4)]).map(m=>m.id),[1,2,3,4])
 assert.deepEqual(current.map(m=>m.id),[2,3])
})
test('retrying the same message retains its request ID, while a different message gets a new one',()=>{
 const first=prepareTaskMessage(' Where do I start? ',null,()=> 'first')
 assert.deepEqual(first,{body:'Where do I start?',id:'first'})
 assert.deepEqual(prepareTaskMessage('Where do I start?',first,()=> 'unused'),first)
 assert.equal(prepareTaskMessage('Please inspect the mixer',first,()=> 'second').id,'second')
 assert.throws(()=>prepareTaskMessage(' ',null,()=> 'unused'))
 assert.throws(()=>prepareTaskMessage('x'.repeat(10001),null,()=> 'unused'))
})
test('draft and retry ID remain isolated by signed-in user and task; blocked storage is tolerated',()=>{
 const values=new Map();const storage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)}
 saveTaskMessageDraft(storage,'DJ','task-a',{text:'Need instructions',requestId:'retry-id'})
 assert.deepEqual(readTaskMessageDraft(storage,'DJ','task-a'),{text:'Need instructions',requestId:'retry-id'})
 assert.equal(readTaskMessageDraft(storage,'DJ','task-b').text,'')
 assert.equal(readTaskMessageDraft(storage,'Don','task-a').text,'')
 saveTaskMessageDraft(storage,'DJ','task-a',{text:'',requestId:null});assert.equal(readTaskMessageDraft(storage,'DJ','task-a').text,'')
 const blocked={getItem(){throw Error('blocked')},setItem(){throw Error('blocked')},removeItem(){throw Error('blocked')}}
 assert.equal(readTaskMessageDraft(blocked,'DJ','task-a').text,'')
 assert.doesNotThrow(()=>saveTaskMessageDraft(blocked,'DJ','task-a',{text:'Safe draft',requestId:null}))
})
const source=readFileSync(new URL('../src/modules/TaskMessageList.tsx',import.meta.url),'utf8')
const js=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const mod={};new Function('require','exports',js)(createRequire(import.meta.url),mod)
test('conversation shows sender, assignment side, timestamp and literal evidence without executing message HTML',()=>{
 const html=renderToStaticMarkup(React.createElement(mod.default,{messages:[message(1,'<script>not executable</script>'),{...message(2),actor_id:'DJ',author_name:'DJ',body:'Please clarify'}],userId:'DJ',assignerId:'assigner'}))
 assert.match(html,/Don McDonald/);assert.match(html,/Task assigner/);assert.match(html,/Task assignee/);assert.match(html,/DJ · You/)
 assert.match(html,/dateTime="2026-10-21T16:00:00Z"/i);assert.match(html,/Alberta/)
 assert.match(html,/&lt;script&gt;not executable&lt;\/script&gt;/);assert.doesNotMatch(html,/<script>/)
 assert.match(html,/role="log"/)
})
