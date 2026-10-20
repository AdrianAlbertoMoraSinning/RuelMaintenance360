export type OfflineObservationPhoto={id:string;name:string;type:string;blob:Blob;caption:string}
export type OfflineObservationDraft={id:string;userId?:string;created_at:string;business_unit_id:string;asset_id:string|null;observation_type:string;description:string;immediate_concern:string;photos:OfflineObservationPhoto[];serverObservationId?:string}

const DB_NAME='ruel-maintenance-360-field';
const DB_VERSION=1;
const STORE='observation_drafts';

function openDb():Promise<IDBDatabase>{
  return new Promise((resolve,reject)=>{
    const request=indexedDB.open(DB_NAME,DB_VERSION)
    request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:'id'})}
    request.onsuccess=()=>resolve(request.result)
    request.onerror=()=>reject(request.error||new Error('Unable to open IndexedDB'))
  })
}

async function withStore<T>(mode:IDBTransactionMode,fn:(store:IDBObjectStore)=>IDBRequest<T>):Promise<T>{
  const db=await openDb()
  try{return await new Promise<T>((resolve,reject)=>{const tx=db.transaction(STORE,mode);const req=fn(tx.objectStore(STORE));req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error||new Error('IndexedDB operation failed'));tx.onerror=()=>reject(tx.error||new Error('IndexedDB transaction failed'))})}finally{db.close()}
}

export async function listObservationDrafts():Promise<OfflineObservationDraft[]>{
  const rows=await withStore<OfflineObservationDraft[]>('readonly',s=>s.getAll())
  return rows.sort((a,b)=>a.created_at.localeCompare(b.created_at))
}
export async function saveObservationDraft(draft:OfflineObservationDraft){await withStore<IDBValidKey>('readwrite',s=>s.put(draft))}
export async function removeObservationDraft(id:string){await withStore<undefined>('readwrite',s=>s.delete(id) as IDBRequest<undefined>)}
