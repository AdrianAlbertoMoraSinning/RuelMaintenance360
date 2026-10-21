import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'
import {operatorUsername,operatorAuthAddress} from '../supabase/functions/_shared/operatorIdentity.ts'
import {operatorInvitationMode,operatorAccessUrl} from '../supabase/functions/_shared/operatorInvitation.ts'
import {supervisorInvitationHtml} from '../supabase/functions/_shared/supervisorInvitation.ts'
import {supervisorInvitationRecipients} from '../supabase/functions/_shared/invitationRecipients.ts'
const source=readFileSync(new URL('../supabase/functions/admin-user-security/index.ts',import.meta.url),'utf8').replace(/^import .*$/gm,'')
const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
function fixture({active=true,missingManager=false,callerRole='super_admin',deliveryFails=false}={}){
 const id='b6a1f147-ae25-4b3e-bdb5-f35c5b4addba',emails=[],rpcs=[],events=[];let serve
 const profiles={admin:{id:'admin',active:true,role:callerRole},[id]:{id,active:true,role:'operator',full_name:'DJ <operator>',phone:'+17806252210',email:null,corporate_manager_id:'don'},don:{id:'don',active:true,email:'don@ruelconcreteltd.com',full_name:'Don',corporate_manager_id:missingManager?null:'adrian'},adrian:{id:'adrian',active:true,email:'concrete@ruelconcreteltd.com',full_name:'Adrian'}}
 const admin={from(table){let key;return {select(){return this},eq(_,v){key=v;return this},async single(){return{data:table==='personnel_onboarding'?{profile_id:id,status:active?'active':'pending_invitation'}:profiles[key],error:null}},async insert(v){events.push(v);return{error:null}}}},rpc:async(name)=>{rpcs.push(name);return{data:'2026-10-25T12:00:00Z',error:null}},auth:{admin:new Proxy({},{get(){throw new Error('Must not change an Auth account during resend')}})}}
 const caller={auth:{getUser:async()=>({data:{user:{id:'admin'}},error:null})}}
 new Function('createClient','operatorUsername','operatorAuthAddress','supervisorInvitationRecipients','supervisorInvitationHtml','operatorInvitationMode','operatorAccessUrl','Deno','fetch',js)((_,__,opts)=>opts?.global?caller:admin,operatorUsername,operatorAuthAddress,supervisorInvitationRecipients,supervisorInvitationHtml,operatorInvitationMode,operatorAccessUrl,{serve:fn=>serve=fn,env:{get:key=>key}},async(url,opts)=>{emails.push(JSON.parse(opts.body));return new Response(JSON.stringify(deliveryFails?{error:'rejected'}:{id:'email-1'}),{status:deliveryFails?503:200})})
 return {emails,rpcs,events,send:()=>serve(new Request('https://test.invalid',{method:'POST',body:JSON.stringify({action:'create_forwarded_invitation',user_id:id,send_email:true})}))}
}
test('active operator can repeatedly resend to supervisor + manager without issuing tokens or changing Auth',async()=>{
 const h=fixture();for(let n=0;n<2;n++){const r=await h.send();assert.equal(r.status,200);const body=await r.json();assert.equal(body.mode,'access_installation');assert.equal(body.activation_url,operatorAccessUrl());assert.equal(body.expires_at,null);assert.equal(body.delivery_id,'email-1')}
 assert.equal(h.rpcs.length,0);assert.equal(h.emails.length,2);assert.deepEqual(h.emails[0].to,['don@ruelconcreteltd.com']);assert.deepEqual(h.emails[0].cc,['concrete@ruelconcreteltd.com']);assert.match(h.emails[0].html,/RUEL OPERATORS/);assert.match(h.emails[0].html,/Add to Home Screen/);assert.match(h.emails[0].html,/existing password/);assert.match(h.emails[0].html,/DJ &lt;operator&gt;/);assert.doesNotMatch(h.emails[0].html,/#invite=/)
})
test('pending operator gets a replacement one-time setup link and installation instructions',async()=>{
 const h=fixture({active:false}),r=await h.send(),body=await r.json();assert.equal(r.status,200);assert.equal(body.mode,'activation');assert.match(body.activation_url,/setup=forwarded&operator_app=1#invite=[a-f0-9]{64}$/);assert.deepEqual(h.rpcs,['issue_forwarded_operator_invitation']);assert.match(h.emails[0].html,/Works once/);assert.match(h.emails[0].html,/install.*RUEL Operators/)
})
test('missing manager, unauthorized caller and rejected delivery cannot report a sent email',async()=>{
 for(const opts of [{missingManager:true},{callerRole:'operator'},{deliveryFails:true}]){const h=fixture(opts),r=await h.send();assert.notEqual(r.status,200);assert.equal((await r.json()).ok,undefined);assert.equal(h.events.length,0);if(!opts.deliveryFails)assert.equal(h.emails.length,0)}
})
test('installed app launch stays reusable and never stores an activation token or login in its manifest',()=>{
 const manifest=JSON.parse(readFileSync(new URL('../public/operator.webmanifest',import.meta.url),'utf8'));assert.equal(manifest.name,'RUEL Operators');assert.equal(manifest.start_url,'/?operator_app=1');assert.equal(manifest.display,'standalone');assert.doesNotMatch(JSON.stringify(manifest),/invite=|password|op-b6/)
})
