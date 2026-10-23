import type {ProductionLoad} from './production'
export function manualDeliveryActions(load:Pick<ProductionLoad,'status'|'left_site_at'>){
 if(load.status==='ready')return[{event:'departed',label:'Mark departed · notify order creator',confirm:'Confirm that this loaded vehicle has actually left the plant? This updates customer tracking and notifies the order creator.'}]
 if(load.status==='departed')return[{event:'arrived',label:'Mark arrived',confirm:'Confirm that this vehicle has arrived at the delivery jobsite? This records the arrival now, updates customer tracking and notifies the order creator.'}]
 if(['arrived','completed'].includes(load.status)&&!load.left_site_at)return[{event:'site_left',label:'Mark left site',confirm:'Confirm that this vehicle has actually left the jobsite? This records the exit now and updates customer tracking. It does not record customer acceptance.'}]
 if(load.status==='arrived'&&load.left_site_at)return[{event:'completed',label:'Complete delivery',confirm:'Confirm that this delivery service is finished? This closes the load, updates customer tracking and notifies the order creator. A missing customer signature stays pending.'}]
 return[]
}
