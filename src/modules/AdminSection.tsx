import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'

type Profile={id:string;email:string|null;phone:string|null;full_name:string|null;role:string;active:boolean;position_title:string|null;personnel_category:string}
type Access={id:string;user_id:string;business_unit_id:string;access_role:string;can_edit:boolean;can_approve:boolean}
type Props={units:BusinessUnit[];role:string}

const roles=['super_admin','it_admin','corporate_manager','unit_supervisor','technician','operator','viewer']
const personnelCategories=['ceo','manager','supervisor','operator','technician','administration','other']

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
  const [search,setSearch]=useState('')
  const [categoryFilter,setCategoryFilter]=useState('all')
  const canAdmin=['super_admin','it_admin'].includes(role)

  async function load(){
    setLoading(true)
    const [{data:p},{data:a}]=await Promise.all([
      supabase.from('profiles').select('id,email,phone,full_name,role,active,position_title,personnel_category').order('full_name'),
      supabase.from('user_unit_access').select('id,user_id,business_unit_id,access_role,can_edit,can_approve')
    ])
    setProfiles((p||[]) as Profile[]);setAccess((a||[]) as Access[]);setLoading(false)
  }
  useEffect(()=>{load()},[])

  const selectedProfile=profiles.find(p=>p.id===selected)||null
  const selectedAccess=useMemo(()=>access.filter(a=>a.user_id===selected),[access,selected])
  const filtered=useMemo(()=>{
    const q=search.trim().toLowerCase()
    return profiles.filter(p=>{
      const matchesCategory=categoryFilter==='all'||p.personnel_category===categoryFilter
      const hay=`${p.full_name||''} ${p.email||''} ${p.phone||''} ${p.role} ${p.position_title||''} ${p.personnel_category}`.toLowerCase()
      return matchesCategory&&(!q||hay.includes(q))
    })
  },[profiles,search,categoryFilter])

  const counts=useMemo(()=>{
    const c:Record<string,number>={}
    for(const key of personnelCategories)c[key]=profiles.filter(p=>p.personnel_category===key).length
    c.super_users=profiles.filter(p=>p.role==='super_admin').length
    return c
  },[profiles])

  function unitName(id:string){return units.find(u=>u.id===id)?.name||id}

  async function updateProfile(userId:string,patch:Partial<Profile>,success='User updated.'){
    if(!canAdmin)return
    setMessage('')
    const {error}=await supabase.from('profiles').update(patch).eq('id',userId)
    if(error)setMessage(error.message);else{setMessage(success);await load()}
  }

  async function updateRole(userId:string,newRole:string){await updateProfile(userId,{role:newRole},'User role updated.')}
  async function toggleActive(userId:string,active:boolean){await updateProfile(userId,{active:!active},!active?'User activated.':'User deactivated.')}
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
    <div className="hero-row compact-hero"><div><span className="eyebrow">Security, Personnel & Access Control</span><h1>Administration</h1><p className="muted">Corporate directory, application roles, organizational positions and business-unit permissions.</p></div></div>

    <div className="stat-grid personnel-stats">
      <article className="stat-card"><span>Super Users</span><strong>{counts.super_users||0}</strong><small>Full system administrators</small></article>
      <article className="stat-card"><span>CEO</span><strong>{counts.ceo||0}</strong><small>Organizational position</small></article>
      <article className="stat-card"><span>Managers</span><strong>{counts.manager||0}</strong><small>Corporate / unit management</small></article>
      <article className="stat-card"><span>Operators</span><strong>{counts.operator||0}</strong><small>Field / equipment operators</small></article>
    </div>

    {!canAdmin&&<div className="warning-box"><strong>Read-only access</strong><p>Your current application role does not permit user administration.</p></div>}
    {message&&<div className={message.toLowerCase().includes('updated')||message.toLowerCase().includes('saved')||message.toLowerCase().includes('activated')||message.toLowerCase().includes('removed')?'success-box':'error-box'}>{message}</div>}

    <div className="toolbar"><input className="search-input" placeholder="Search personnel, email, role…" value={search} onChange={e=>setSearch(e.target.value)}/><select value={categoryFilter} onChange={e=>setCategoryFilter(e.target.value)}><option value="all">All personnel categories</option>{personnelCategories.map(c=><option key={c} value={c}>{c.replaceAll('_',' ')}</option>)}</select><span className="count-chip">{filtered.length} users</span></div>

    {loading?<div className="loading-panel">Loading users…</div>:<div className="admin-layout">
      <div className="table-wrap"><table className="data-table"><thead><tr><th>Person</th><th>Position</th><th>Category</th><th>System Role</th><th>Status</th><th></th></tr></thead><tbody>{filtered.map(p=><tr key={p.id} className={selected===p.id?'selected-row':''}>
        <td><strong>{p.full_name||'Unnamed user'}</strong><small>{p.email||p.phone||p.id}</small></td>
        <td>{canAdmin?<input value={p.position_title||''} placeholder="e.g. CEO, Plant Manager" onChange={e=>setProfiles(prev=>prev.map(x=>x.id===p.id?{...x,position_title:e.target.value}:x))} onBlur={()=>updateProfile(p.id,{position_title:p.position_title||null},'Position updated.')}/>:p.position_title||'—'}</td>
        <td>{canAdmin?<select value={p.personnel_category} onChange={e=>updateProfile(p.id,{personnel_category:e.target.value},'Personnel category updated.')}>{personnelCategories.map(c=><option key={c} value={c}>{c.replaceAll('_',' ')}</option>)}</select>:p.personnel_category.replaceAll('_',' ')}</td>
        <td>{canAdmin?<select value={p.role} onChange={e=>updateRole(p.id,e.target.value)}>{roles.map(r=><option key={r} value={r}>{r.replaceAll('_',' ')}</option>)}</select>:p.role.replaceAll('_',' ')}</td>
        <td><span className={`status-pill ${p.active?'active':'out_of_service'}`}>{p.active?'active':'inactive'}</span></td>
        <td><div className="row-actions"><button className="secondary-outline mini" onClick={()=>setSelected(p.id)}>Access</button>{canAdmin&&<button className="secondary-outline mini" onClick={()=>toggleActive(p.id,p.active)}>{p.active?'Deactivate':'Activate'}</button>}</div></td>
      </tr>)}</tbody></table></div>

      <aside className="admin-panel">
        <span className="eyebrow">Selected person</span><h2>{selectedProfile?.full_name||selectedProfile?.email||'Select a user'}</h2>
        {!selectedProfile?<p className="muted">Choose a person to review organizational information and business-unit permissions.</p>:<>
          <div className="detail-list"><span>Position <b>{selectedProfile.position_title||'Not assigned'}</b></span><span>Category <b>{selectedProfile.personnel_category.replaceAll('_',' ')}</b></span><span>System role <b>{selectedProfile.role.replaceAll('_',' ')}</b></span></div>
          <div className="section-heading small-heading"><div><span className="eyebrow">Business unit access</span></div></div>
          <div className="access-list">{selectedAccess.length===0?<div className="empty-table compact">No explicit unit assignments. Corporate roles may still have global access.</div>:selectedAccess.map(a=><div className="access-card" key={a.id}><div><strong>{unitName(a.business_unit_id)}</strong><small>{a.access_role.replaceAll('_',' ')} · Edit {a.can_edit?'Yes':'No'} · Approve {a.can_approve?'Yes':'No'}</small></div>{canAdmin&&<button className="icon-button small" onClick={()=>removeAccess(a.id)}>×</button>}</div>)}</div>
          {canAdmin&&<div className="access-form"><label>Business unit<select value={unitId} onChange={e=>setUnitId(e.target.value)}><option value="">Select unit</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label><label>Unit role<select value={accessRole} onChange={e=>setAccessRole(e.target.value)}>{roles.filter(r=>!['super_admin','it_admin','corporate_manager'].includes(r)).map(r=><option key={r} value={r}>{r.replaceAll('_',' ')}</option>)}</select></label><label className="check-row"><input type="checkbox" checked={canEdit} onChange={e=>setCanEdit(e.target.checked)}/><span>Can edit operational records</span></label><label className="check-row"><input type="checkbox" checked={canApprove} onChange={e=>setCanApprove(e.target.checked)}/><span>Can approve within unit</span></label><button className="primary-button action-button" type="button" onClick={addAccess}>Save unit access</button></div>}
        </>}
      </aside>
    </div>}
    <div className="phase-banner">Organizational position and system access are intentionally separate. A CEO can be a super user, while an operator can have only the asset and unit access required for their work.</div>
  </div>
}
