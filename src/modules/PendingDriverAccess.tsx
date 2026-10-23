import {useState,type FormEvent} from 'react'
import {supabase} from '../lib/supabase'
export default function PendingDriverAccess({userId,onSaved}:{userId:string;onSaved:()=>void}){
 const[email,setEmail]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('')
 async function save(e:FormEvent){e.preventDefault();setBusy(true);setError('');try{const r=await supabase.functions.invoke('admin-user-security',{body:{action:'set_driver_email',user_id:userId,email}});if(r.error||r.data?.error)throw Error(r.data?.error||r.error?.message||'Unable to save email');onSaved()}catch(e){setError(e instanceof Error?e.message:'Unable to save email')}finally{setBusy(false)}}
 return <form className="profile-panel" onSubmit={save}><h3>Driver access · pending activation</h3><p>This driver can be selected for dispatches. Register their personal email, then use Resend app invitation to provide access to the driver app.</p><label>Personal sign-in email<input type="email" required maxLength={254} value={email} disabled={busy} onChange={e=>setEmail(e.target.value)}/></label>{error&&<p className="error-box" role="alert">{error}</p>}<button className="primary-button" disabled={busy}>{busy?'Saving…':'Register driver email'}</button><small>No invitation is sent by this step. Existing dispatch assignments are retained.</small></form>
}
