// The verified administrator id comes from getUser(), never the request body.
export async function changeUserLifecycle(admin:any,actorId:string,targetId:string,action:'activate'|'deactivate'|'remove',confirmation=''){
 const args={p_actor_id:actorId,p_user_id:targetId,p_action:action,p_confirmation:confirmation,p_apply:false}
 const preflight=await admin.rpc('admin_user_lifecycle',args)
 if(preflight.error)throw preflight.error
 const identity=await admin.auth.admin.getUserById(targetId)
 if(identity.error&&identity.error.status!==404&&identity.error.code!=='user_not_found')throw identity.error
 const exists=!!identity.data?.user
 if(!exists&&action==='activate')throw Error('This profile has no sign-in account. Complete onboarding before activation.')
 const previousUntil=identity.data?.user?.banned_until
 const remaining=previousUntil?Math.max(0,Math.ceil((Date.parse(previousUntil)-Date.now())/1000)):0
 if(exists){const result=await admin.auth.admin.updateUserById(targetId,{ban_duration:action==='activate'?'none':'876000h'});if(result.error)throw result.error}
 const applied=await admin.rpc('admin_user_lifecycle',{...args,p_apply:true})
 if(applied.error){
  if(exists){const restored=await admin.auth.admin.updateUserById(targetId,{ban_duration:remaining>0?`${remaining}s`:'none'});if(restored.error)throw Error(`${applied.error.message}. Sign-in status could not be restored; review this account before retrying.`)}
  throw applied.error
 }
 return{ok:true,...applied.data}
}
