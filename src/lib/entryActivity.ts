export type EntryActivity = {tasks:number; chats:number; alerts:number; taskId?:string; observationId?:string; partial:boolean}
type CountResult = {count:number|null; data?:{id?:string; observation_id?:string}[]|null; error:unknown}
export type ActivityReads = Record<'tasks'|'chats'|'alerts',()=>PromiseLike<CountResult>>

// Counts come from the existing per-user read cursors, not from all pending work.
// A task with several unread chat/progress events is one item needing attention.
export async function readEntryActivity(reads:ActivityReads):Promise<EntryActivity>{
 const keys=['tasks','chats','alerts'] as const
 const results=await Promise.allSettled(keys.map(key=>Promise.resolve().then(reads[key])))
 const summary:EntryActivity={tasks:0,chats:0,alerts:0,partial:false}
 results.forEach((result,index)=>{
  const key=keys[index]
  if(result.status==='rejected'||result.value.error||result.value.count===null){summary.partial=true;return}
  summary[key]=result.value.count
  if(result.value.count===1){
   if(key==='tasks')summary.taskId=result.value.data?.[0]?.id
   if(key==='chats')summary.observationId=result.value.data?.[0]?.observation_id
  }
 })
 return summary
}
export function hasEntryActivity(summary:EntryActivity){return summary.tasks+summary.chats+summary.alerts>0}
export function entryActivityText(summary:EntryActivity){
 return [summary.tasks?`${summary.tasks} ${summary.tasks===1?'task has':'tasks have'} new activity`:null,
  summary.chats?`${summary.chats} unread observation ${summary.chats===1?'message':'messages'}`:null,
  summary.alerts?`${summary.alerts} other ${summary.alerts===1?'alert':'alerts'}`:null].filter(Boolean).join(' · ')
}

// A single app activation often emits pageshow, visibilitychange and focus together.
export function entryActivationGate(cooldown=1500){
 let last=-Infinity
 return(now:number)=>{if(now-last<cooldown)return false;last=now;return true}
}
