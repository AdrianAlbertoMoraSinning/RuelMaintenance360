import {useChatDictation} from '../lib/useChatDictation'
import {appendTaskDictation} from '../lib/taskDictation'
import {useUpdateBlocker} from '../lib/useUpdateBlocker'
import ChatVoiceButton from './ChatVoiceButton'
export default function ProductionVoiceField({label,value,onChange,scope,disabled=false}:{label:string;value:string;onChange:(s:string)=>void;scope:string;disabled?:boolean}){const voice=useChatDictation(scope,true,disabled,words=>onChange(appendTaskDictation(value,words)));useUpdateBlocker(voice.recording||!!value);return <div className="production-voice"><label>{label}<textarea value={value} maxLength={10000} onChange={e=>onChange(e.target.value)} disabled={disabled} placeholder="Type or tap the microphone…"/></label><ChatVoiceButton recording={voice.recording} disabled={disabled} onClick={voice.toggle}/>{voice.feedback&&<p role="status">{voice.feedback}</p>}<small>Voice to text · Review before sending. You can also attach an audio recording.</small></div>}
