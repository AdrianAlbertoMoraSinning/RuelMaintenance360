type MarkedRecord={asset_code?:string;title?:string;observations?:string|null}
export function isTrainingPerformanceRecord(record:MarkedRecord){
 return /^MOC[-_]/i.test(record.asset_code||'')||[record.title,record.observations].some(value=>/^\s*\[MOC(?:\s+TRAINING)?\]/i.test(value||''))
}
// Filter before aggregation so KPI values and their drill-down records agree.
// Keep the source records available in their operational/training modules.
export function operationalPerformanceRecords<A extends MarkedRecord&{id:string},W extends MarkedRecord&{asset_id:string},P extends MarkedRecord&{asset_id:string},I extends MarkedRecord&{asset_id:string}>(assets:A[],orders:W[],plans:P[],inspections:I[]){
 const trainingAssets=new Set(assets.filter(isTrainingPerformanceRecord).map(a=>a.id))
 const operational=<T extends MarkedRecord&{asset_id:string}>(row:T)=>!trainingAssets.has(row.asset_id)&&!isTrainingPerformanceRecord(row)
 return{assets:assets.filter(a=>!trainingAssets.has(a.id)),orders:orders.filter(operational),plans:plans.filter(operational),inspections:inspections.filter(operational)}
}
