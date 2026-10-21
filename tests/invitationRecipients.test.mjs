import test from 'node:test'
import assert from 'node:assert/strict'
import {supervisorInvitationRecipients} from '../supabase/functions/_shared/invitationRecipients.ts'
const don={id:'don',active:true,email:'don@ruelconcreteltd.com'}
const adrian={id:'adrian',active:true,email:'concrete@ruelconcreteltd.com'}
test('operator invitation addresses supervisor and copies that supervisor’s manager',()=>{
 assert.deepEqual(supervisorInvitationRecipients(don,adrian),{to:['don@ruelconcreteltd.com'],cc:['concrete@ruelconcreteltd.com']})
 assert.deepEqual(supervisorInvitationRecipients(don,{...adrian,id:'replacement',email:' New.Manager@example.com '}),{to:['don@ruelconcreteltd.com'],cc:['new.manager@example.com']})
})
test('missing/inactive manager, invalid addresses and self-reporting cannot silently omit manager CC',()=>{
 for(const manager of [null,{...adrian,active:false},{...adrian,email:null},{...adrian,email:'invalid'},don])assert.throws(()=>supervisorInvitationRecipients(don,manager))
 assert.throws(()=>supervisorInvitationRecipients({...don,active:false},adrian))
})
test('a shared destination is not emailed twice',()=>{
 assert.deepEqual(supervisorInvitationRecipients(don,{...adrian,email:don.email}),{to:[don.email],cc:[]})
})
