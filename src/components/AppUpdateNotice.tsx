import{useEffect,useRef,useState}from'react'
import{automaticUpdateAllowed,isCurrentAppVersion,parseAppVersion,recentlyReloaded,updateSafety,type AppAssets,type AppVersion}from'../lib/appUpdate'
import{trackUpdateEdits}from'../lib/updateEdits'
import './app-update.css'
const reloadKey='ruel:last-version-reload'
function savedReload(){try{return sessionStorage.getItem(reloadKey)}catch{return null}}
export default function AppUpdateNotice(){
 const[version,setVersion]=useState<AppVersion|null>(null),[blocked,setBlocked]=useState(false),[countdown,setCountdown]=useState<number|null>(null),[error,setError]=useState(''),[updating,setUpdating]=useState(false)
 const reload=useRef<()=>void>(()=>{})
 useEffect(()=>{
  if(!import.meta.env.PROD)return
  const entry=document.querySelector<HTMLScriptElement>('script[type="module"][src]')
  if(!entry)return
  const loadedBuild=document.querySelector<HTMLMetaElement>('meta[name="ruel-build"]')?.content
  const loaded:AppAssets={entry:new URL(entry.src).pathname,styles:Array.from(document.querySelectorAll<HTMLLinkElement>('link[rel="stylesheet"][href]')).map(link=>new URL(link.href).pathname).filter(path=>path.startsWith('/assets/'))}
  const edits=trackUpdateEdits(document)
  let disposed=false,candidate:AppVersion|null=null,lastInteraction=Date.now(),interactionSerial=0,deadline:number|null=null,checking=false,lastCheck=0,reloading=false,autoFailed=false
  const controllers=new Set<AbortController>()
  const isBlocked=()=>updateSafety.blocked()||edits.blocked()
  const fetchVersion=async()=>{
   const controller=new AbortController();controllers.add(controller);const timer=window.setTimeout(()=>controller.abort(),10000)
   try{const response=await fetch('/app-version.json',{cache:'no-store',signal:controller.signal});if(!response.ok||!response.headers.get('content-type')?.includes('application/json'))return null;return parseAppVersion(await response.json())}catch{return null}finally{clearTimeout(timer);controllers.delete(controller)}
  }
  const check=async()=>{
   if(disposed||checking||!navigator.onLine||document.visibilityState==='hidden'||Date.now()-lastCheck<1500)return
   checking=true;lastCheck=Date.now()
   try{const next=await fetchVersion();if(disposed||!next)return
    if(isCurrentAppVersion(loaded,next,loadedBuild)){candidate=null;setVersion(null);deadline=null;return}
    if(next.version!==candidate?.version){candidate=next;deadline=null;setVersion(next);setError('')}
   }finally{checking=false}
  }
  async function apply(){
   if(disposed||reloading||!candidate)return
   if(isBlocked()){setError('Save your work or close the form before updating.');return}
   if(!navigator.onLine){setError('Connect to the internet to update.');return}
   const startedAtInteraction=interactionSerial
   reloading=true;setUpdating(true);setError('')
   // Recheck deployment and safety immediately before navigating. Never reload
   // an expired deployment prompt or interrupt work that started during a read.
   const latest=await fetchVersion()
   if(disposed)return
   if(interactionSerial!==startedAtInteraction||document.visibilityState!=='visible'){reloading=false;setUpdating(false);deadline=null;return}
   if(!latest||isBlocked()||!navigator.onLine){reloading=false;autoFailed=true;setUpdating(false);deadline=null;setError(isBlocked()?'Save your work or close the form before updating.':'The update could not be checked. Please try again.');return}
   if(isCurrentAppVersion(loaded,latest,loadedBuild)){candidate=null;setVersion(null);setUpdating(false);reloading=false;return}
   try{sessionStorage.setItem(reloadKey,JSON.stringify({version:latest.version,at:Date.now()}))}catch{/* No storage clearing; the version query also bypasses a stale HTML cache. */}
   const url=new URL(window.location.href);url.searchParams.set('_app_version',latest.version)
   window.location.replace(url.href)
  }
  reload.current=()=>void apply()
  const interaction=()=>{interactionSerial++;lastInteraction=Date.now();deadline=null;setCountdown(null)}
  const tick=()=>{
   if(!candidate||disposed)return
   const busy=isBlocked();setBlocked(busy)
   const allowed=!autoFailed&&automaticUpdateAllowed({online:navigator.onLine,visible:document.visibilityState==='visible',blocked:busy,focused:!!document.activeElement?.matches('input,textarea,select,[contenteditable="true"]'),idleMs:Date.now()-lastInteraction,recentReload:recentlyReloaded(savedReload(),candidate.version,Date.now())})
   if(!allowed){deadline=null;setCountdown(null);return}
   if(deadline===null)deadline=Date.now()+5000
   const remaining=Math.max(0,Math.ceil((deadline-Date.now())/1000));setCountdown(remaining)
   if(!remaining)void apply()
  }
  const resume=()=>{interaction();void check()}
  const visible=()=>{if(document.visibilityState==='visible')resume();else{deadline=null;setCountdown(null)}}
  const shown=(event:PageTransitionEvent)=>{if(event.persisted)resume()}
  const requested=()=>{lastCheck=0;void check()}
  const poll=window.setInterval(()=>void check(),60000),safety=window.setInterval(tick,500),start=window.setTimeout(()=>void check(),1500)
  document.addEventListener('visibilitychange',visible);document.addEventListener('pointerdown',interaction,true);document.addEventListener('keydown',interaction,true);document.addEventListener('input',interaction,true)
  window.addEventListener('focus',resume);window.addEventListener('online',resume);window.addEventListener('pageshow',shown)
  window.addEventListener('ruel:check-app-update',requested)
  return()=>{disposed=true;reload.current=()=>{};edits.stop();controllers.forEach(c=>c.abort());clearInterval(poll);clearInterval(safety);clearTimeout(start);document.removeEventListener('visibilitychange',visible);document.removeEventListener('pointerdown',interaction,true);document.removeEventListener('keydown',interaction,true);document.removeEventListener('input',interaction,true);window.removeEventListener('focus',resume);window.removeEventListener('online',resume);window.removeEventListener('pageshow',shown);window.removeEventListener('ruel:check-app-update',requested)}
 },[])
 if(!version)return null
 return <aside className="app-update-notice" aria-label="Application update"><div role="status" aria-live="polite"><span className="app-update-kicker">RUEL MAINTENANCE 360</span><strong>New version available</strong><p>{updating?'Checking the update…':blocked?'Save your work or close the form, then tap Update now.':countdown!==null?`Your workspace is idle. Updating in ${countdown}s…`:'The latest improvements are ready. Update when you are ready.'}</p>{error&&<p className="app-update-error">{error}</p>}</div><button type="button" disabled={blocked||updating} onClick={()=>reload.current()}>{updating?'Updating…':'Update now'} <span aria-hidden="true">↻</span></button></aside>
}
