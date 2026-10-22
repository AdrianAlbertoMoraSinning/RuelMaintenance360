type Control=HTMLInputElement|HTMLSelectElement|HTMLTextAreaElement
export function controlValue(control:Control){return control instanceof HTMLInputElement&&['checkbox','radio'].includes(control.type)?String(control.checked):control.value}
export function trackUpdateEdits(doc:Document){
 const baseline=new Map<Control,string>(),changed=new Set<Control>()
 const control=(target:EventTarget|null)=>target instanceof HTMLInputElement||target instanceof HTMLSelectElement||target instanceof HTMLTextAreaElement?target:null
 const remember=(event:Event)=>{const c=control(event.target);if(c&&!baseline.has(c))baseline.set(c,controlValue(c))}
 const edit=(event:Event)=>{const c=control(event.target);if(c){if(!baseline.has(c)&&!(c instanceof HTMLSelectElement))baseline.set(c,c instanceof HTMLInputElement&&['checkbox','radio'].includes(c.type)?String(c.defaultChecked):c.defaultValue);changed.add(c)}}
 const reset=(event:Event)=>{for(const c of changed)if(c.form===event.target){changed.delete(c);baseline.delete(c)}}
 doc.addEventListener('focusin',remember,true);doc.addEventListener('pointerdown',remember,true)
 doc.addEventListener('input',edit,true);doc.addEventListener('change',edit,true);doc.addEventListener('reset',reset,true)
 return{blocked(){
  for(const c of baseline.keys())if(!c.isConnected){baseline.delete(c);changed.delete(c)}
  for(const c of changed){if(!c.isConnected||baseline.get(c)===controlValue(c)){changed.delete(c);continue}return true}
  return false
 },stop(){doc.removeEventListener('focusin',remember,true);doc.removeEventListener('pointerdown',remember,true);doc.removeEventListener('input',edit,true);doc.removeEventListener('change',edit,true);doc.removeEventListener('reset',reset,true)}}
}
