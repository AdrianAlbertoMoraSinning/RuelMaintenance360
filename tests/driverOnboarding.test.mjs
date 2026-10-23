import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'
const source=readFileSync(new URL('../supabase/functions/admin-user-security/index.ts',import.meta.url),'utf8').replace(/^import .*$/gm,'')
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
function fixture({callerRole='super_admin',managerActive=true,pending=true,identityEmail=null,profileEmail=null}={}){
 const calls=[];let serve
 const profiles={admin:{id:'admin',role:callerRole,active:true},manager:{id:'manager',role:'unit_supervisor',active:managerActive},driver:{id:'driver',role:'driver',active:true,email:profileEmail}}
 const admin={
  from(table){let key;return{
   update(v){calls.push(['profile_update',v]);return this},select(){return this},eq(_,v){key=v;return this},
   single:async()=>({data:profiles[key]}),
   upsert:async v=>{calls.push(['profile',v]);return{}},
   insert:async v=>{calls.push(['audit',v]);return{}}
  }},
  auth:{admin:{getUserById:async()=>({data:{user:{id:'driver',email:identityEmail,app_metadata:{driver_pending_activation:pending}}}}),updateUserById:async(...args)=>{calls.push(['identity_update',...args]);return{}},inviteUserByEmail:async(...args)=>{calls.push(['invite',...args]);return{data:{user:{id:'driver'}}}}}}
 }
 const caller={auth:{getUser:async()=>({data:{user:{id:'admin'}}})}}
 new Function('createClient','appInvitationHtml','operatorInvitationMode','operatorAccessUrl','supervisorInvitationRecipients','supervisorInvitationHtml','operatorUsername','operatorAuthAddress','Deno',code)(
  (_,__,opts)=>opts?.global?caller:admin,()=>'',()=>'',()=>'',()=>[],()=>'',()=>'',()=>'',{serve:fn=>serve=fn,env:{get:key=>key}}
 )
 return{calls,send:body=>serve(new Request('https://test.invalid',{method:'POST',body:JSON.stringify(body)}))}
}
const request={action:'create_user',email:'driver@example.invalid',full_name:'QA Driver',role:'driver',personnel_category:'driver',corporate_manager_id:'manager'}
test('admin can invite a real Driver profile through the normal guarded onboarding path',async()=>{const h=fixture(),r=await h.send(request);assert.equal(r.status,200,JSON.stringify(await r.clone().json()));assert.equal(h.calls[0][0],'invite');const profile=h.calls.find(c=>c[0]==='profile')[1];assert.equal(profile.role,'driver');assert.equal(profile.personnel_category,'driver');assert.equal(profile.corporate_manager_id,'manager');assert.equal(profile.active,true)})
test('driver creation requires an authorized administrator and an active reporting manager before sending invitations',async()=>{for(const opts of [{callerRole:'driver'},{managerActive:false}]){const h=fixture(opts),r=await h.send(request);assert.notEqual(r.status,200);assert.equal(h.calls.length,0)}const h=fixture(),r=await h.send({...request,corporate_manager_id:''});assert.equal(r.status,400);assert.equal(h.calls.length,0)})
test('driver install entry is reusable and contains no personal credentials',()=>{const d=JSON.parse(readFileSync(new URL('../public/driver.webmanifest',import.meta.url),'utf8'));assert.equal(d.name,'RUEL Drivers');assert.equal(d.start_url,'/?driver_app=1');assert.equal(d.display,'standalone');assert.doesNotMatch(JSON.stringify(d),/token|password|invite=/i)})

test('pending Driver receives a real email on the same account without an invitation or password',async()=>{const h=fixture();const r=await h.send({action:'set_driver_email',user_id:'driver',email:'driver@example.ca'});assert.equal(r.status,200,JSON.stringify(await r.clone().json()));const ids=h.calls.filter(c=>c[0]==='identity_update');assert.equal(ids.length,2);assert.ok(ids.every(c=>c[1]==='driver'&&!('password' in c[2])));assert.equal(ids[0][2].email,'driver@example.ca');assert.equal(ids[1][2].ban_duration,'none');assert.equal(ids[1][2].app_metadata.driver_pending_activation,false);assert.equal(h.calls.filter(c=>c[0]==='invite').length,0);assert.ok(h.calls.some(c=>c[0]==='profile_update'&&c[1].email==='driver@example.ca'))})
test('pending Driver email setup rejects unauthorized callers, existing access and invented email domains',async()=>{for(const [opts,email] of [[{callerRole:'driver'},'driver@example.ca'],[{pending:false,identityEmail:'existing@example.ca',profileEmail:'existing@example.ca'},'driver@example.ca'],[{},'driver@pending.invalid']]){const h=fixture(opts);const r=await h.send({action:'set_driver_email',user_id:'driver',email});assert.notEqual(r.status,200);assert.equal(h.calls.length,0)}})
