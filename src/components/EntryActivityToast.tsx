import {useEffect,useState} from 'react'
import {supabase} from '../lib/supabase'
import {entryActivationGate,entryActivityText,hasEntryActivity,readEntryActivity,type EntryActivity} from '../lib/entryActivity'
import './entry-activity.css'

type Props={userId:string;onNavigate:(section:string,id?:string)=>void;onAlerts:()=>void}
export default function EntryActivityToast({userId,onNavigate,onAlerts}:Props){
 const[summary,setSummary]=useState<EntryActivity|null>(null)
 const[paused,setPaused]=useState(false)
 useEffect(()=>{
  let disposed=false,version=0
  const allow=entryActivationGate()
  const visibleNow=()=>document.visibilityState!=='hidden'
  const check=async()=>{
   if(!visibleNow()||!allow(performance.now()))return
   const request=++version
   setSummary(null);setPaused(false)
   const next=await readEntryActivity({
    tasks:()=>supabase.from('operation_task_inbox').select('id',{count:'exact'}).eq('has_updates',true).or(`assigned_by.eq.${userId},assigned_to.eq.${userId}`).order('updated_at',{ascending:false}).limit(1),
    // Message notifications belong to the actual recipient; leadership observers
    // may read a chat but must not receive someone else's unread-message reminder.
    chats:()=>supabase.from('notifications').select('observation_id',{count:'exact'}).eq('user_id',userId).is('read_at',null).eq('notification_type','observation_message').order('created_at',{ascending:false}).limit(1),
    // Chats/progress use their cursors. Signature notices do not mutate those cursors.
    alerts:()=>supabase.from('notifications').select('id',{count:'exact'}).eq('user_id',userId).is('read_at',null).or('task_id.is.null,dedupe_key.like.signature:*').neq('notification_type','observation_message').limit(1)
   })
   if(!disposed&&request===version&&visibleNow()&&hasEntryActivity(next))setSummary(next)
  }
  const visible=()=>{if(document.visibilityState==='hidden'){++version;setSummary(null)}else void check()}
  const shown=(event:PageTransitionEvent)=>{if(event.persisted)void check()}
  void check()
  document.addEventListener('visibilitychange',visible)
  window.addEventListener('focus',check)
  window.addEventListener('pageshow',shown)
  window.addEventListener('online',check)
  return()=>{disposed=true;++version;document.removeEventListener('visibilitychange',visible);window.removeEventListener('focus',check);window.removeEventListener('pageshow',shown);window.removeEventListener('online',check)}
 },[userId])
 useEffect(()=>{if(!summary||paused)return;const timer=window.setTimeout(()=>setSummary(null),12000);return()=>window.clearTimeout(timer)},[summary,paused])
 if(!summary)return null
 function open(section:string,id?:string){setSummary(null);onNavigate(section,id)}
 return <aside className="entry-activity-toast" aria-label="Unread activity" onMouseEnter={()=>setPaused(true)} onMouseLeave={()=>setPaused(false)} onFocus={()=>setPaused(true)} onBlur={event=>{if(!event.currentTarget.contains(event.relatedTarget as Node|null))setPaused(false)}}>
  <div className="entry-activity-symbol" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"/><path d="M10 21h4"/></svg><i/></div>
  <div className="entry-activity-copy"><div role="status" aria-live="polite" aria-atomic="true"><strong>You have new activity</strong><p>{entryActivityText(summary)}</p>{summary.partial&&<small>Some updates could not be checked. Open Alerts to review.</small>}</div>
   <div className="entry-activity-actions">
    {summary.tasks>0&&<button type="button" onClick={()=>open('todo',summary.taskId)}>My To-do <span>→</span></button>}
    {summary.chats>0&&<button type="button" onClick={()=>open('observations',summary.observationId)}>Observation chat <span>→</span></button>}
    {summary.alerts>0&&<button type="button" onClick={()=>{setSummary(null);onAlerts()}}>Alerts <span>→</span></button>}
   </div>
  </div>
  <button type="button" className="entry-activity-close" aria-label="Dismiss activity reminder" onClick={()=>setSummary(null)}>×</button>
 </aside>
}
