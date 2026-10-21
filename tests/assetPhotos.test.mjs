import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import ts from 'typescript'
import React from 'react'
import {renderToStaticMarkup} from 'react-dom/server'
const require=createRequire(import.meta.url),source=readFileSync(new URL('../src/modules/AssetPhotos.tsx',import.meta.url),'utf8')
const js=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const mod={};new Function('require','exports',js)(name=>name==='../lib/supabase'||name==='../lib/partPhotos'?{}:require(name),mod)
test('equipment, shared photographs and schematic references are visibly distinguished',()=>{
 const rows=['equipment','shared_equipment','schematic'].map((kind,i)=>({id:String(i),kind,caption:'<script>Not HTML</script>',asset_photo_images:{image_data:'/9j/AA==',mime_type:'image/jpeg',source_name:'source.jpg'}}))
 const html=renderToStaticMarkup(React.createElement(mod.AssetPhotoGallery,{rows}))
 assert.match(html,/Equipment photo/);assert.match(html,/Shared equipment view/);assert.match(html,/physical photo pending/);assert.match(html,/data:image\/jpeg;base64,\/9j\/AA==/);assert.match(html,/&lt;script&gt;Not HTML&lt;\/script&gt;/);assert.doesNotMatch(html,/<script>/)
})
test('commissioning register has unique codes, known parents and traceable source photos',()=>{
 const m=JSON.parse(readFileSync(new URL('../data/peace-river-commissioning-2026-10-21.json',import.meta.url),'utf8'));const codes=new Set(m.assets.map(a=>a.code)),photos=new Set(m.source_photographs.map(p=>p.photo))
 assert.equal(codes.size,m.assets.length);assert.equal(m.business_unit_code,'CONC-PR');assert.equal(photos.size,9)
 for(const asset of m.assets){assert.match(asset.code,/^PRC-[A-Z]{3}-[A-Z0-9]{3}$|^PRC-[A-Z]{3}-[A-Z]{3}-\d{3}$/);if(asset.parent){assert.ok(codes.has(asset.parent));assert.notEqual(asset.parent,asset.code)}if(asset.photo)assert.ok(photos.has(asset.photo));if(asset.photo_kind==='schematic')assert.ok(asset.notes.length>20)}
 const bays=m.assets.filter(a=>a.code.startsWith('PRC-RMS-'));assert.equal(bays.length,4);assert.ok(bays.every(a=>a.photo===null));assert.equal(m.assets.filter(a=>/^PRC-CEM-BLR-/.test(a.code)).length,2)
 assert.equal(m.assets.filter(a=>/^PRC-ADM-DOS-00[1-7]$/.test(a.code)).length,7);assert.ok(!codes.has('PRC-ADM-DOS-008'))
})
