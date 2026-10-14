import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Profile={id:string;email:string|null;phone:string|null;full_name:string|null;role:string;active:boolean}
type Access={id:string;user_id:string;business_unit_id:string;access_role:string;can_edit:boolean;can_approve:boolean}
type Props={units:BusinessUnit[];role:string}

const roles=['super_admin','it_admin','corporate_manager','unit_supervisor','technician','operator','viewer']

export default function AdminSection({units,role}:Props){
  const [profiles,setProfiles]=useState<Profile[]>([])
  const [access,setAccess]=useState<Access[]>([])
  const [loading,setLoading]=useState(true)
  const [message,setMessage]=useState('')
  const [selected,setSelected]=useState<string>('')
  const [unitId,setUnitId]=useState('')
  const [accessRole,setAccessRole]=useState('viewer')
  const [canEdit,setCanEdit]=useState(false)
  const [canApprove,setCanApprove]=useState(false)
  const canAdmin=['super_admin','it_admin'].includes(role)

  async function load(){
    setLoading(true)
    const [{data:p},{data:a}]=await Promise.all([
      supabase.from('profiles').select('id,email,phone,full_name,role,active').order('email'),
      supabase.from('user_unit_access').select('id,user_id,business_unit_id,access_role,can_edit,can_approve')
    ])
    setProfiles((p||[]) as Profile[]);setAccess((a||[]) as Access[]);setLoading(false)
  }
  useEffect(()=>{load()},[])

  const selectedProfile=profiles.find(p=>p.id===selected)||null
  const selectedAccess=useMemo(()=>access.filter(a=>a.user_id===selected),[access,selected])
  function unitName(id:string){return units.find(u=>u.id===id)?.name||id}

  async function updateRole(userId:string,newRole:string){
    if(!canAdmin)return
    setMessage('')
    const {error}=await supabase.from('profiles').update({role:newRole}).eq('id',userId)
    if(error)setMessage(error.message);else{setMessage('User role updated.');await load()}
  }

  async function toggleActive(userId:string,active:boolean){
    if(!canAdmin)return
    const {error}=await supabase.from('profiles').update({active:!active}).eq('id',userId)
    if(error)setMessage(error.message);else{setMessage(!active?'User activated.':'User deactivated.');await load()}
  }

  async function addAccess(){
    if(!canAdmin||!selected||!unitId)return
    setMessage('')
    const {error}=await supabase.from('user_unit_access').upsert({user_id:selected,business_unit_id:unitId,access_role:accessRole,can_edit:canEdit,can_approve:canApprove},{onConflict:'user_id,business_unit_id'})
    if(error)setMessage(error.message);else{setMessage('Unit access saved.');await load()}
  }

  async function removeAccess(id:string){
    if(!canAdmin)return
    const {error}=await supabase.from('user_unit_access').delete().eq('id',id)
    if(error)setMessage(error.message);else{setMessage('Unit access removed.');await load()}
  }

  return <div>
    <div className="hero-row compact-hero"><div><span className="eyebrow">Security & Access Control</span><h1>Administration</h1><p className="muted">Manage application roles, account status and business-unit access. Authentication credentials remain managed through Supabase Auth.</p></div></div>
    {!canAdmin&&<div className="warning-box"><strong>Read-only access</strong><p>Your current application role does not permit user administration.</p></div>}
    {message&&<div className={message.includes('updated')||message.includes('saved')||message.includes('activated')||message.includes('removed')?'success-box':'error-box'}>{message}</div>}
    {loading?<div className="loading-panel">Loading users…</div>:<div className="admin-layout">
      <div className="table-wrap"><table className="data-table"><thead><tr><th>User</th><th>Role</th><th>Status</th><th></th></tr></thead><tbody>{profiles.map(p=><tr key={p.id} className={selected===p.id?'selected-row':''}><td><strong>{p.full_name||'Unnamed user'}</strong><small>{p.email||p.phone||p.id}</small></td><td>{canAdmin?<select value={p.role} onChange={e=>updateRole(p.id,e.target.value)}>{roles.map(r=><option key={r} value={r}>{r.replaceAll('_',' ')}</option>)}</select>:p.role.replaceAll('_',' ')}</td><td><span className={`status-pill ${p.active?'active':'out_of_service'}`}>{p.active?'active':'inactive'}</span></td><td><div className="row-actions"><button className="secondary-outline mini" onClick={()=>setSelected(p.id)}>Access</button>{canAdmin&&<button className="secondary-outline mini" onClick={()=>toggleActive(p.id,p.active)}>{p.active?'Deactivate':'Activate'}</button>}</div></td></tr>)}</tbody></table></div>
      <aside className="admin-panel">
        <span className="eyebrow">Unit access</span><h2>{selectedProfile?.full_name||selectedProfile?.email||'Select a user'}</h2>
        {!selectedProfile?<p className="muted">Choose a user from the table to review or assign business-unit permissions.</p>:<>
          <div className="access-list">{selectedAccess.length===0?<div className="empty-table compact">No explicit unit assignments. Corporate roles may still have global access.</div>:selectedAccess.map(a=><div className="access-card" key={a.id}><div><strong>{unitName(a.business_unit_id)}</strong><small>{a.access_role.replaceAll('_',' ')} · Edit {a.can_edit?'Yes':'No'} · Approve {a.can_approve?'Yes':'No'}</small></div>{canAdmin&&<button className="icon-button small" onClick={()=>removeAccess(a.id)}>×</button>}</div>)}</div>
          {canAdmin&&<div className="access-form"><label>Business unit<select value={unitId} onChange={e=>setUnitId(e.target.value)}><option value="">Select unit</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label><label>Unit role<select value={accessRole} onChange={e=>setAccessRole(e.target.value)}>{roles.filter(r=>r!=='super_admin'&&r!=='it_admin'&&r!=='corporate_manager').map(r=><option key={r} value={r}>{r.replaceAll('_',' ')}</option>)}</select></label><label className="check-row"><input type="checkbox" checked={canEdit} onChange={e=>setCanEdit(e.target.checked)}/><span>Can edit operational records</span></label><label className="check-row"><input type="checkbox" checked={canApprove} onChange={e=>setCanApprove(e.target.checked)}/><span>Can approve within unit</span></label><button className="primary-button action-button" type="button" onClick={addAccess}>Save unit access</button></div>}
        </>}
      </aside>
    </div>}
    <div className="phase-banner">New login accounts should be created in Supabase Authentication, then configured here with the correct RUEL application role and unit scope. Never share a common password between personnel.</div>
  </div>
}
