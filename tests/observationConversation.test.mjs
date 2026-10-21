import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import ts from 'typescript'
import React from 'react'
import {renderToStaticMarkup} from 'react-dom/server'
import {mergeObservationMessages,prepareObservationMessage,readObservationMessageDraft,saveObservationMessageDraft} from '../src/lib/observationConversation.ts'
import {readTaskMessageDraft} from '../src/lib/taskConversation.ts'
const message=(id,observation_id='obs-a')=>({id,observation_id,author_id:'reporter',author_name:'Adrian Mora',author_role:'reporter',body:'Please clarify',created_at:'2026-10-21T20:00:00Z',client_message_id:'retry-'+id})
test('repeated polls and older pages retain chronological messages without duplicates',()=>{
 const current=[message(2),message(3)];assert.deepEqual(mergeObservationMessages(current,[message(1),message(3),message(4)]).map(x=>x.id),[1,2,3,4]);assert.deepEqual(current.map(x=>x.id),[2,3])
})
test('a retry keeps its identifier; a different message requires a new one',()=>{
 const first=prepareObservationMessage(' Question ',null,()=> 'one');assert.deepEqual(first,{body:'Question',id:'one'});assert.equal(prepareObservationMessage('Question',first,()=> 'unused'),first);assert.equal(prepareObservationMessage('Answer',first,()=> 'two').id,'two');assert.throws(()=>prepareObservationMessage(' ',null,()=> 'unused'));assert.throws(()=>prepareObservationMessage('x'.repeat(10001),null,()=> 'unused'))
})
test('drafts and retries are isolated by observation, account and the My To-do module',()=>{
 const values=new Map();const storage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)}
 saveObservationMessageDraft(storage,'Adrian','obs-a',{text:'Need details',requestId:'retry'})
 assert.deepEqual(readObservationMessageDraft(storage,'Adrian','obs-a'),{text:'Need details',requestId:'retry'})
 assert.equal(readObservationMessageDraft(storage,'Adrian','obs-b').text,'');assert.equal(readObservationMessageDraft(storage,'Guy','obs-a').text,'');assert.equal(readTaskMessageDraft(storage,'Adrian','obs-a').text,'')
 saveObservationMessageDraft(storage,'Adrian','obs-a',{text:'',requestId:null});assert.equal(readObservationMessageDraft(storage,'Adrian','obs-a').text,'')
 const blocked={getItem(){throw Error('blocked')},setItem(){throw Error('blocked')},removeItem(){throw Error('blocked')}};assert.equal(readObservationMessageDraft(blocked,'Adrian','obs-a').text,'');assert.doesNotThrow(()=>saveObservationMessageDraft(blocked,'Adrian','obs-a',{text:'Draft',requestId:null}))
})
const source=readFileSync(new URL('../src/modules/ObservationMessageList.tsx',import.meta.url),'utf8')
const js=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const mod={};new Function('require','exports',js)(createRequire(import.meta.url),mod)
test('reporter and reviewer messages show author, side and timestamp, with literal evidence',()=>{
 const html=renderToStaticMarkup(React.createElement(mod.default,{messages:[{...message(1),body:'<script>unsafe</script>'},{...message(2),author_id:'reviewer',author_name:'Guy Munden',author_role:'reviewer',body:'Use the north shelf'}],userId:'reporter'}))
 assert.match(html,/Adrian Mora · You/);assert.match(html,/Guy Munden/);assert.match(html,/Reporter/);assert.match(html,/Assigned reviewer/);assert.match(html,/Alberta/);assert.match(html,/dateTime="2026-10-21T20:00:00Z"/i);assert.match(html,/&lt;script&gt;unsafe&lt;\/script&gt;/);assert.doesNotMatch(html,/<script>/);assert.match(html,/role="log"/)
})
