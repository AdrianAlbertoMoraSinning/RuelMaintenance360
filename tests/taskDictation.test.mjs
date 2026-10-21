import test from 'node:test'
import assert from 'node:assert/strict'
import {appendTaskDictation,createTaskDictation} from '../src/lib/taskDictation.ts'
class Speech {
 static sessions=[]
 constructor(){Speech.sessions.push(this)}
 start(){} stop(){this.stopped=true} abort(){this.aborted=true}
 result(words,final=true){this.onresult?.({resultIndex:0,results:[{isFinal:final,0:{transcript:words}}]})}
}
function setup(){const states=[],messages=[];return {states,messages,voice:createTaskDictation(v=>states.push(v),v=>messages.push(v))}}
test('dictated instructions append final text once, remain editable and support language selection',()=>{
 const{voice}=setup();let text='Inspect mixer';voice.start(Speech,'es-CO',words=>text=appendTaskDictation(text,words));const rec=Speech.sessions.at(-1)
 assert.equal(rec.lang,'es-CO');rec.result('partial',false);assert.equal(text,'Inspect mixer');rec.result('Check bearing');assert.equal(text,'Inspect mixer Check bearing')
 text+=' safely';rec.onresult({resultIndex:1,results:[{isFinal:true,0:{transcript:'Check bearing'}},{isFinal:true,0:{transcript:'Report findings'}}]});assert.equal(text,'Inspect mixer Check bearing safely Report findings');voice.abort()
})
test('stop waits for final transcript before enabling submission',()=>{
 const{voice,states}=setup();let text='';voice.start(Speech,'en-CA',w=>text=w);const rec=Speech.sessions.at(-1);voice.stop();assert.equal(rec.stopped,true);assert.equal(voice.active,true);rec.result('Final instruction');rec.onend();assert.equal(text,'Final instruction');assert.equal(voice.active,false);assert.equal(states.at(-1),false)
})
test('closing or switching tasks prevents late results from changing another draft',()=>{
 const{voice}=setup();let first='',second='';voice.start(Speech,'en-CA',w=>first+=w);const old=Speech.sessions.at(-1);const late=old.onresult;const lateEnd=old.onend;voice.abort();voice.start(Speech,'en-CA',w=>second+=w);late({resultIndex:0,results:[{isFinal:true,0:{transcript:'Wrong task'}}]});lateEnd();assert.equal(voice.active,true);Speech.sessions.at(-1).result('Correct task');assert.equal(first,'');assert.equal(second,'Correct task');voice.abort()
})
test('unsupported browser and denied microphone offer fallback without losing text',()=>{
 const{voice,messages}=setup();voice.start(undefined,'en-CA',()=>assert.fail());assert.equal(voice.active,false);assert.match(messages.at(-1),/phone keyboard/)
 let text='Keep this';voice.start(Speech,'en-CA',w=>text+=w);const rec=Speech.sessions.at(-1);rec.onerror({error:'not-allowed'});assert.equal(voice.active,false);assert.equal(text,'Keep this');assert.match(messages.at(-1),/denied/);assert.equal(rec.aborted,true)
})
test('start failures release the microphone state and text respects the task limit',()=>{
 const{voice,messages}=setup();class Broken extends Speech{start(){throw Error('unavailable')}}voice.start(Broken,'en-CA',()=>assert.fail());assert.equal(voice.active,false);assert.match(messages.at(-1),/Unable/);assert.equal(appendTaskDictation('a'.repeat(9999),'word').length,10000)
})
