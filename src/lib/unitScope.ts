// Focused navigation is a view filter; database authorization still applies independently.
export function scopeUnitQuery<T>(query:T,unitId?:string|null):T{return unitId?(query as T&{eq:(column:string,value:string)=>T}).eq('business_unit_id',unitId):query}
export function unitContext<T extends{id:string}>(units:T[],unitId?:string|null){return unitId?units.filter(unit=>unit.id===unitId):units}

export function performanceNavigation(from:string,to:string,recordId:string|undefined,unitId:string|undefined,previousUnit:string|null){
 if(from==='business_units'&&unitId)return unitId
 if(previousUnit&&!recordId&&['observations','todo'].includes(to))return previousUnit
 return null
}
