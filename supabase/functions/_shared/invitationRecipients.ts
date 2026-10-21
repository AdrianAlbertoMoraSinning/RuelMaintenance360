type RecipientProfile = {id:string;email:string|null;active:boolean}
export function supervisorInvitationRecipients(supervisor:RecipientProfile,manager:RecipientProfile|null){
 const to=supervisor.email?.trim().toLowerCase()
 if(!supervisor.active||!to||!/^\S+@\S+\.\S+$/.test(to))throw new Error('An active supervisor with a valid email is required')
 const copy=manager?.email?.trim().toLowerCase()
 if(!manager?.active||manager.id===supervisor.id||!copy||!/^\S+@\S+\.\S+$/.test(copy))throw new Error('Assign an active manager with a valid email to this supervisor before preparing an operator invitation')
 return {to:[to],cc:copy===to?[]:[copy]}
}
