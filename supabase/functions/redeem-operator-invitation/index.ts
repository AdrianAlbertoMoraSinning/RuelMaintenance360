import {operatorUsername,operatorAuthAddress} from '../_shared/operatorIdentity.ts'
import {createClient} from 'npm:@supabase/supabase-js@2.58.0'
const headers={'Access-Control-Allow-Origin':'https://ruelmaintenance360.netlify.app','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers})
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers})
 if(req.method!=='POST')return reply({error:'POST required'},405)
 let hash='',claimed=false,passwordChanged=false
 const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}})
 try{
  const body=await req.json()
  if(typeof body.token!=='string'||!/^[a-f0-9]{64}$/.test(body.token))return reply({error:'This invitation is invalid or incomplete.'},400)
  hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(body.token))),x=>x.toString(16).padStart(2,'0')).join('')
  if(body.action==='inspect'){
   const{data,error}=await admin.rpc('inspect_forwarded_operator_invitation',{p_token_hash:hash})
   if(error)throw new Error('Unable to check invitation. Please try again.')
   if(!data)return reply({error:'This invitation has expired, was replaced or has already been used. Ask your supervisor for a new link.'},410)
   return reply({name:data.full_name,username:operatorUsername(data.profile_id),supervisor:data.supervisor,expires_at:data.expires_at})
  }
  if(body.action!=='redeem')return reply({error:'Unsupported action'},400)
  if(typeof body.password!=='string'||body.password.length<10)return reply({error:'Use a password of at least 10 characters.'},400)
  const{data:context,error:claimError}=await admin.rpc('claim_forwarded_operator_invitation',{p_token_hash:hash})
  if(claimError||!context)return reply({error:'This invitation has expired, is being processed or has already been used. Ask your supervisor for a new link.'},410)
  claimed=true
  const{data:identity,error:identityError}=await admin.auth.admin.getUserById(context.profile_id)
  const username=operatorUsername(context.profile_id),email=operatorAuthAddress(username)
  if(identityError||!identity.user||(identity.user.email&&identity.user.email!==email))throw new Error('Account details changed. Ask your supervisor for a new invitation.')
  // Possession of the link forwarded by the assigned supervisor is the enrollment proof.
  // Phone is contact information only. No phone authentication or SMS is used.
  const{error:updateError}=await admin.auth.admin.updateUserById(context.profile_id,{password:body.password,email,email_confirm:true,phone:'',app_metadata:{...identity.user.app_metadata,operator_username:username}})
  if(updateError)throw new Error('Password could not be saved. Please use a different password or try again.')
  passwordChanged=true
  const{error:finishError}=await admin.rpc('finish_forwarded_operator_invitation',{p_token_hash:hash})
  if(finishError)throw new Error('Your password was saved, but activation needs administrator review. Please contact your supervisor.')
  return reply({activated:true,username})
 }catch(error){
  if(claimed&&!passwordChanged)await admin.rpc('release_forwarded_operator_invitation',{p_token_hash:hash})
  return reply({error:error instanceof Error?error.message:'Unable to process invitation. Please try again.'},400)
 }
})
