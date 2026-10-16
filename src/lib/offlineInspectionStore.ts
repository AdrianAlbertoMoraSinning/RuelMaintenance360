const DB_NAME='ruel-maintenance-360-offline'
const DB_VERSION=1
const STORE='inspection_drafts'

function openDb():Promise<IDBDatabase>{
  return new Promise((resolve,reject)=>{
    const req=indexedDB.open(DB_NAME,DB_VERSION)
    req.onupgradeneeded=()=>{
      const db=req.result
      if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:'id'})
    }
    req.onsuccess=()=>resolve(req.result)
    req.onerror=()=>reject(req.error||new Error('Unable to open offline inspection database.'))
  })
}

function txDone(tx:IDBTransaction):Promise<void>{
  return new Promise((resolve,reject)=>{
    tx.oncomplete=()=>resolve()
    tx.onerror=()=>reject(tx.error||new Error('Offline inspection transaction failed.'))
    tx.onabort=()=>reject(tx.error||new Error('Offline inspection transaction was aborted.'))
  })
}

export async function listOfflineInspectionDrafts<T=any>():Promise<T[]>{
  const db=await openDb()
  try{
    const tx=db.transaction(STORE,'readonly')
    const req=tx.objectStore(STORE).getAll()
    const rows=await new Promise<T[]>((resolve,reject)=>{req.onsuccess=()=>resolve((req.result||[]) as T[]);req.onerror=()=>reject(req.error)})
    await txDone(tx)
    return rows
  }finally{db.close()}
}

export async function replaceOfflineInspectionDrafts(rows:any[]):Promise<void>{
  const db=await openDb()
  try{
    const tx=db.transaction(STORE,'readwrite')
    const store=tx.objectStore(STORE)
    store.clear()
    for(const row of rows)store.put(row)
    await txDone(tx)
  }finally{db.close()}
}

export async function migrateOfflineInspectionLocalStorage(keys:string[]):Promise<number>{
  const existing=await listOfflineInspectionDrafts<any>()
  const merged=new Map<string,any>()
  for(const row of existing)if(row?.id)merged.set(row.id,row)
  let migrated=0
  for(const key of keys){
    try{
      const parsed=JSON.parse(localStorage.getItem(key)||'[]')
      if(Array.isArray(parsed))for(const row of parsed){if(row?.id&&!merged.has(row.id)){merged.set(row.id,row);migrated++}}
    }catch{/* ignore corrupt legacy browser payload */}
  }
  if(migrated)await replaceOfflineInspectionDrafts([...merged.values()])
  for(const key of keys)localStorage.removeItem(key)
  return migrated
}

export async function clearOfflineInspectionDrafts():Promise<void>{
  await replaceOfflineInspectionDrafts([])
}
