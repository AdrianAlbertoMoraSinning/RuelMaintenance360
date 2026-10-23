import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import ts from 'typescript'
import React from 'react'
import {renderToStaticMarkup} from 'react-dom/server'
import * as model from '../src/lib/deliveryGeofence.ts'
const native=createRequire(import.meta.url),zone={latitude:56,longitude:-117,radius_m:150}
const load={id:'load',driver_id:'driver',load_number:1,status:'ready',plant_zone:zone,site_zone:zone}
const position=(overrides={})=>({coords:{latitude:56,longitude:-117,accuracy:10,...overrides},timestamp:Date.now()})
test('location fixes reject stale, imprecise, nonfinite and out-of-range GPS data',()=>{
 assert.ok(model.locationSample(position()));for(const patch of [{accuracy:51},{accuracy:-1},{latitude:NaN},{longitude:181}])assert.equal(model.locationSample(position(patch)),null)
 assert.equal(model.locationSample({...position(),timestamp:Date.now()-46000}),null);assert.equal(model.locationSample({...position(),timestamp:Date.now()+6000}),null)
})
test('only configured ready or active assigned loads are tracked; recent completion can still record site exit',()=>{
 const loads=[load,{...load,id:'scheduled',status:'scheduled'},{...load,id:'other',driver_id:'other'},{...load,id:'unconfigured',plant_zone:null},{...load,id:'done',status:'completed',completed_at:new Date().toISOString()},{...load,id:'left',status:'arrived',left_site_at:new Date().toISOString()},{...load,id:'old',status:'completed',completed_at:new Date(Date.now()-13*3600000).toISOString()}]
 assert.deepEqual(model.locationLoads(loads,'driver').map(l=>l.id),['done']);assert.deepEqual(model.locationLoads([load],'driver').map(l=>l.id),['load'])
})
function harness({blocked=false,hidden=false,online=true}={}){
 const effects=[],calls=[],cleared=[],timers=[];let success,failure,slot=0
 const doc={visibilityState:hidden?'hidden':'visible',addEventListener(){},removeEventListener(){}}
 const nav={onLine:online,geolocation:{watchPosition(ok,fail){success=ok;failure=fail;return 7},clearWatch(id){cleared.push(id)},getCurrentPosition(){}}}
 const react={...React,useState(initial){const i=slot++;return[i===0?true:i===1?!hidden:typeof initial==='function'?initial():initial,()=>{}]},useRef:value=>({current:value}),useEffect:fn=>effects.push(fn)}
 const js=ts.transpileModule(readFileSync(new URL('../src/modules/DeliveryGeofence.tsx',import.meta.url),'utf8'),{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
 const mod={};new Function('require','exports','navigator','document','setInterval','clearInterval',js)(name=>name==='react'?react:name==='../lib/deliveryGeofence'?model:name==='../lib/supabase'?{supabase:{rpc:async(name,data)=>{calls.push({name,data});return{data:{event:null,notice:'Active'}}}}}:name==='../lib/useUpdateBlocker'?{useUpdateBlocker(){}}:native(name),mod,nav,doc,fn=>{timers.push(fn);return 9},id=>cleared.push(id))
 const html=renderToStaticMarkup(React.createElement(mod.default,{loads:[load],userId:'driver',blocked,onChange(){},onWorking(){}}));const cleanup=effects.at(-1)()
 return{html,calls,cleared,doc,fix:p=>success?.(p),fail:e=>failure?.(e),cleanup}
}
test('foreground assistance sends only an account-bound sample and clears GPS and heartbeat on cleanup',async()=>{
 const h=harness();assert.match(h.html,/completion stays manual/);assert.match(h.html,/Locking the phone/);await h.fix(position());assert.equal(h.calls.length,1);assert.equal(h.calls[0].data.p_data.actor_id,'driver');assert.equal(h.calls[0].data.p_action,'sample');assert.equal(h.calls[0].data.p_data.event,undefined);h.cleanup();assert.deepEqual(h.cleared,[7,9]);await h.fix(position());assert.equal(h.calls.length,1)
})
test('hidden, offline, blocked or poor GPS conditions never create an automatic event',async()=>{
 for(const options of [{hidden:true},{online:false},{blocked:true},{}]){const h=harness(options);await h.fix(position(options.hidden||options.online===false||options.blocked?{}:{accuracy:99}));assert.equal(h.calls.length,0);h.cleanup?.()}
 const h=harness();h.doc.visibilityState='hidden';await h.fix(position());assert.equal(h.calls.length,0);h.cleanup()
})

test('future ready loads never auto-depart while another delivery is active, even without site coordinates',()=>{
 const next={...load,id:'next',load_number:2};assert.deepEqual(model.locationLoads([load,next],'driver').map(l=>l.id),['load']);
 assert.deepEqual(model.locationLoads([{...load,status:'departed',site_zone:null},next],'driver'),[]);
});

test('planned departure order drives GPS load selection even if assignments were created out of sequence',()=>{const late={...load,id:'late',load_number:1,planned_departure_at:'2026-10-24T16:00Z'},early={...load,id:'early',load_number:2,planned_departure_at:'2026-10-24T14:00Z'};assert.deepEqual(model.locationLoads([late,early],'driver').map(l=>l.id),['early']);assert.deepEqual(model.locationLoads([{...late,status:'departed'},early],'driver').map(l=>l.id),['late'])})
