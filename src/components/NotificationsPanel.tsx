import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

type Notification={production_order_id:string|null;id:string;task_id:string|null;notification_type:string;severity:string;title:string;message:string|null;read_at:string|null;created_at:string;work_order_id:string|null;inspection_id:string|null;maintenance_plan_id:string|null;observation_id:string|null;safety_case_id:string|null}
type Props={open:boolean;onClose:()=>void;onNavigate?:(section:string,taskId?:string)=>void}

export default function NotificationsPanel({open,onClose,onNavigate}:Props){
  const [rows,setRows]=useState<Notification[]>([])
  const [loading,setLoading]=useState(false)
  async function load(){setLoading(true);await supabase.rpc('refresh_pm_due_notifications');const {data}=await supabase.from('notifications').select('production_order_id,task_id,id,notification_type,severity,title,message,read_at,created_at,work_order_id,inspection_id,maintenance_plan_id,observation_id,safety_case_id').order('created_at',{ascending:false}).limit(100);setRows((data||[]) as Notification[]);setLoading(false)}
  useEffect(()=>{if(open)load()},[open])
  async function markRead(id:string){await supabase.from('notifications').update({read_at:new Date().toISOString()}).eq('id',id);setRows(prev=>prev.map(r=>r.id===id?{...r,read_at:new Date().toISOString()}:r))}
  async function openNotification(r:Notification){await markRead(r.id);if(r.production_order_id){onNavigate?.('production',r.production_order_id);onClose();return}if(r.task_id){onNavigate?.('todo',r.task_id);onClose();return}if(r.observation_id||r.safety_case_id){onNavigate?.('observations',r.observation_id||undefined);onClose();return}if(r.work_order_id){onNavigate?.('work_orders');onClose();return}if(r.inspection_id){onNavigate?.('inspections');onClose();return}if(r.maintenance_plan_id){onNavigate?.('maintenance');onClose()}}
  async function markAll(){const unread=rows.filter(r=>!r.read_at);await Promise.all(unread.map(r=>supabase.from('notifications').update({read_at:new Date().toISOString()}).eq('id',r.id)));await load()}
  if(!open)return null
  const unread=rows.filter(r=>!r.read_at).length
  return <div className="drawer-backdrop" onClick={onClose}><aside className="manual-drawer notification-drawer" onClick={e=>e.stopPropagation()}><div className="manual-head"><div><span className="eyebrow">Operational Escalations</span><h2>Notifications</h2></div><button className="icon-button" onClick={onClose}>×</button></div><div className="form-actions"><span className="count-chip">{unread} unread</span>{unread>0&&<button className="secondary-outline mini" onClick={markAll}>Mark all read</button>}</div>{loading?<div className="loading-panel">Refreshing alerts…</div>:rows.length===0?<div className="empty-table compact">No notifications.</div>:<div className="notification-list">{rows.map(r=><button key={r.id} className={`notification-card ${r.read_at?'read':'unread'} ${r.severity}`} onClick={()=>openNotification(r)}><span className={`priority-pill ${r.severity==='warning'?'high':r.severity}`}>{r.severity}</span><strong>{r.title}</strong><p>{r.message||''}</p><small>{new Date(r.created_at).toLocaleString()} · {r.notification_type.replaceAll('_',' ')}{r.observation_id||r.safety_case_id?' · Open observation':''}</small></button>)}</div>}</aside></div>
}
