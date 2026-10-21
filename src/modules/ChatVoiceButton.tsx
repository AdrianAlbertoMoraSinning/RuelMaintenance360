import {FieldIcon} from './OperatorObservationForm'
type Props={recording:boolean;disabled:boolean;onClick:()=>void}
export default function ChatVoiceButton({recording,disabled,onClick}:Props){const label=recording?'Stop dictating message':'Dictate message';return <button type="button" className={`chat-voice-button ${recording?'is-recording':''}`} disabled={disabled} onClick={onClick} aria-label={label} title={label} aria-pressed={recording}><FieldIcon name={recording?'stop':'mic'}/></button>}
