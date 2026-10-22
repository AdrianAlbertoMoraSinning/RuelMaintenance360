export type AppAssets={entry:string;styles:string[]}
export type AppVersion=AppAssets&{schema:1;version:string}
export function parseAppVersion(value:unknown):AppVersion|null{
 if(!value||typeof value!=='object')return null
 const v=value as Partial<AppVersion>
 if(v.schema!==1||typeof v.version!=='string'||!/^[a-f0-9]{20}$/.test(v.version)||typeof v.entry!=='string'||!/^\/assets\/[\w.-]+\.js$/.test(v.entry)||!Array.isArray(v.styles)||!v.styles.every(s=>typeof s==='string'&&/^\/assets\/[\w.-]+\.css$/.test(s)))return null
 return{schema:1,version:v.version,entry:v.entry,styles:[...v.styles]}
}
export function sameAppAssets(a:AppAssets,b:AppAssets){return a.entry===b.entry&&JSON.stringify([...a.styles].sort())===JSON.stringify([...b.styles].sort())}
export function isCurrentAppVersion(loaded:AppAssets,next:AppVersion,loadedBuild?:string){return loadedBuild&&/^[a-f0-9]{20}$/.test(loadedBuild)?loadedBuild===next.version:sameAppAssets(loaded,next)}
export function createUpdateSafety(){
 const blockers=new Set<symbol>()
 return{hold(){const token=Symbol();blockers.add(token);return()=>{blockers.delete(token)}},blocked:()=>blockers.size>0}
}
export const updateSafety=createUpdateSafety()
export function guardUpdateRequests(fetcher:typeof fetch,safety=createUpdateSafety()):typeof fetch{return async(input,init)=>{
 const method=(init?.method||(typeof Request!=='undefined'&&input instanceof Request?input.method:'GET')).toUpperCase()
 const release=['GET','HEAD','OPTIONS'].includes(method)?()=>{}:safety.hold()
 try{return await fetcher(input,init)}finally{release()}
}}
export const updateAwareFetch=guardUpdateRequests(globalThis.fetch.bind(globalThis),updateSafety)
export function installUpdateFetchGuard(){globalThis.fetch=updateAwareFetch}
export function automaticUpdateAllowed({online,visible,blocked,focused,idleMs,recentReload}:{online:boolean;visible:boolean;blocked:boolean;focused:boolean;idleMs:number;recentReload:boolean}){
 return online&&visible&&!blocked&&!focused&&idleMs>=10000&&!recentReload
}
export function recentlyReloaded(record:string|null,version:string,now:number){
 try{const saved=JSON.parse(record||'null');return saved?.version===version&&Number.isFinite(saved?.at)&&now-saved.at>=0&&now-saved.at<300000}catch{return false}
}
