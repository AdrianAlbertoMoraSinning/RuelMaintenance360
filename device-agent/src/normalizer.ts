export type MachineIdentity = Partial<Record<
  'serial_number'|'vin'|'obd_vin'|'j1939_name'|'ecu_serial'|'ecu_address'|'plc_station'|'oem_machine_id'|'other',
  string
>>

export type NormalizedReading = {
  source_key?: string
  metric_key?: string
  value: number
  unit: string
  recorded_at: string
  source_reference?: string
  notes?: string
}

export type NormalizedFault = {
  code: string
  subsystem?: string
  severity?: 'info'|'warning'|'critical'
  description?: string
  recommended_action?: string
  raw?: unknown
}

export type NormalizedDiagnosticBatch = {
  captured_at: string
  identity: MachineIdentity
  readings: NormalizedReading[]
  faults: NormalizedFault[]
  source_reference?: string
  metadata: Record<string,unknown>
}

function clean(value:unknown){return String(value??'').trim()}
function finite(value:unknown){const n=Number(value);return Number.isFinite(n)?n:null}

export function normalizeJsonPayload(input:unknown):NormalizedDiagnosticBatch{
  const root=(input&&typeof input==='object'?input:{}) as Record<string,unknown>
  const identity=(root.identity&&typeof root.identity==='object'?root.identity:{}) as Record<string,unknown>
  const readings=Array.isArray(root.readings)?root.readings:[]
  const faults=Array.isArray(root.faults)?root.faults:[]
  return {
    captured_at:clean(root.captured_at)||new Date().toISOString(),
    identity:Object.fromEntries(Object.entries(identity).map(([k,v])=>[k,clean(v)]).filter(([,v])=>v)) as MachineIdentity,
    readings:readings.flatMap((r:any)=>{const value=finite(r?.value);const unit=clean(r?.unit);if(value===null||!unit)return[];return[{source_key:clean(r.source_key)||undefined,metric_key:clean(r.metric_key)||undefined,value,unit,recorded_at:clean(r.recorded_at)||new Date().toISOString(),source_reference:clean(r.source_reference)||undefined,notes:clean(r.notes)||undefined}]}),
    faults:faults.flatMap((f:any)=>{const code=clean(f?.code);if(!code)return[];const sev=clean(f.severity);return[{code,subsystem:clean(f.subsystem)||undefined,severity:['info','warning','critical'].includes(sev)?sev as any:undefined,description:clean(f.description)||undefined,recommended_action:clean(f.recommended_action)||undefined,raw:f}]}),
    source_reference:clean(root.source_reference)||undefined,
    metadata:(root.metadata&&typeof root.metadata==='object'?root.metadata:{}) as Record<string,unknown>
  }
}

export function parseSimpleCsv(text:string):Record<string,string>[] {
  const lines=text.split(/\r?\n/).map(x=>x.trim()).filter(Boolean)
  if(lines.length<2)return[]
  const headers=splitCsvLine(lines[0])
  return lines.slice(1).map(line=>{
    const values=splitCsvLine(line)
    return Object.fromEntries(headers.map((h,i)=>[h,values[i]??'']))
  })
}

function splitCsvLine(line:string){
  const out:string[]=[];let current='';let quoted=false
  for(let i=0;i<line.length;i++){
    const ch=line[i]
    if(ch==='"'&&line[i+1]==='"'){current+='"';i++;continue}
    if(ch==='"'){quoted=!quoted;continue}
    if(ch===','&&!quoted){out.push(current.trim());current='';continue}
    current+=ch
  }
  out.push(current.trim());return out
}

export function normalizeCsvReadings(text:string, mapping:Record<string,{metric_key:string;unit:string;scale?:number;offset?:number}>):NormalizedReading[]{
  const rows=parseSimpleCsv(text);const now=new Date().toISOString();const out:NormalizedReading[]=[]
  for(const row of rows){
    for(const [sourceKey,rule] of Object.entries(mapping)){
      const raw=finite(row[sourceKey]);if(raw===null)continue
      out.push({source_key:sourceKey,metric_key:rule.metric_key,value:raw*(rule.scale??1)+(rule.offset??0),unit:rule.unit,recorded_at:row.recorded_at||row.timestamp||now})
    }
  }
  return out
}

export interface DiagnosticTransportAdapter {
  readonly transportType:string
  connect():Promise<void>
  disconnect():Promise<void>
  readIdentity():Promise<MachineIdentity>
  capture():Promise<NormalizedDiagnosticBatch>
}

export class OfflineDiagnosticQueue {
  private readonly key='ruel-maintenance360-diagnostic-queue-v1'
  load():NormalizedDiagnosticBatch[]{try{return JSON.parse(localStorage.getItem(this.key)||'[]')}catch{return[]}}
  save(items:NormalizedDiagnosticBatch[]){localStorage.setItem(this.key,JSON.stringify(items))}
  enqueue(batch:NormalizedDiagnosticBatch){const items=this.load();items.push(batch);this.save(items)}
  remove(index:number){const items=this.load();items.splice(index,1);this.save(items)}
}
