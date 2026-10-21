export type UnitObservation={id:string;observation_number:number;business_unit_id:string;asset_id:string|null;observation_type:string;description:string;status:string;reported_by:string;assigned_manager_id:string|null;submitted_at:string;updated_at:string}
export type UnitTask={id:string;task_number:number;business_unit_id:string|null;title:string;description:string;status:string;due_at:string|null;progress:number;assigner_name:string|null;assignee_name:string|null;asset_code:string|null;updated_at:string}
export type UnitAction={id:string;observation_id:string;instructions:string;assigned_to:string|null;status:string;due_at:string|null}
export type Timing='overdue'|'on_time'|'no_due_date'
export function observationPending(o:Pick<UnitObservation,'status'>){return !['resolved','closed_no_action','rejected'].includes(o.status)}
export function taskPending(t:Pick<UnitTask,'status'>){return !['completed','cancelled'].includes(t.status)}
export function dueTiming(due:string|null,now=Date.now()):Timing{if(!due||!Number.isFinite(Date.parse(due)))return 'no_due_date';return Date.parse(due)<now?'overdue':'on_time'}
export function observationTiming(id:string,actions:UnitAction[],now=Date.now()):Timing{const pending=actions.filter(a=>a.observation_id===id&&!['completed','cancelled'].includes(a.status));if(pending.some(a=>dueTiming(a.due_at,now)==='overdue'))return 'overdue';return pending.some(a=>dueTiming(a.due_at,now)==='on_time')?'on_time':'no_due_date'}
export function unitPending(unitId:string,observations:UnitObservation[],tasks:UnitTask[]){return{observations:observations.filter(o=>o.business_unit_id===unitId&&observationPending(o)),tasks:tasks.filter(t=>t.business_unit_id===unitId&&taskPending(t))}}
// Stable pagination prevents the API row cap from silently understating a unit's backlog.
export async function activityPages<T>(read:(start:number,end:number)=>PromiseLike<{data:T[]|null;error:unknown}>){const rows:T[]=[];for(let start=0;;start+=500){const r=await read(start,start+499);if(r.error)throw r.error;rows.push(...(r.data||[]));if(!r.data||r.data.length<500)return rows}}
