// Browser speech recognition is optional; no audio file is retained by this module.
type Result = {isFinal:boolean;0:{transcript:string}}
type Recognition = {
 lang:string;continuous:boolean;interimResults:boolean;
 onresult:((event:{resultIndex:number;results:ArrayLike<Result>})=>void)|null;
 onend:(()=>void)|null;onerror:((event:{error?:string})=>void)|null;
 start:()=>void;stop:()=>void;abort:()=>void;
}
export type TaskSpeechConstructor = new()=>Recognition
export function appendTaskDictation(text:string,words:string){return `${text.trimEnd()} ${words.trim()}`.trim().slice(0,10000)}
export function createTaskDictation(onActive:(active:boolean)=>void,onMessage:(message:string)=>void){
 let current:Recognition|null=null
 function abort(){const rec=current;current=null;if(rec){rec.onresult=null;rec.onend=null;rec.onerror=null;try{rec.abort()}catch{/* Already ended. */}}onActive(false)}
 return {
  get active(){return current!==null},
  abort,
  stop(){if(current)try{current.stop()}catch{abort()}},
  start(Speech:TaskSpeechConstructor|undefined,language:string,onText:(words:string)=>void){
   abort()
   if(!Speech){onMessage('Voice input is not supported in this browser. Tap the microphone on your phone keyboard to dictate the text.');return}
   const rec=new Speech();current=rec
   rec.lang=language;rec.continuous=true;rec.interimResults=false
   rec.onresult=event=>{if(current!==rec)return;const words=Array.from(event.results).slice(event.resultIndex).filter(r=>r.isFinal).map(r=>r[0].transcript).join(' ').trim();if(words)onText(words)}
   rec.onend=()=>{if(current!==rec)return;current=null;onActive(false);onMessage('Voice input finished. Review and edit the text before sending.')}
   rec.onerror=event=>{if(current!==rec)return;const denied=event.error==='not-allowed'||event.error==='service-not-allowed';abort();onMessage(denied?'Microphone access was denied. Allow the microphone or use your phone keyboard to enter the text.':'Voice input stopped. Your transcribed text is still here. You can type or use your phone keyboard microphone.')}
   try{onMessage('');onActive(true);rec.start()}catch{abort();onMessage('Unable to start voice input. Use your phone keyboard microphone or type the text.')}
  }
 }
}
