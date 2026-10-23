import {useState} from 'react'
import {manualDeliveryActions} from '../lib/manualDelivery'
import type {ProductionLoad} from '../lib/production'
export default function DispatcherDeliveryControls({load,userId,disabled,onAction}:{load:ProductionLoad;userId:string;disabled:boolean;onAction:(name:string,data:Record<string,unknown>)=>Promise<unknown>}){
 const[requests]=useState<Record<string,string>>({})
 const actions=manualDeliveryActions(load)
 if(!actions.length)return null
 return <section className="manual-delivery-controls" aria-label="Manual delivery controls"><strong>Manual delivery controls</strong><p>Record confirmed information from the driver when their app is unavailable. Each step records your name and the current time, updates customer tracking and notifies the order creator.</p>{load.status==='arrived'&&!load.left_site_at&&<p>After the vehicle leaves, record Mark left site. Complete delivery becomes available next.</p>}<div className="production-tabs">{actions.map(a=><button type="button" key={a.event} className="primary-button" disabled={disabled} onClick={()=>{if(!window.confirm(a.confirm))return;const client_id=requests[a.event]||(requests[a.event]=crypto.randomUUID());void onAction(a.event==='departed'?'dispatch':'dispatch_event',{load_id:load.id,actor_id:userId,event:a.event,client_id}).catch(()=>{})}}>{a.label}</button>)}</div></section>
}
