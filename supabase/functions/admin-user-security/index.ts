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
    const admin=createClient(url,service)
    const {data:caller}=await admin.from('profiles').select('id,role,active').eq('id',user.id).single()
    if(!caller?.active||!['super_admin','it_admin'].includes(caller.role)) return new Response(JSON.stringify({error:'Administrator access required'}),{status:403,headers:cors})

    const body=await req.json()
    const action=String(body.action||'')

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
