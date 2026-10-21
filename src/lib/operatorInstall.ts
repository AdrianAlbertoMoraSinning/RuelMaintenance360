export type InstallPrompt=Event & {prompt:()=>Promise<void>;userChoice:Promise<{outcome:'accepted'|'dismissed'}>}
let pending:InstallPrompt|null=null
const subscribers=new Set<()=>void>()
if(typeof window!=='undefined')window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();pending=e as InstallPrompt;subscribers.forEach(fn=>fn())})
export function currentInstallPrompt(){return pending}
export function clearInstallPrompt(){pending=null;subscribers.forEach(fn=>fn())}
export function subscribeInstallPrompt(fn:()=>void){subscribers.add(fn);return()=>{subscribers.delete(fn)}}
export function enableOperatorInstall(){
 const manifest=document.querySelector<HTMLLinkElement>('link[rel="manifest"]');if(manifest)manifest.href='/operator.webmanifest'
 document.title='RUEL Operators'
 document.querySelector('meta[name="apple-mobile-web-app-title"]')?.setAttribute('content','RUEL Operators')
}
