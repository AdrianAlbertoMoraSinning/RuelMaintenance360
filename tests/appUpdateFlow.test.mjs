import test from 'node:test'
import assert from 'node:assert/strict'
import{readFileSync}from'node:fs'
import{createRequire}from'node:module'
import ts from'typescript'
import React from'react'
import{renderToStaticMarkup}from'react-dom/server'
import*as model from'../src/lib/appUpdate.ts'

// Run the real notice effect against deterministic activation events and time.
// This verifies navigation behavior without opening a real account or consuming a session.
const nativeRequire=createRequire(import.meta.url)
const source=readFileSync(new URL('../src/components/AppUpdateNotice.tsx',import.meta.url),'utf8').replace('import.meta.env.PROD','true')
const js=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const current={schema:1,version:'00000000000000000000',entry:'/assets/old.js',styles:['/assets/old.css']}
const newer={schema:1,version:'11111111111111111111',entry:'/assets/new.js',styles:['/assets/new.css']}
test('About displays the release actually loaded on the device with a separate build identity',()=>{
 const previous=globalThis.document
 const metadata={'ruel-release':'0.2.0','ruel-build':'device-build-123','ruel-built-at':'2026-10-22T15:00:00Z'}
 globalThis.document={querySelector:selector=>({content:metadata[selector.match(/name="([^"]+)/)[1]]})}
 try{
  const about=readFileSync(new URL('../src/modules/AboutSection.tsx',import.meta.url),'utf8')
  const rendered=ts.transpileModule(about,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
  const exports={};new Function('require','exports',rendered)(name=>name==='../lib/appUpdate'?model:name==='../components/Brand'?{__esModule:true,default:()=>null}:nativeRequire(name),exports)
  const html=renderToStaticMarkup(React.createElement(exports.default))
  assert.match(html,/0\.2\.0/);assert.match(html,/device-build-123/);assert.match(html,/Check for updates/)
 }finally{globalThis.document=previous}
})
async function harness(storage=new Map()){
 let now=100000,seed=0,next=current;const timers=new Map(),effects=[],values=[],refs=[],listeners=new Map(),navigations=[]
 const saved={window:globalThis.window,document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),sessionStorage:globalThis.sessionStorage,fetch:globalThis.fetch,now:Date.now,clearTimeout:globalThis.clearTimeout,clearInterval:globalThis.clearInterval}
 const add=(type,fn)=>{if(!listeners.has(type))listeners.set(type,new Set());listeners.get(type).add(fn)}
 const remove=(type,fn)=>listeners.get(type)?.delete(fn)
 const setTimer=(fn,delay,repeat=false)=>{const id=++seed;timers.set(id,{fn,delay,at:now+delay,repeat});return id}
 const doc={visibilityState:'visible',activeElement:null,querySelector:()=>({src:'https://app.test/assets/old.js'}),querySelectorAll:()=>[{href:'https://app.test/assets/old.css'}],addEventListener:add,removeEventListener:remove}
 const win={setTimeout:(fn,delay)=>setTimer(fn,delay),setInterval:(fn,delay)=>setTimer(fn,delay,true),addEventListener:add,removeEventListener:remove,location:{href:'https://app.test/?task=task-123',replace:url=>navigations.push(url)}}
 globalThis.window=win;globalThis.document=doc;Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true});globalThis.sessionStorage={getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value)}
 Date.now=()=>now;globalThis.clearTimeout=id=>timers.delete(id);globalThis.clearInterval=id=>timers.delete(id)
 globalThis.fetch=async()=>({ok:true,headers:{get:()=> 'application/json'},json:async()=>next})
 const react={useState(initial){const index=values.length;values.push(initial);return[initial,value=>{values[index]=typeof value==='function'?value(values[index]):value}]},useRef(initial){const ref={current:initial};refs.push(ref);return ref},useEffect(effect){effects.push(effect)}}
 const mod={};new Function('require','exports',js)(name=>name==='react'?react:name==='../lib/appUpdate'?model:name==='../lib/updateEdits'?{trackUpdateEdits:()=>({blocked:()=>false,stop(){}})}:name.endsWith('.css')?{}:nativeRequire(name),mod)
 mod.default();const cleanup=effects[0]()
 const flush=()=>new Promise(resolve=>setImmediate(resolve))
 return{values,navigations,storage,refs,doc,async advance(ms){const until=now+ms;while(now<until){now=Math.min(until,now+500);for(const[id,timer]of[...timers])if(timer.at<=now){if(timer.repeat)timer.at=now+timer.delay;else timers.delete(id);timer.fn()}await flush()}},async upgrade(){next=newer;for(const fn of listeners.get('ruel:check-app-update')||[])fn();await flush()},async apply(){refs[0].current();await flush()},event(type){for(const fn of listeners.get(type)||[])fn()},async flush(){await flush()},close(){cleanup();globalThis.window=saved.window;globalThis.document=saved.document;if(saved.navigator)Object.defineProperty(globalThis,'navigator',saved.navigator);else delete globalThis.navigator;globalThis.sessionStorage=saved.sessionStorage;globalThis.fetch=saved.fetch;Date.now=saved.now;globalThis.clearTimeout=saved.clearTimeout;globalThis.clearInterval=saved.clearInterval}}
}
test('the real update notice waits for drafts and cancels navigation when activity starts during the version read',async()=>{
 const h=await harness();let release=model.updateSafety.hold()
 try{await h.advance(2000);assert.equal(h.values[0],null);await h.upgrade();await h.advance(20000);assert.equal(h.values[1],true);assert.equal(h.navigations.length,0)
  release();await h.advance(500);assert.equal(h.values[1],false)
  h.refs[0].current();h.event('pointerdown');await h.flush();assert.equal(h.navigations.length,0)
  await h.apply();assert.equal(h.navigations.length,1);const url=new URL(h.navigations[0]);assert.equal(url.searchParams.get('task'),'task-123');assert.equal(url.searchParams.get('_app_version'),newer.version)
 }finally{release();h.close()}
})
test('safe idle workspaces update automatically, but a stale page cannot enter a reload loop',async()=>{
 const storage=new Map();let h=await harness(storage)
 try{await h.upgrade();await h.advance(17000);assert.equal(h.navigations.length,1);assert.equal(JSON.parse(storage.get('ruel:last-version-reload')).version,newer.version)}finally{h.close()}
 h=await harness(storage)
 try{await h.upgrade();await h.advance(30000);assert.equal(h.navigations.length,0);assert.ok(h.values[0]);await h.apply();assert.equal(h.navigations.length,1)}finally{h.close()}
})
test('a version already requested in the URL prevents loops even with browser storage blocked',async()=>{
 const storage={get(){throw Error('Storage blocked')},set(){throw Error('Storage blocked')}}
 const h=await harness(storage)
 try{window.location.href+='&_app_version='+newer.version;await h.upgrade();await h.advance(30000);assert.equal(h.navigations.length,0);await h.apply();assert.equal(h.navigations.length,1)}finally{h.close()}
})
