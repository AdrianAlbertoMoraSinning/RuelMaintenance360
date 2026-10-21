import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

type Props={avatarPath:string|null|undefined;name:string|null|undefined;size?:'sm'|'md'|'lg'}

export default function PersonAvatar({avatarPath,name,size='md'}:Props){
  const [url,setUrl]=useState<string>('')
  useEffect(()=>{
    let alive=true
    async function load(){
      setUrl('')
      if(!avatarPath){setUrl('');return}
      if(/^https?:\/\//i.test(avatarPath)){setUrl(avatarPath);return}
      const {data}=await supabase.storage.from('ruel-avatars').createSignedUrl(avatarPath,3600)
      if(alive)setUrl(data?.signedUrl||'')
    }
    load()
    return()=>{alive=false}
  },[avatarPath])
  const initial=(name||'U').trim().slice(0,1).toUpperCase()||'U'
  return <span className={`person-avatar person-avatar-${size} ${url?'has-photo':''} ${avatarPath?.includes('/avatar-framed-')?'person-avatar-framed':''}`} aria-label={name||'User'}>{url?<img src={url} alt={name||'User'}/>:<b>{initial}</b>}</span>
}
