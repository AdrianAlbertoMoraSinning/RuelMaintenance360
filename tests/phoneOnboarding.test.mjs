import test from 'node:test'
import assert from 'node:assert/strict'
import {normalizePhone,validSmsCode} from '../src/lib/phoneOnboarding.ts'
test('Canadian local and formatted numbers resolve to the same E.164 login',()=>{
 assert.equal(normalizePhone('(780) 555-0123'),'+17805550123')
 assert.equal(normalizePhone('+1 780 555 0123'),'+17805550123')
 assert.equal(normalizePhone('17805550123'),'+17805550123')
})
test('invalid numbers and non-SMS payloads are rejected before Auth requests',()=>{
 for(const phone of ['', 'abc', '+0 780 555 0123','+1;fetch()','1234567'])assert.throws(()=>normalizePhone(phone))
 for(const code of ['12345','1234567','12345a','12 345'])assert.equal(validSmsCode(code),false)
 assert.equal(validSmsCode(' 123456 '),true)
})
