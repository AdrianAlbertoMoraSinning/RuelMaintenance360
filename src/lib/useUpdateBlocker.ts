import{useLayoutEffect}from'react'
import{updateSafety}from'./appUpdate'
// Keep in-memory drafts, camera processing, dictation and writes ahead of updates.
export function useUpdateBlocker(blocked:boolean){useLayoutEffect(()=>{if(blocked)return updateSafety.hold()},[blocked])}
