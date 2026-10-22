export type WorkspaceRead='tasks'|'recipients'|'assets'|'plans'
type ReadResult={data:any[]|null;error:unknown}
// A failed inbox or optional catalogue must not discard successfully loaded assignment recipients.
export async function settleTaskWorkspace(reads:Record<WorkspaceRead,()=>PromiseLike<ReadResult>>){
 const keys:WorkspaceRead[]=['tasks','recipients','assets','plans']
 const results=await Promise.allSettled(keys.map(key=>Promise.resolve().then(()=>reads[key]())))
 return Object.fromEntries(keys.map((key,index)=>{const result=results[index];return[key,result.status==='fulfilled'?result.value:{data:null,error:result.reason}]})) as Record<WorkspaceRead,ReadResult>
}
