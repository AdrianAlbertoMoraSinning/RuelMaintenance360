import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { BusinessUnit } from './AssetsSection'
import EquipmentDiagnosticsSection from './EquipmentDiagnosticsSection'

type Props={units:BusinessUnit[];role:string}

export default function EquipmentDiagnosticsEmbedded({units,role}:Props){
  const [userId,setUserId]=useState<string|null>(null)
  useEffect(()=>{supabase.auth.getUser().then(({data})=>setUserId(data.user?.id||null))},[])
  if(!userId)return <div className="loading-panel">Loading diagnostics security context…</div>
  return <EquipmentDiagnosticsSection units={units} userId={userId} role={role}/>
}
