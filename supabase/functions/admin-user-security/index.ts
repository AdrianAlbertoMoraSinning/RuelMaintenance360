import { createClient } from 'npm:@supabase/supabase-js@2.58.0'

const cors={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
  'Content-Type':'application/json'
}
const roles=['super_admin','it_admin','corporate_manager','ohs_admin','unit_supervisor','technician','operator','viewer']
const categories=['ceo','shareholder','manager','supervisor','operator','technician','administration','other']

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors})
  try{
    const authHeader=req.headers.get('Authorization')||''
    const url=Deno.env.get('SUPABASE_URL')!
    const anon=Deno.env.get('SUPABASE_ANON_KEY')!
    const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const callerClient=createClient(url,anon,{global:{headers:{Authorization:authHeader}}})
    const {data:{user},error:userError}=await callerClient.auth.getUser()
    if(userError||!user) return new Response(JSON.stringify({error:'Unauthorized'}),{status:401,headers:cors})
    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}})
    const {data:caller}=await admin.from('profiles').select('id,role,active').eq('id',user.id).single()
    if(!caller?.active||!['super_admin','it_admin'].includes(caller.role)) return new Response(JSON.stringify({error:'Administrator access required'}),{status:403,headers:cors})

    const body=await req.json()
    const action=String(body.action||'')

    if(action==='activate_phone_onboarding'){
      const rosterId=String(body.onboarding_id||'')
      const {data:roster,error:rosterError}=await admin.from('personnel_onboarding').select('*').eq('id',rosterId).single()
      if(rosterError||!roster)return new Response(JSON.stringify({error:'Personnel record not found'}),{status:404,headers:cors})
      if(roster.role!=='operator'||!roster.phone||!/^\+[1-9]\d{7,14}$/.test(roster.phone))return new Response(JSON.stringify({error:'A registered operator with a valid mobile number is required'}),{status:400,headers:cors})
      const {data:manager}=await admin.from('profiles').select('id,role,active').eq('id',roster.reporting_manager_id).single()
      const {data:unitAccess}=await admin.from('user_unit_access').select('user_id').eq('user_id',roster.reporting_manager_id).eq('business_unit_id',roster.business_unit_id).maybeSingle()
      if(!manager?.active||!['unit_supervisor','corporate_manager','super_admin'].includes(manager.role)||!unitAccess)return new Response(JSON.stringify({error:'An active reporting manager in this unit is required'}),{status:400,headers:cors})
      let newId=roster.profile_id
      if(!newId){
        const {data:existing}=await admin.from('profiles').select('id').eq('phone',roster.phone).maybeSingle()
        if(existing)return new Response(JSON.stringify({error:'Mobile number already belongs to another profile. Review the existing account.'}),{status:409,headers:cors})
        const {data:created,error:createError}=await admin.auth.admin.createUser({phone:roster.phone,phone_confirm:false,user_metadata:{full_name:roster.full_name}})
        if(createError)throw createError
        newId=created.user?.id
        if(!newId)throw new Error('Unable to create phone account')
        // Retain identity immediately: retry resumes this exact Auth account.
        const {error:linkError}=await admin.from('personnel_onboarding').update({profile_id:newId,status:'pending_invitation'}).eq('id',rosterId)
        if(linkError)throw linkError
      }
      const {data:identity,error:identityError}=await admin.auth.admin.getUserById(newId)
      if(identityError||identity.user?.phone?.replace(/^\+/,'')!==roster.phone.slice(1))throw new Error('Registered phone does not match the authentication account')
      if(roster.status==='active')return new Response(JSON.stringify({error:'This operator is already activated. Use the normal sign-in screen.'}),{status:409,headers:cors})
      const {error:profileError}=await admin.from('profiles').upsert({id:newId,phone:roster.phone,full_name:roster.full_name,role:'operator',personnel_category:'operator',position_title:roster.position_title||'Concrete Plant Operator',corporate_manager_id:roster.reporting_manager_id,active:true},{onConflict:'id'})
      if(profileError)throw profileError
      const {error:accessError}=await admin.from('user_unit_access').upsert({user_id:newId,business_unit_id:roster.business_unit_id,access_role:'operator',can_edit:false,can_approve:false},{onConflict:'user_id,business_unit_id'})
      if(accessError)throw accessError
      await admin.from('admin_security_events').insert({actor_user_id:user.id,target_user_id:newId,action:'phone_operator_provisioned'})
      if(body.send_sms!==true)return new Response(JSON.stringify({ok:true,user_id:newId,sms_sent:false,message:'Phone account created. No SMS sent.'}),{headers:cors})
      if(roster.sms_sent_at&&Date.now()-Date.parse(roster.sms_sent_at)<60000)return new Response(JSON.stringify({error:'Wait one minute before resending.'}),{status:429,headers:cors})
      const phoneClient=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}})
      const {error:smsError}=await phoneClient.auth.signInWithOtp({phone:roster.phone,options:{shouldCreateUser:false}})
      if(smsError){
        await admin.from('personnel_onboarding').update({status:'pending_invitation',invitation_error:smsError.message}).eq('id',rosterId)
        return new Response(JSON.stringify({ok:true,user_id:newId,sms_sent:false,message:'Account created. SMS not sent: '+smsError.message}),{headers:cors})
      }
      const {error:sentError}=await admin.from('personnel_onboarding').update({status:'invited',sms_sent_at:new Date().toISOString(),invitation_error:null}).eq('id',rosterId)
      if(sentError)throw new Error('SMS provider accepted the request, but the personnel status could not be saved. Check before resending.')
      await admin.from('admin_security_events').insert({actor_user_id:user.id,target_user_id:newId,action:'phone_invitation_sms_requested'})
      return new Response(JSON.stringify({ok:true,user_id:newId,sms_sent:true,message:'SMS code requested. Delivery is not yet confirmed.'}),{headers:cors})
    }

    if(action==='create_user'){
      const email=String(body.email||'').trim().toLowerCase()
      const fullName=String(body.full_name||'').trim()
      const positionTitle=String(body.position_title||'').trim()||null
      const role=String(body.role||'viewer')
      const category=String(body.personnel_category||'other')
      const managerId=body.corporate_manager_id?String(body.corporate_manager_id):null
      if(!email||!/^\S+@\S+\.\S+$/.test(email)) return new Response(JSON.stringify({error:'A valid email is required'}),{status:400,headers:cors})
      if(!fullName) return new Response(JSON.stringify({error:'Full name is required'}),{status:400,headers:cors})
      if(!roles.includes(role)||!categories.includes(category)) return new Response(JSON.stringify({error:'Invalid role or personnel category'}),{status:400,headers:cors})
      if(!['super_admin','it_admin','ohs_admin'].includes(role)&&!managerId) return new Response(JSON.stringify({error:'Reporting Manager is required for operational users'}),{status:400,headers:cors})
      if(managerId){const {data:mgr}=await admin.from('profiles').select('id,active,role').eq('id',managerId).single();if(!mgr?.active||!['corporate_manager','super_admin','unit_supervisor'].includes(mgr.role))return new Response(JSON.stringify({error:'Reporting Manager must be an active Supervisor, Corporate Manager, or Super Admin'}),{status:400,headers:cors})}
      const {data:invited,error:inviteError}=await admin.auth.admin.inviteUserByEmail(email,{data:{full_name:fullName}})
      if(inviteError) throw inviteError
      const newId=invited.user?.id
      if(!newId) throw new Error('Unable to create invited user')
      const {error:profileError}=await admin.from('profiles').upsert({id:newId,email,full_name:fullName,role,personnel_category:role==='ohs_admin'?'administration':category,position_title:role==='ohs_admin'?(positionTitle||'OHS Administrator'):positionTitle,corporate_manager_id:managerId,active:true},{onConflict:'id'})
      if(profileError) throw profileError
      await admin.from('admin_security_events').insert({actor_user_id:user.id,target_user_id:newId,action:role==='ohs_admin'?'ohs_administrator_invited':'user_invited'})
      return new Response(JSON.stringify({ok:true,user_id:newId}),{headers:cors})
    }

    const targetUserId=String(body.user_id||'')
    if(!targetUserId) return new Response(JSON.stringify({error:'user_id is required'}),{status:400,headers:cors})
    const {data:target}=await admin.from('profiles').select('id,role,active').eq('id',targetUserId).single()
    if(!target) return new Response(JSON.stringify({error:'Target user not found'}),{status:404,headers:cors})

    if(action==='set_password'){
      const password=String(body.password||'')
      if(password.length<10) return new Response(JSON.stringify({error:'Password must be at least 10 characters'}),{status:400,headers:cors})
      const {error}=await admin.auth.admin.updateUserById(targetUserId,{password})
      if(error) throw error
      await admin.from('admin_security_events').insert({actor_user_id:user.id,target_user_id:targetUserId,action:'password_changed'})
      return new Response(JSON.stringify({ok:true}),{headers:cors})
    }

    if(action==='set_active'){
      const active=Boolean(body.active)
      if(targetUserId===user.id&&!active) return new Response(JSON.stringify({error:'You cannot deactivate your own account'}),{status:400,headers:cors})
      const {error}=await admin.auth.admin.updateUserById(targetUserId,{ban_duration:active?'none':'876000h'})
      if(error) throw error
      const {error:profileError}=await admin.from('profiles').update({active}).eq('id',targetUserId)
      if(profileError) throw profileError
      await admin.from('admin_security_events').insert({actor_user_id:user.id,target_user_id:targetUserId,action:active?'user_activated':'user_deactivated'})
      return new Response(JSON.stringify({ok:true}),{headers:cors})
    }

    if(action==='update_profile'){
      const patch:any={}
      if('full_name' in body) patch.full_name=String(body.full_name||'').trim()||null
      if('position_title' in body) patch.position_title=String(body.position_title||'').trim()||null
      if('role' in body){const v=String(body.role);if(!roles.includes(v)) return new Response(JSON.stringify({error:'Invalid role'}),{status:400,headers:cors});patch.role=v;if(v==='ohs_admin'){patch.personnel_category='administration';if(!('position_title' in body))patch.position_title='OHS Administrator'}}
      if('personnel_category' in body){const v=String(body.personnel_category);if(!categories.includes(v)) return new Response(JSON.stringify({error:'Invalid personnel category'}),{status:400,headers:cors});patch.personnel_category=v}
      if('avatar_url' in body) patch.avatar_url=body.avatar_url?String(body.avatar_url):null
      if('corporate_manager_id' in body){const managerId=body.corporate_manager_id?String(body.corporate_manager_id):null;if(managerId===targetUserId)return new Response(JSON.stringify({error:'A user cannot be their own manager'}),{status:400,headers:cors});if(managerId){const {data:mgr}=await admin.from('profiles').select('id,active,role').eq('id',managerId).single();if(!mgr?.active||!['corporate_manager','super_admin','unit_supervisor'].includes(mgr.role))return new Response(JSON.stringify({error:'Reporting Manager must be an active Supervisor, Corporate Manager, or Super Admin'}),{status:400,headers:cors})}patch.corporate_manager_id=managerId}
      const {error}=await admin.from('profiles').update(patch).eq('id',targetUserId)
      if(error) throw error
      return new Response(JSON.stringify({ok:true}),{headers:cors})
    }

    return new Response(JSON.stringify({error:'Unsupported action'}),{status:400,headers:cors})
  }catch(error){
    return new Response(JSON.stringify({error:error instanceof Error?error.message:'Unexpected error'}),{status:500,headers:cors})
  }
})
