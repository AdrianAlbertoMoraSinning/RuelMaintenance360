export function taskNetworkError(error:unknown){const message=typeof error==='string'?error:(error as {message?:string})?.message||'';return /failed to fetch|fetch failed|networkerror|network request failed|load failed/i.test(message)}
// Retry reads only: a lost response to an assignment or approval must never replay it.
export async function retryTaskRead<T extends {error:unknown}>(read:()=>PromiseLike<T>):Promise<T>{
 try{const result=await read();if(!taskNetworkError(result.error))return result}catch(error){if(!taskNetworkError(error))throw error}
 return await read()
}
export function taskRefreshError(error:unknown){return taskNetworkError(error)?'Connection interrupted. Showing the last loaded tasks. Tap Refresh to try again.':(error as {message?:string})?.message||'Unable to refresh tasks. Showing the last loaded tasks. Tap Refresh to try again.'}
export function taskActionError(error:unknown,fallback:string){return taskNetworkError(error)?'Connection interrupted. The result could not be confirmed. Refresh the task before trying again.':(error as {message?:string})?.message||fallback}
