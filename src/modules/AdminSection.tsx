import { ChangeEvent, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'
import PersonAvatar from '../components/PersonAvatar'

type Profile={id:string;email:string|null;phone:string|null;full_name:string|null;role:string;active:boolean;position_title:string|null;personnel_category:string;avatar_url:string|null}
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
  const [passwordTarget,setPasswordTarget]=useState<Profile|null>(null)
  const [newPassword,setNewPassword]=useState('')
  const [confirmPassword,setConfirmPassword]=useState('')
  const [busy,setBusy]=useState(false)
  const canAdmin=['super_admin','it_admin'].includes(role)

  async function load(){
    setLoading(true)
    const [{data:p},{data:a}]=await Promise.all([
      supabase.from('profiles').select('id,email,phone,full_name,role,active,position_title,personnel_category,avatar_url').order('full_name'),
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
    c.it_users=profiles.filter(p=>p.role==='it_admin').length
    return c
  },[profiles])

  function unitName(id:string){return units.find(u=>u.id===id)?.name||id}

  async function adminAction(body:Record<string,unknown>){
    const {data,error}=await supabase.functions.invoke('admin-user-security',{body})
    if(error)throw error
    if(data?.error)throw new Error(data.error)
    return data
  }

  async function updateProfile(userId:string,patch:Partial<Profile>,success='User updated.'){
    if(!canAdmin)return
    setMessage('')
    try{await adminAction({action:'update_profile',user_id:userId,...patch});setMessage(success);await load()}
    catch(e){setMessage(e instanceof Error?e.message:'Unable to update user.')}
  }

  async function updateRole(userId:string,newRole:string){await updateProfile(userId,{role:newRole},'User role updated.')}

  async function toggleActive(userId:string,active:boolean){
    if(!canAdmin)return
    setMessage('');setBusy(true)
    try{await adminAction({action:'set_active',user_id:userId,active:!active});setMessage(!active?'User activated.':'User deactivated and sign-in blocked.');await load()}
    catch(e){setMessage(e instanceof Error?e.message:'Unable to change account status.')}
    setBusy(false)
  }

  async function changePassword(){
    if(!canAdmin||!passwordTarget)return
    if(newPassword.length<10){setMessage('Password must be at least 10 characters.');return}
    if(newPassword!==confirmPassword){setMessage('Password confirmation does not match.');return}
    setBusy(true);setMessage('')
    try{await adminAction({action:'set_password',user_id:passwordTarget.id,password:newPassword});setMessage(`Password changed for ${passwordTarget.full_name||passwordTarget.email}.`);setPasswordTarget(null);setNewPassword('');setConfirmPassword('')}
    catch(e){setMessage(e instanceof Error?e.message:'Unable to change password.')}
    setBusy(false)
  }

  async function normalizeAvatar(file:File):Promise<Blob>{
    const bitmap=await createImageBitmap(file,{imageOrientation:'from-image'})
    const size=Math.min(bitmap.width,bitmap.height)
    const sx=bitmap.width>bitmap.height?(bitmap.width-size)/2:0
    const sy=bitmap.height>bitmap.width?(bitmap.height-size)*0.28:0
    const canvas=document.createElement('canvas')
    canvas.width=640;canvas.height=640
    const ctx=canvas.getContext('2d')
    if(!ctx){bitmap.close();throw new Error('Unable to process photo.')}
    ctx.imageSmoothingEnabled=true
    ctx.imageSmoothingQuality='high'
    ctx.drawImage(bitmap,sx,sy,size,size,0,0,640,640)
    bitmap.close()
    const blob=await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/jpeg',0.9))
    if(!blob)throw new Error('Unable to prepare photo.')
    return blob
  }

  async function uploadAvatar(e:ChangeEvent<HTMLInputElement>,profile:Profile){
    const file=e.target.files?.[0];if(!file||!canAdmin)return
    if(file.size>10*1024*1024){setMessage('Original photo must be 10 MB or smaller.');return}
    if(!['image/jpeg','image/png','image/webp'].includes(file.type)){setMessage('Photo must be JPG, PNG or WEBP.');return}
    setBusy(true);setMessage('')
    try{
      const normalized=await normalizeAvatar(file)
      const path=`${profile.id}/avatar-${Date.now()}.jpg`
      const {error:uploadError}=await supabase.storage.from('ruel-avatars').upload(path,normalized,{upsert:false,contentType:'image/jpeg',cacheControl:'3600'})
      if(uploadError)throw uploadError
      await adminAction({action:'update_profile',user_id:profile.id,avatar_url:path})
      if(profile.avatar_url&&!/^https?:\/\//i.test(profile.avatar_url)) await supabase.storage.from('ruel-avatars').remove([profile.avatar_url])
      setMessage('Personnel photo automatically cropped, resized and updated.');await load()
    }catch(err){setMessage(err instanceof Error?err.message:'Unable to upload photo.')}
    setBusy(false);e.target.value=''
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
    <div className="hero-row compact-hero"><div><span className="eyebrow">Security, Personnel & Access Control</span><h1>Administration</h1><p className="muted">Corporate directory, photos, passwords, account status, application roles and business-unit permissions.</p></div></div>

    <div className="stat-grid personnel-stats">
      <article className="stat-card"><span>Super Users</span><strong>{counts.super_users||0}</strong><small>Full system administrators</small></article>
      <article className="stat-card"><span>IT Administrators</span><strong>{counts.it_users||0}</strong><small>Password and account administration</small></article>
      <article className="stat-card"><span>Managers</span><strong>{counts.manager||0}</strong><small>Corporate / unit management</small></article>
      <article className="stat-card"><span>Operators</span><strong>{counts.operator||0}</strong><small>Field / equipment operators</small></article>
    </div>

    {!canAdmin&&<div className="warning-box"><strong>Read-only access</strong><p>Your current application role does not permit user administration.</p></div>}
    {message&&<div className={/updated|saved|activated|deactivated|changed|photo|cropped/i.test(message)?'success-box':'error-box'}>{message}</div>}

    <div className="toolbar"><input className="search-input" placeholder="Search personnel, email, role…" value={search} onChange={e=>setSearch(e.target.value)}/><select value={categoryFilter} onChange={e=>setCategoryFilter(e.target.value)}><option value="all">All personnel categories</option>{personnelCategories.map(c=><option key={c} value={c}>{c.replaceAll('_',' ')}</option>)}</select><span className="count-chip">{filtered.length} users</span></div>

    {loading?<div className="loading-panel">Loading users…</div>:<div className="admin-layout">
      <div className="table-wrap"><table className="data-table"><thead><tr><th>Person</th><th>Position</th><th>Category</th><th>System Role</th><th>Status</th><th></th></tr></thead><tbody>{filtered.map(p=><tr key={p.id} className={selected===p.id?'selected-row':''}>
        <td><div className="person-cell"><PersonAvatar avatarPath={p.avatar_url} name={p.full_name||p.email} size="sm"/><span><strong>{p.full_name||'Unnamed user'}</strong><small>{p.email||p.phone||p.id}</small></span></div></td>
        <td>{canAdmin?<input value={p.position_title||''} placeholder="e.g. CEO, Plant Manager" onChange={e=>setProfiles(prev=>prev.map(x=>x.id===p.id?{...x,position_title:e.target.value}:x))} onBlur={()=>updateProfile(p.id,{position_title:p.position_title||null},'Position updated.')}/>:p.position_title||'—'}</td>
        <td>{canAdmin?<select value={p.personnel_category} onChange={e=>updateProfile(p.id,{personnel_category:e.target.value},'Personnel category updated.')}>{personnelCategories.map(c=><option key={c} value={c}>{c.replaceAll('_',' ')}</option>)}</select>:p.personnel_category.replaceAll('_',' ')}</td>
        <td>{canAdmin?<select value={p.role} onChange={e=>updateRole(p.id,e.target.value)}>{roles.map(r=><option key={r} value={r}>{r.replaceAll('_',' ')}</option>)}</select>:p.role.replaceAll('_',' ')}</td>
        <td><span className={`status-pill ${p.active?'active':'out_of_service'}`}>{p.active?'active':'inactive'}</span></td>
        <td><div className="row-actions"><button className="secondary-outline mini" onClick={()=>setSelected(p.id)}>Manage</button>{canAdmin&&<button className="secondary-outline mini" onClick={()=>setPasswordTarget(p)}>Password</button>}{canAdmin&&<button className="secondary-outline mini" disabled={busy} onClick={()=>toggleActive(p.id,p.active)}>{p.active?'Deactivate':'Activate'}</button>}</div></td>
      </tr>)}</tbody></table></div>

      <aside className="admin-panel">
        <span className="eyebrow">Selected person</span>
        {!selectedProfile?<><h2>Select a user</h2><p className="muted">Choose a person to manage identity, photo and unit permissions.</p></>:<>
          <div className="admin-person-card"><PersonAvatar avatarPath={selectedProfile.avatar_url} name={selectedProfile.full_name||selectedProfile.email} size="lg"/><div><h2>{selectedProfile.full_name||selectedProfile.email}</h2><small>{selectedProfile.email||selectedProfile.phone}</small></div></div>
          {canAdmin&&<label className="photo-upload">Personnel photo<input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={e=>uploadAvatar(e,selectedProfile)}/><small className="field-help">Upload a normal portrait or landscape photo. The system automatically rotates, crops, centers and resizes it to a standardized 640×640 personnel image.</small></label>}
          <div className="detail-list"><span>Position <b>{selectedProfile.position_title||'Not assigned'}</b></span><span>Category <b>{selectedProfile.personnel_category.replaceAll('_',' ')}</b></span><span>System role <b>{selectedProfile.role.replaceAll('_',' ')}</b></span><span>Account <b>{selectedProfile.active?'Active':'Inactive / sign-in blocked'}</b></span></div>
          <div className="section-heading small-heading"><div><span className="eyebrow">Business unit access</span></div></div>
          <div className="access-list">{selectedAccess.length===0?<div className="empty-table compact">No explicit unit assignments. Corporate roles may still have global access.</div>:selectedAccess.map(a=><div className="access-card" key={a.id}><div><strong>{unitName(a.business_unit_id)}</strong><small>{a.access_role.replaceAll('_',' ')} · Edit {a.can_edit?'Yes':'No'} · Approve {a.can_approve?'Yes':'No'}</small></div>{canAdmin&&<button className="icon-button small" onClick={()=>removeAccess(a.id)}>×</button>}</div>)}</div>
          {canAdmin&&<div className="access-form"><label>Business unit<select value={unitId} onChange={e=>setUnitId(e.target.value)}><option value="">Select unit</option>{units.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label><label>Unit role<select value={accessRole} onChange={e=>setAccessRole(e.target.value)}>{roles.filter(r=>!['super_admin','it_admin','corporate_manager'].includes(r)).map(r=><option key={r} value={r}>{r.replaceAll('_',' ')}</option>)}</select></label><label className="check-row"><input type="checkbox" checked={canEdit} onChange={e=>setCanEdit(e.target.checked)}/><span>Can edit operational records</span></label><label className="check-row"><input type="checkbox" checked={canApprove} onChange={e=>setCanApprove(e.target.checked)}/><span>Can approve within unit</span></label><button className="primary-button action-button" type="button" onClick={addAccess}>Save unit access</button></div>}
        </>}
      </aside>
    </div>}

    {passwordTarget&&<div className="modal-backdrop" onClick={()=>setPasswordTarget(null)}><div className="modal-card" onClick={e=>e.stopPropagation()}><div className="form-title"><div><span className="eyebrow">Security administration</span><h2>Change password</h2><p className="muted">{passwordTarget.full_name||passwordTarget.email}</p></div><button className="icon-button" onClick={()=>setPasswordTarget(null)}>×</button></div><label>New password<input type="password" minLength={10} value={newPassword} onChange={e=>setNewPassword(e.target.value)} autoComplete="new-password"/></label><label>Confirm password<input type="password" minLength={10} value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} autoComplete="new-password"/></label><div className="warning-box"><strong>Security</strong><p>Use a unique password of at least 10 characters. The password is sent only to the protected administrator function and is not stored in the application database.</p></div><button className="primary-button action-button" disabled={busy||newPassword.length<10} onClick={changePassword}>{busy?'Updating…':'Change password'}</button></div></div>}

    <div className="phase-banner">Super Users and IT Administrators can securely change passwords and block/unblock sign-in. Personnel photos are standardized automatically and shown wherever asset accountability is displayed.</div>
  </div>
}
