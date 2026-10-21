export type PartMachine={part_id:string;asset_id:string;asset_code:string;asset_name:string;business_unit_name:string|null;relationship_type:'installed'|'compatible';installed_quantity:number;component_system:string|null;installation_position:string|null}
type Link={part_id:string;asset_id:string;relationship_type:string;installed_quantity:number|string;component_system:string|null;installation_position:string|null}
type Asset={id:string;asset_code:string;name:string;business_unit_id:string}
type Unit={id:string;name:string}
export function joinPartMachines(partIds:string[],links:Link[],assets:Asset[],units:Unit[]):PartMachine[]{
 const allowed=new Set(partIds),machines=new Map(assets.map(a=>[a.id,a])),names=new Map(units.map(u=>[u.id,u.name])),seen=new Set<string>(),rows:PartMachine[]=[]
 for(const link of links){const asset=machines.get(link.asset_id),key=link.part_id+':'+link.asset_id;if(!allowed.has(link.part_id)||!asset||seen.has(key)||!['installed','compatible'].includes(link.relationship_type))continue;seen.add(key);rows.push({part_id:link.part_id,asset_id:asset.id,asset_code:asset.asset_code,asset_name:asset.name,business_unit_name:names.get(asset.business_unit_id)||null,relationship_type:link.relationship_type as 'installed'|'compatible',installed_quantity:link.relationship_type==='installed'?Number(link.installed_quantity):0,component_system:link.component_system,installation_position:link.installation_position})}
 return rows.sort((a,b)=>a.part_id.localeCompare(b.part_id)||(a.relationship_type==='installed'?0:1)-(b.relationship_type==='installed'?0:1)||a.asset_code.localeCompare(b.asset_code))
}
// All reads use the signed-in client's existing RLS. Never request or infer hidden machines.
export async function loadPartMachines(db:{from:(table:string)=>any},partIds:string[]):Promise<PartMachine[]>{
 const ids=[...new Set(partIds)];if(!ids.length)return []
 const links:Link[]=[]
 for(let offset=0;;offset+=500){const{data,error}=await db.from('asset_part_compatibility').select('part_id,asset_id,relationship_type,installed_quantity,component_system,installation_position').in('part_id',ids).order('part_id').order('asset_id').range(offset,offset+499);if(error)throw error;links.push(...(data||[]));if(!data||data.length<500)break}
 const assetIds=[...new Set(links.map(l=>l.asset_id))],assets:Asset[]=[]
 for(let offset=0;offset<assetIds.length;offset+=100){const{data,error}=await db.from('assets').select('id,asset_code,name,business_unit_id').in('id',assetIds.slice(offset,offset+100));if(error)throw error;assets.push(...(data||[]))}
 const unitIds=[...new Set(assets.map(a=>a.business_unit_id))],units:Unit[]=[]
 for(let offset=0;offset<unitIds.length;offset+=100){const{data,error}=await db.from('business_units').select('id,name').in('id',unitIds.slice(offset,offset+100));if(error)throw error;units.push(...(data||[]))}
 return joinPartMachines(ids,links,assets,units)
}
