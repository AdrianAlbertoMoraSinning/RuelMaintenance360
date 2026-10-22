import {useEffect,useRef,useState} from 'react'
import {supabase} from '../lib/supabase'
import {locationLoads,locationSample} from '../lib/deliveryGeofence'
import type {ProductionLoad} from '../lib/production'
import {useUpdateBlocker} from '../lib/useUpdateBlocker'
export default function DeliveryGeofence({loads,userId,blocked,onChange,onWorking}:{loads:ProductionLoad[];userId:string;blocked:boolean;onChange:()=>void;onWorking:(working:boolean)=>void}){
 const[enabled,setEnabled]=useState(false),[visible,setVisible]=useState(()=>typeof document==='undefined'||document.visibilityState!=='hidden'),[notice,setNotice]=useState(''),[working,setWorking]=useState(false)
 const latest=useRef({loads,blocked,onChange});latest.current={loads,blocked,onChange};useUpdateBlocker(working)
 useEffect(()=>{setEnabled(false)},[userId])
 const ids=locationLoads(loads,userId).map(l=>l.id).join(',')
 useEffect(()=>{const fn=()=>setVisible(document.visibilityState!=='hidden');document.addEventListener('visibilitychange',fn);return()=>document.removeEventListener('visibilitychange',fn)},[])
 useEffect(()=>{
  if(!enabled||!visible||!ids)return
  if(!navigator.geolocation){setNotice('Location is unavailable. Use the delivery buttons.');setEnabled(false);return}
  let live=true,inFlight=false,lastSent=0
  const hidden=()=>document.visibilityState==='hidden'
  const fail=(e:GeolocationPositionError)=>{if(!live)return;setNotice(e.code===1?'Location permission was denied. Use the delivery buttons or allow location in browser settings.':'GPS unavailable. Use the delivery buttons; location assistance will retry.');if(e.code===1)setEnabled(false)}
  const fix=async(p:GeolocationPosition)=>{
   if(!live||inFlight||latest.current.blocked||document.visibilityState==='hidden')return
   if(!navigator.onLine){setNotice('Offline — use the delivery buttons. Automatic detection resumes online.');return}
   const sample=locationSample(p);if(!sample){setNotice('Waiting for a fresh GPS reading within 50 m accuracy.');return}
   if(Date.now()-lastSent<10000)return
   lastSent=Date.now();inFlight=true;setWorking(true);onWorking(true)
   try{
    for(const l of locationLoads(latest.current.loads,userId)){
     if(!live||hidden())break
     const r=await supabase.rpc('production_geofence',{p_action:'sample',p_data:{...sample,actor_id:userId,load_id:l.id}})
     if(r.error)throw Error(r.error.message)
     if(!live)break
     setNotice(r.data.notice)
     if(r.data.event){latest.current.onChange();break}
    }
   }catch(e){if(live)setNotice(`Location update not confirmed. Use the delivery buttons. ${e instanceof Error?e.message:''}`)}finally{inFlight=false;if(live){setWorking(false);onWorking(false)}}
  }
  const options={enableHighAccuracy:true,maximumAge:0,timeout:20000}
  const watch=navigator.geolocation.watchPosition(p=>void fix(p),fail,options)
  const timer=setInterval(()=>{if(live&&!inFlight)navigator.geolocation.getCurrentPosition(p=>void fix(p),fail,options)},15000)
  return()=>{live=false;navigator.geolocation.clearWatch(watch);clearInterval(timer);setWorking(false);onWorking(false)}
 },[enabled,visible,userId,ids,onWorking])
 if(!ids)return null
 return <section className="delivery-location" aria-label="Location assistance"><strong>◉ Location assistance</strong><p>Automatically records plant departure, site arrival and site departure while this screen is open. Delivery completion stays manual.</p><button className="secondary-outline" aria-pressed={enabled} onClick={()=>{setNotice('');setEnabled(v=>!v)}}>{enabled?'Stop location assistance':'Enable location assistance'}</button><p role="status">{!enabled?'Optional · Manual delivery buttons remain available.':!visible?'Paused while this screen is hidden.':notice||'Waiting for location permission and accurate GPS…'}</p><small>Allow location on this phone. Locking the phone or leaving this screen can pause detection. No continuous route is stored; confirmed events retain their location.</small></section>
}
