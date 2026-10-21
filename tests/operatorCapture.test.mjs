import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import ts from 'typescript'
import React from 'react'
import {renderToStaticMarkup} from 'react-dom/server'
const source=readFileSync(new URL('../src/modules/OperatorObservationForm.tsx',import.meta.url),'utf8')
const js=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const mod={};new Function('require','exports',js)(createRequire(import.meta.url),mod)
const base={form:{business_unit_id:'unit',asset_id:'',observation_type:'equipment',description:'',immediate_concern:'normal'},setForm:()=>{},units:[{id:'unit',name:'Test unit'}],assets:[{id:'asset',business_unit_id:'unit',asset_code:'MIX-001',name:'Mixer'}],photos:[],recording:false,saving:false,preparingPhotos:false,online:true,loading:false,onSubmit:()=>{},onVoice:()=>{},onPhotos:()=>{},onRemovePhoto:()=>{},onPhotoCaption:()=>{}}
function render(p={}){return renderToStaticMarkup(React.createElement(mod.default,{...base,...p}))}
function disabled(html){return /<button type="submit"[^>]*disabled/.test(html)}
test('equipment report requires an asset from its site and a description before sending',()=>{
 assert.equal(disabled(render()),true)
 assert.equal(disabled(render({form:{...base.form,description:'Oil leak'}})),true)
 assert.equal(disabled(render({form:{...base.form,asset_id:'asset',description:'Oil leak'}})),false)
 assert.equal(disabled(render({form:{...base.form,asset_id:'asset',description:'Oil leak',business_unit_id:'another-unit'}})),true)
})
test('recording and photo preparation block sending; preparing a photo is never labelled as sending',()=>{
 const form={...base.form,asset_id:'asset',description:'Oil leak'}
 assert.equal(disabled(render({form,recording:true})),true)
 assert.match(render({form,recording:true}),/STOP RECORDING/)
 const prepared=render({form,preparingPhotos:true});assert.equal(disabled(prepared),true);assert.match(prepared,/PREPARING PHOTOS/);assert.doesNotMatch(prepared,/SENDING/)
})
test('offline reports are clearly queued rather than falsely reported as delivered',()=>{
 const html=render({form:{...base.form,asset_id:'asset',description:'Oil leak'},online:false})
 assert.match(html,/SAVE ON THIS PHONE/);assert.match(html,/Will send when connection returns/)
})
test('safety reporting remains possible without a specific machine and exposes urgent instructions',()=>{
 const html=render({form:{...base.form,observation_type:'safety',description:'Unsafe walkway'}})
 assert.equal(disabled(html),false);assert.match(html,/Notify your supervisor now/)
})
test('camera captures from the rear camera, previews attachments, and reports an empty asset catalogue',()=>{
 const html=render({photos:[{id:'photo',url:'blob:local-photo',caption:''}]})
 assert.match(html,/capture="environment"/);assert.match(html,/Observation photo 1/);assert.match(html,/Remove photo 1/)
 assert.match(render({assets:[]}),/No equipment is registered for this site/)
})

test('leadership and supervisor capture retains process, facility and other observations',()=>{
 const html=render({allowAllTypes:true,form:{...base.form,observation_type:'process',description:'Loading procedure improvement'}})
 assert.equal(disabled(html),false);assert.match(html,/>Process<\/button>/);assert.match(html,/>Facility<\/button>/);assert.match(html,/>Other<\/button>/)
 assert.doesNotMatch(render(),/>Process<\/button>/)
})

// Render the actual observation screen to verify the compact layout is separate from role permissions.
const fieldSource=readFileSync(new URL('../src/modules/ObservationsSection.tsx',import.meta.url),'utf8')
const fieldJs=ts.transpileModule(fieldSource,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const fieldMod={};const nativeRequire=createRequire(import.meta.url)
new Function('require','exports',fieldJs)(name=>{
 if(name.endsWith('.css'))return {}
 if(name==='./OperatorObservationForm')return mod
 if(name==='./ObservationEvidence'||name==='./ObservationConversation')return {__esModule:true,default:()=>null}
 if(name==='../lib/supabase'||name==='../lib/observationOfflineStore')return {}
 return nativeRequire(name)
},fieldMod)
Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true})
function fieldScreen(role,compact){return renderToStaticMarkup(React.createElement(fieldMod.default,{units:base.units,userId:'current-user',role,compact}))}
test('all non-operator roles get the phone capture screen with their wider report types',()=>{
 for(const role of ['super_admin','corporate_manager','unit_supervisor','technician','ohs_admin','viewer']){
  const html=fieldScreen(role,true)
  for(const text of ['See it. Report it.','TAKE PHOTO','RECORD VOICE','SEND OBSERVATION','Reports &amp; review','Process'])assert.ok(html.includes(text),`${role}: ${text}`)
  assert.doesNotMatch(html,/Safety responsibility routing/)
  assert.doesNotMatch(html,/Choose your work site first/)
 }
})
test('desktop administration stays in the full review layout, while operators keep direct capture',()=>{
 const desktop=fieldScreen('super_admin',false);assert.match(desktop,/Safety responsibility routing/);assert.match(desktop,/Report observation/);assert.doesNotMatch(desktop,/TAKE PHOTO/)
 for(const compact of [false,true]){const operator=fieldScreen('operator',compact);assert.match(operator,/TAKE PHOTO/);assert.match(operator,/My reports/);assert.doesNotMatch(operator,/Reports &amp; review|>Process</)}
})

const evidenceSource=readFileSync(new URL('../src/modules/ObservationEvidence.tsx',import.meta.url),'utf8')
const evidenceJs=ts.transpileModule(evidenceSource,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const evidenceMod={};new Function('require','exports',evidenceJs)(name=>name==='../lib/supabase'?{}:nativeRequire(name),evidenceMod)
test('review shows uploaded photos inline, keeps captions literal, and links PDFs without popup scripts',()=>{
 const image={id:'photo',storage_path:'private/photo.jpg',file_name:'photo.jpg',mime_type:'image/jpeg',caption:'<script>photo note</script>',url:'https://example.test/signed/photo'}
 const pdf={...image,id:'pdf',mime_type:'application/pdf',file_name:'report.pdf',caption:'Document',url:'https://example.test/signed/pdf'}
 const html=renderToStaticMarkup(React.createElement(evidenceMod.ObservationEvidenceGallery,{items:[image,pdf],failed:[],onImageError:()=>{}}))
 assert.match(html,/<img[^>]*src="https:\/\/example.test\/signed\/photo"/);assert.equal((html.match(/<img /g)||[]).length,1)
 assert.match(html,/Open full photo/);assert.match(html,/Open report.pdf/);assert.match(html,/rel="noopener noreferrer"/)
 assert.match(html,/&lt;script&gt;photo note&lt;\/script&gt;/);assert.doesNotMatch(html,/<script>/)
})
test('expired or denied photo links show a retry message instead of a broken or public image',()=>{
 for(const [url,failed] of [[null,[]],['https://example.test/expired',['photo']]]){
 const html=renderToStaticMarkup(React.createElement(evidenceMod.ObservationEvidenceGallery,{items:[{id:'photo',mime_type:'image/jpeg',file_name:'photo.jpg',url,caption:null}],failed,onImageError:()=>{}}))
 assert.doesNotMatch(html,/<img|href=/);assert.match(html,/Refresh photos to retry/)
 }
})
