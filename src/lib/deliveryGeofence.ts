import type {ProductionLoad} from './production'
export type DeliveryZone={latitude:number;longitude:number;radius_m:number}
export function locationLoads(loads:ProductionLoad[],userId:string,now=Date.now()){
 const own=loads.filter(l=>l.driver_id===userId)
 const primary=own.filter(l=>['ready','departed','arrived'].includes(l.status)).sort((a,b)=>{const rank=(l:ProductionLoad)=>l.status==='ready'?1:0;return rank(a)-rank(b)||a.load_number-b.load_number})[0]
 const result:ProductionLoad[]=[]
 if(primary&&((primary.status==='ready'&&primary.plant_zone)||(['departed','arrived'].includes(primary.status)&&primary.site_zone&&!primary.left_site_at)))result.push(primary)
 // A driver can confirm completion before leaving; GPS exit remains independent.
 result.push(...own.filter(l=>l.status==='completed'&&l.site_zone&&!l.left_site_at&&l.completed_at&&now-Date.parse(l.completed_at)<12*3600000))
 return result
}
// Invalid/stale browser fixes never reach the event API. Server repeats these checks.
export function locationSample(p:GeolocationPosition,now=Date.now()){
 const {latitude,longitude,accuracy}=p.coords
 if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||!Number.isFinite(accuracy)||Math.abs(latitude)>90||Math.abs(longitude)>180||accuracy<0||accuracy>50||!Number.isFinite(p.timestamp)||now-p.timestamp>45000||p.timestamp-now>5000)return null
 return{latitude,longitude,accuracy_m:accuracy,sampled_at:new Date(p.timestamp).toISOString()}
}
