export type PartPosition={location_id:string;location_name?:string;position_code?:string;quantity_on_hand?:number;quantity_reserved?:number;quantity_available?:number;quantity_on_order?:number;next_expected_at?:string|null;available?:number;on_hand?:number;reserved?:number;on_order?:number;expected_at?:string|null}
export function materialReadiness(required:number,positions:PartPosition[],preferred=''){
 const selected=preferred?positions.find(p=>p.location_id===preferred):[...positions].sort((a,b)=>Number(b.quantity_available??b.available??0)-Number(a.quantity_available??a.available??0)||String(a.location_name||'').localeCompare(String(b.location_name||'')))[0]
 const available=Math.max(0,Number(selected?.quantity_available??selected?.available??0))
 return {available,missing:Math.max(0,required-available),onOrder:Math.max(0,Number(selected?.quantity_on_order??selected?.on_order??0)),locationId:selected?.location_id||preferred,locationName:selected?.location_name||'No stock position',expectedAt:selected?.next_expected_at||selected?.expected_at||null}
}
