import {useEffect,useRef,useState} from 'react'
import {createTaskDictation,type TaskSpeechConstructor} from './taskDictation'
export function useChatDictation(scope:string,active:boolean,disabled:boolean,onWords:(words:string)=>void){
 const[recording,setRecording]=useState(false),[feedback,setFeedback]=useState('')
 const callback=useRef(onWords);callback.current=onWords
 const speech=useRef<ReturnType<typeof createTaskDictation>|null>(null)
 if(!speech.current)speech.current=createTaskDictation(setRecording,setFeedback)
 useEffect(()=>{speech.current?.abort();setFeedback('');return()=>speech.current?.abort()},[scope])
 useEffect(()=>{if(!active||disabled)speech.current?.abort()},[active,disabled])
 useEffect(()=>{const stop=()=>speech.current?.abort();const hidden=()=>{if(document.visibilityState==='hidden')stop()};window.addEventListener('ruel:workspace-change',stop);document.addEventListener('visibilitychange',hidden);return()=>{window.removeEventListener('ruel:workspace-change',stop);document.removeEventListener('visibilitychange',hidden);stop()}},[])
 function toggle(){
  if(!active||disabled)return
  if(speech.current?.active){speech.current.stop();return}
  const Speech=((window as any).SpeechRecognition||(window as any).webkitSpeechRecognition) as TaskSpeechConstructor|undefined
  const language=navigator.language?.toLowerCase().startsWith('es')?'es-CO':'en-CA'
  speech.current?.start(Speech,language,words=>callback.current(words))
 }
 return {recording,feedback,toggle,isActive:()=>!!speech.current?.active}
}
