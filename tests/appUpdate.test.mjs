import test from 'node:test'
import assert from 'node:assert/strict'
import{automaticUpdateAllowed,createUpdateSafety,guardUpdateRequests,isCurrentAppVersion,parseAppVersion,recentlyReloaded,sameAppAssets}from'../src/lib/appUpdate.ts'
import{trackUpdateEdits}from'../src/lib/updateEdits.ts'

test('version identity detects CSS-only and JS changes without reloading the same release',()=>{
 const assets={entry:'/assets/index-one.js',styles:['/assets/one.css']}
 assert.equal(sameAppAssets(assets,{...assets}),true)
 assert.equal(sameAppAssets(assets,{...assets,styles:['/assets/two.css']}),false)
 assert.equal(sameAppAssets(assets,{...assets,entry:'/assets/index-two.js'}),false)
 assert.equal(parseAppVersion({schema:1,version:'abcdef0123456789abcd',...assets})?.entry,assets.entry)
 assert.equal(isCurrentAppVersion(assets,{schema:1,version:'abcdef0123456789abcd',...assets},'00000000000000000000'),false)
 for(const value of [null,{},'<!doctype html>',{schema:1,version:'abcdef0123456789abcd',...assets,entry:'https://other.example/code.js'}])assert.equal(parseAppVersion(value),null)
})
test('automatic updates require idle, visible, online, unblocked work and avoid reload loops',()=>{
 const safe={online:true,visible:true,blocked:false,focused:false,idleMs:15000,recentReload:false}
 assert.equal(automaticUpdateAllowed(safe),true)
 for(const override of [{online:false},{visible:false},{blocked:true},{focused:true},{idleMs:9999},{recentReload:true}])assert.equal(automaticUpdateAllowed({...safe,...override}),false)
 assert.equal(recentlyReloaded(JSON.stringify({version:'build',at:1000}),'build',2000),true)
 assert.equal(recentlyReloaded(JSON.stringify({version:'build',at:1000}),'new-build',2000),false)
 assert.equal(recentlyReloaded(JSON.stringify({version:'build',at:1000}),'build',302000),false)
 assert.equal(recentlyReloaded('broken','build',2000),false)
})
test('nested draft and write blockers release independently and only once',()=>{
 const safety=createUpdateSafety(),draft=safety.hold(),write=safety.hold()
 draft();draft();assert.equal(safety.blocked(),true);write();assert.equal(safety.blocked(),false)
})
test('fetch keeps writes protected through success and abort without changing arguments or responses',async()=>{
 const safety=createUpdateSafety();let finish;let seen
 const response={ok:true};const guarded=guardUpdateRequests((...args)=>{seen=args;return new Promise(resolve=>{finish=resolve})},safety)
 const options={method:'POST',body:'draft',signal:new AbortController().signal}
 const pending=guarded('/write',options);assert.equal(safety.blocked(),true);assert.equal(seen[1],options)
 finish(response);assert.equal(await pending,response);assert.equal(safety.blocked(),false)
 const abort=guardUpdateRequests(async()=>{throw new DOMException('Aborted','AbortError')},safety)
 await assert.rejects(abort(new Request('https://example.test/write',{method:'POST'})),{name:'AbortError'});assert.equal(safety.blocked(),false)
 const read=guarded('/app-version.json',{cache:'no-store'});assert.equal(safety.blocked(),false);finish(response);await read
})
test('form protection detects edits, reverts, removed controls and successful reset',()=>{
 class Input{value='';defaultValue='';type='text';checked=false;defaultChecked=false;isConnected=true;form={}}
 class Select{value='';isConnected=true;form={}}
 class TextArea extends Input{}
 globalThis.HTMLInputElement=Input;globalThis.HTMLSelectElement=Select;globalThis.HTMLTextAreaElement=TextArea
 const listeners=new Map();const doc={addEventListener(type,fn){listeners.set(type,fn)},removeEventListener(type){listeners.delete(type)}}
 const guard=trackUpdateEdits(doc),field=new Input()
 listeners.get('focusin')({target:field});field.value='Unsent observation';listeners.get('input')({target:field});assert.equal(guard.blocked(),true)
 field.value='';assert.equal(guard.blocked(),false)
 field.value='Edited';listeners.get('input')({target:field});assert.equal(guard.blocked(),true)
 listeners.get('reset')({target:field.form});assert.equal(guard.blocked(),false)
 field.value='Another draft';listeners.get('input')({target:field});field.isConnected=false;assert.equal(guard.blocked(),false)
 guard.stop();assert.equal(listeners.size,0)
 delete globalThis.HTMLInputElement;delete globalThis.HTMLSelectElement;delete globalThis.HTMLTextAreaElement
})
