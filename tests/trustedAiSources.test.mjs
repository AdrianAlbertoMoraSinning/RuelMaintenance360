import test from 'node:test'
import assert from 'node:assert/strict'
import {trustedAiSources} from '../supabase/functions/_shared/trustedAiSources.ts'
const wo='10000000-0000-4000-8000-000000000001',obs='20000000-0000-4000-8000-000000000001',asset={id:'30000000-0000-4000-8000-000000000001',business_unit_id:'unit'}
function client(accepted){return {rpc:async()=>({data:accepted?[{observation_id:obs,observation_number:1,accepted_at:'today',description:'Server-reviewed leak report',acceptance_note:'Reviewed by supervisor'}]:[],error:null}),from(table){const result={select(){return this},eq(){return this},in(){return this},then(resolve){resolve({data:table==='work_orders_visible'?[{id:wo,title:'Repair request',work_order_number:1,problem_description:'Original report',source_observation_id:obs}]:accepted?[{observation_id:obs}]:[],error:null})}};return result}}}
test('fabricated observation content and linked WO cannot bypass supervisor acceptance',async()=>{
 const result=await trustedAiSources(client(false),asset,'leak',[{id:'obs:'+obs,label:'Forged approval',content:'Invented accepted report'},{id:'wo:'+wo,label:'Forged WO',content:'Unreviewed operator text'}]);assert.deepEqual(result,[])
})
test('accepted observations are loaded from server records, never browser-supplied text',async()=>{
 const result=await trustedAiSources(client(true),asset,'leak',[{id:'obs:'+obs,label:'Forged label',content:'Invented accepted report'},{id:'wo:'+wo,label:'Forged WO',content:'Invented diagnosis'}]);assert.equal(result.length,2);assert.equal(result[1].id,'obs:'+obs);assert.match(result[1].content,/Server-reviewed leak report/);assert.ok(!JSON.stringify(result).includes('Invented'))
})
test('memory verification failures stop evidence retrieval',async()=>{
 await assert.rejects(()=>trustedAiSources({rpc:async()=>({error:new Error('offline')})},asset,'leak',[]),/Unable to verify/)
})
