import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import ts from 'typescript'
import React from 'react'
import {renderToStaticMarkup} from 'react-dom/server'
import {joinPartMachines,loadPartMachines} from '../src/lib/partMachineLookup.ts'
const link=(asset_id,part_id='bearing',relationship_type='installed')=>({asset_id,part_id,relationship_type,installed_quantity:relationship_type==='installed'?'2':'99',component_system:'Drive',installation_position:'Pump outlet'})
const machine=id=>({id,asset_code:'MIX-'+id,name:'Mixer '+id,business_unit_id:'unit'})
test('the same suggested bearing lists installed and compatible machines using recorded relations only',()=>{
 const rows=joinPartMachines(['bearing'],[link('A'),link('B','bearing','compatible'),link('A'),link('hidden'),link('C','unmatched'),link('D','bearing','invented')],['A','B','C','D'].map(machine),[{id:'unit',name:'Concrete Plant'}])
 assert.equal(rows.length,2);assert.equal(rows[0].relationship_type,'installed');assert.equal(rows[0].installed_quantity,2);assert.equal(rows[1].installed_quantity,0)
 assert.equal(rows[0].business_unit_name,'Concrete Plant');assert.equal(rows[0].installation_position,'Pump outlet')
 assert.deepEqual(rows.map(r=>r.asset_id),['A','B'])
})
function client(tables,failure){const calls=[];return {calls,from(table){const filters=[];let range=null;const q={select(fields){calls.push({table,fields});return q},in(key,values){filters.push([key,values]);return q},order(){return q},range(a,b){range=[a,b];return q},then(ok,bad){if(table===failure)return Promise.resolve({data:null,error:new Error('Read denied')}).then(ok,bad);let rows=tables[table]||[];for(const[key,values]of filters)rows=rows.filter(r=>values.includes(r[key]));if(range)rows=rows.slice(range[0],range[1]+1);return Promise.resolve({data:rows,error:null}).then(ok,bad)}};return q}}}
test('a machine-scoped photo match still lists all authorized machines for that part across paginated reads',async()=>{
 const links=Array.from({length:501},(_,i)=>link(String(i)))
 const db=client({asset_part_compatibility:links,assets:links.slice(0,500).map(l=>machine(l.asset_id)),business_units:[{id:'unit',name:'Authorized unit'}]})
 const rows=await loadPartMachines(db,['bearing']);assert.equal(rows.length,500);assert.equal(rows.some(r=>r.asset_id==='500'),false)
 assert.equal(db.calls.filter(c=>c.table==='asset_part_compatibility').length,2)
 assert.ok(db.calls.filter(c=>c.table==='assets').length>1)
 assert.equal(db.calls.some(c=>/cost|price/.test(c.fields)),false)
})
test('empty matches perform no reads and a failed machine lookup is not misrepresented as no associations',async()=>{
 const empty=client({});assert.deepEqual(await loadPartMachines(empty,[]),[]);assert.equal(empty.calls.length,0)
 const failed=client({asset_part_compatibility:[link('A')]},'assets');await assert.rejects(()=>loadPartMachines(failed,['bearing']),/Read denied/)
})
const source=readFileSync(new URL('../src/modules/PartMachineMatches.tsx',import.meta.url),'utf8')
const js=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
const mod={};new Function('require','exports',js)(createRequire(import.meta.url),mod)
const render=props=>renderToStaticMarkup(React.createElement(mod.default,{machines:[],loading:false,error:'',...props}))
test('results distinguish installation from compatibility and make empty/loading/error states explicit',()=>{
 const rows=joinPartMachines(['bearing'],[link('A'),link('B','bearing','compatible')],[machine('A'),machine('B')],[{id:'unit',name:'Concrete Plant'}])
 const html=render({machines:rows});assert.match(html,/MIX-A/);assert.match(html,/MIX-B/);assert.match(html,/Recorded as installed/);assert.match(html,/Recorded as compatible spare/);assert.match(html,/Quantity installed: 2/)
 assert.doesNotMatch(html,/Quantity installed: 99/);assert.match(html,/Drive · Pump outlet/)
 assert.match(render({loading:true}),/Loading registered/)
 assert.match(render({error:'Unavailable'}),/associations are unavailable/);assert.doesNotMatch(render({error:'Unavailable'}),/No machine associations/)
 assert.match(render({}),/No machine associations are visible/)
})
