import {useEffect,useRef,useState,type FormEvent} from 'react'
import {supabase} from '../lib/supabase'
import {mergeObservationMessages,prepareObservationMessage,readObservationMessageDraft,saveObservationMessageDraft,type ObservationMessage} from '../lib/observationConversation'
import type {ObservationConversationContext} from '../lib/observationConversation'
import ObservationMessageList from './ObservationMessageList'
import {appendTaskDictation} from '../lib/taskDictation'
import {useChatDictation} from '../lib/useChatDictation'
import ChatVoiceButton from './ChatVoiceButton'
import './task-conversation.css'
type Props={observationId:string;userId:string;active?:boolean;onActivity:()=>void}
function cache(){try{return window.sessionStorage}catch{return null}}
export default function ObservationConversation({observationId,userId,active=true,onActivity}:Props){
 const initial=useRef(readObservationMessageDraft(cache(),userId,observationId))
 const[text,setText]=useState(initial.current.text),[messages,setMessages]=useState<ObservationMessage[]>([]),[loading,setLoading]=useState(true),[sending,setSending]=useState(false),[olderBusy,setOlderBusy]=useState(false),[hasOlder,setHasOlder]=useState(false),[error,setError]=useState(''),[sendError,setSendError]=useState(''),[confirmation,setConfirmation]=useState('')
 const request=useRef<{body:string;id:string}|null>(initial.current.requestId?{body:initial.current.text.trim(),id:initial.current.requestId}:null)
 const box=useRef<HTMLDivElement>(null),latest=useRef(0),oldest=useRef(0),epoch=useRef(0),fetching=useRef(false),sendingNow=useRef(false),enabled=useRef(active),initialized=useRef(false)
 const[context,setContext]=useState<ObservationConversationContext|null>(null);const canSend=!!context?.can_send;const peer=context?.reported_by===userId?(context.reviewer_name||'your assigned reviewer'):(context?.reporter_name||'the reporter')
 const voice=useChatDictation(`${userId}:observation:${observationId}`,active,sending||!canSend,words=>{setText(v=>appendTaskDictation(v,words));setConfirmation('')})
 enabled.current=active
 useEffect(()=>{saveObservationMessageDraft(cache(),userId,observationId,{text,requestId:request.current?.body===text.trim()?request.current.id:null})},[text,userId,observationId])
 function bottom(){window.requestAnimationFrame(()=>{if(box.current)box.current.scrollTop=box.current.scrollHeight})}
 async function refresh(){
  if(!enabled.current||document.visibilityState!=='visible'||fetching.current)return
  fetching.current=true;const token=epoch.current;const atBottom=!box.current||box.current.scrollHeight-box.current.scrollTop-box.current.clientHeight<90;const first=!initialized.current
  try{
   let query=supabase.from('field_observation_messages').select('id,observation_id,author_id,author_name,author_role,body,created_at,client_message_id').eq('observation_id',observationId)
   query=first?query.order('id',{ascending:false}).limit(50):query.gt('id',latest.current).order('id').limit(200)
   const[result,details]=await Promise.all([query,supabase.rpc('observation_conversation_context',{p_observation_id:observationId})]);const{data,error:failure}=result;if(failure||details.error)throw failure||details.error
   if(token!==epoch.current)return
   setContext(details.data as ObservationConversationContext);const batch=(data||[]) as ObservationMessage[];if(first){batch.reverse();setHasOlder(batch.length===50);oldest.current=batch[0]?.id||0}
   if(batch.length){latest.current=Math.max(latest.current,...batch.map(m=>m.id));setMessages(v=>mergeObservationMessages(v,batch));if(first||atBottom)bottom()}
   initialized.current=true;setError('');setLoading(false)
   // Read state is specific to this observation; the workflow status is unchanged.
   if(latest.current&&enabled.current&&document.visibilityState==='visible'){
    const seen=await supabase.rpc('mark_observation_messages_seen',{p_observation_id:observationId,p_through_message_id:latest.current});if(seen.error)throw seen.error;if(first||batch.length)onActivity()
   }
  }catch(e){if(token===epoch.current){setError((e as {message?:string}).message||'Unable to refresh conversation. Check your connection.');setLoading(false)}}finally{if(token===epoch.current)fetching.current=false}
 }
 useEffect(()=>{
  if(!active)return
  void refresh();const timer=window.setInterval(()=>void refresh(),4000);const focus=()=>void refresh()
  window.addEventListener('focus',focus);document.addEventListener('visibilitychange',focus)
  return()=>{epoch.current++;fetching.current=false;window.clearInterval(timer);window.removeEventListener('focus',focus);document.removeEventListener('visibilitychange',focus)}
 },[observationId,userId,active])
 async function older(){
  if(olderBusy||!oldest.current)return;setOlderBusy(true);const token=epoch.current;const height=box.current?.scrollHeight||0;const top=box.current?.scrollTop||0
  try{const{data,error:failure}=await supabase.from('field_observation_messages').select('id,observation_id,author_id,author_name,author_role,body,created_at,client_message_id').eq('observation_id',observationId).lt('id',oldest.current).order('id',{ascending:false}).limit(50);if(failure)throw failure;if(token!==epoch.current)return;const batch=(data||[]) as ObservationMessage[];batch.reverse();if(batch.length){oldest.current=batch[0].id;setMessages(v=>mergeObservationMessages(v,batch))}setHasOlder(batch.length===50);setError('');window.requestAnimationFrame(()=>{if(box.current)box.current.scrollTop=top+box.current.scrollHeight-height})}catch(e){if(token===epoch.current)setError((e as {message?:string}).message||'Unable to load earlier messages')}finally{setOlderBusy(false)}
 }
 async function send(e:FormEvent){
  e.preventDefault();if(sendingNow.current||!canSend||!enabled.current||voice.isActive())return
  let pending:{body:string;id:string};try{pending=prepareObservationMessage(text,request.current,()=>crypto.randomUUID())}catch(e){setSendError((e as Error).message);return}
  request.current=pending;sendingNow.current=true;setSending(true);setSendError('');setConfirmation('')
  saveObservationMessageDraft(cache(),userId,observationId,{text,requestId:pending.id})
  try{const{error:failure}=await supabase.rpc('send_field_observation_message',{p_observation_id:observationId,p_body:pending.body,p_client_message_id:pending.id});if(failure)throw failure
   request.current=null;setText('');saveObservationMessageDraft(cache(),userId,observationId,{text:'',requestId:null});setConfirmation('Message saved to this observation.');bottom();await refresh();onActivity()
  }catch(e){setSendError(((e as {message?:string}).message||'Connection error')+'. Delivery was not confirmed. Your text is kept; retry to send this message once.')}
  finally{sendingNow.current=false;setSending(false)}
 }
 return <section className="task-chat" aria-label="Observation conversation"><div className="task-chat-heading"><div><span className="eyebrow">Instructions · Questions · Replies</span><h3>Observation conversation</h3></div><span className="task-chat-evidence">Saved with this observation</span></div>{context&&<p className="task-chat-participants">{canSend?<strong>{peer}</strong>:<><strong>{context.reporter_name||'Reporter'}</strong> ↔ <strong>{context.reviewer_name||'Reviewer not assigned'}</strong></>}</p>}<p className="field-help">Ask questions and reply about this observation. Messages retain their author and time, including after closure, and refresh automatically while this screen is open.</p>
  {error&&<div className="warning-box" role="status">{error} <button type="button" className="secondary-outline" onClick={()=>void refresh()}>Refresh messages</button></div>}
  <div ref={box} className="task-chat-scroll" tabIndex={0} aria-label="Conversation history">{hasOlder&&<button type="button" className="task-chat-older" disabled={olderBusy} onClick={()=>void older()}>{olderBusy?'Loading…':'Load earlier messages'}</button>}{loading?<p className="task-chat-empty">Loading conversation…</p>:messages.length?<ObservationMessageList messages={messages} userId={userId} />:<p className="task-chat-empty">No messages yet. Ask a question or add instructions for this observation.</p>}</div>
  {canSend?<form className="task-chat-composer" onSubmit={send}><label htmlFor={`task-chat-${observationId}`}>Message to {peer}</label><textarea id={`task-chat-${observationId}`} rows={3} maxLength={10000} disabled={sending} value={text} onChange={e=>{setText(e.target.value);setConfirmation('')}} placeholder="Ask for details, give instructions or reply…"/><div className="task-chat-send-row"><small>{text.length.toLocaleString()} / 10,000</small><ChatVoiceButton recording={voice.recording} disabled={sending||!active} onClick={voice.toggle}/><button type="submit" className="todo-primary" disabled={sending||voice.recording||!text.trim()||!active}>{sending?'Sending…':sendError?'Retry message':'Send message'}</button></div>{(voice.recording||voice.feedback)&&<p className="chat-voice-feedback" role="status">{voice.recording?'Listening… Tap the microphone to stop, then review and send your message.':voice.feedback}</p>}{sendError&&<p className="task-chat-error" role="alert">{sendError}</p>}{confirmation&&<p className="task-chat-confirmation" role="status">{confirmation}</p>}<small className="field-help">Sent messages remain as evidence. Sending a message does not change the observation status, approve work or accept it for AI memory.</small></form>:<p className="field-help">Only the reporter and assigned reviewer can reply. Other authorized users can read the evidence.</p>}
 </section>
}
