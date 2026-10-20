import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'
import {operatorUsername,operatorAuthAddress} from '../supabase/functions/_shared/operatorIdentity.ts'
const source=readFileSync(new URL('../supabase/functions/redeem-operator-invitation/index.ts',import.meta.url),'utf8').replace(/^import .*$/gm,'')
const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
function handler(failUpdate=false){
 let serve,updated,finished=false,released=false
 const id='b6a1f147-ae25-4b3e-bdb5-f35c5b4addba'
 const admin={rpc:async(name)=>{if(name==='claim_forwarded_operator_invitation')return {data:{profile_id:id,phone:'+17806252210'}};if(name==='finish_forwarded_operator_invitation')finished=true;if(name==='release_forwarded_operator_invitation')released=true;return {data:null,error:null}},auth:{admin:{getUserById:async()=>({data:{user:{id,phone:'17806252210',app_metadata:{}}}}),updateUserById:async(_,attrs)=>{updated=attrs;return {error:failUpdate?new Error('rejected'):null}}}}}
 new Function('createClient','operatorUsername','operatorAuthAddress','Deno',js)(()=>admin,operatorUsername,operatorAuthAddress,{serve:f=>serve=f,env:{get:()=>''}})
 return {run:body=>serve(new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})),state:()=>({updated,finished,released})}
}
test('forwarded redemption uses username/password and removes legacy Auth phone, never requesting SMS',async()=>{
 const h=handler(),r=await h.run({action:'redeem',token:'a'.repeat(64),password:'Chosen only by operator'})
 assert.equal(r.status,200);assert.deepEqual(await r.json(),{activated:true,username:'op-b6a1f147ae25'})
 const state=h.state();assert.equal(state.updated.phone,'');assert.equal(state.updated.email,operatorAuthAddress('op-b6a1f147ae25'));assert.equal(state.updated.email_confirm,true);assert.equal(state.updated.phone_confirm,undefined);assert.equal(state.finished,true)
})
test('failed password submission releases claim and cannot report activation',async()=>{
 const h=handler(true),r=await h.run({action:'redeem',token:'a'.repeat(64),password:'Chosen only by operator'});assert.equal(r.status,400);assert.equal(h.state().released,true);assert.equal(h.state().finished,false)
})
