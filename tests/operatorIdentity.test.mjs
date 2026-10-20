import test from 'node:test'
import assert from 'node:assert/strict'
import {operatorUsername,operatorAuthAddress,loginAddress} from '../supabase/functions/_shared/operatorIdentity.ts'
test('operator usernames remain stable without using phone or name',()=>{
 assert.equal(operatorUsername('b6a1f147-ae25-4b3e-bdb5-f35c5b4addba'),'op-b6a1f147ae25')
 assert.equal(operatorAuthAddress(' OP-B6A1F147AE25 '),'op-b6a1f147ae25@operators.ruelmaintenance360.invalid')
 assert.equal(loginAddress(' OP-B6A1F147AE25 '),operatorAuthAddress('op-b6a1f147ae25'))
 assert.equal(loginAddress(' manager@example.com '),'manager@example.com')
 for(const input of ['+17806252210','7806252210','DJ','op-bad',''])assert.throws(()=>loginAddress(input))
 assert.throws(()=>operatorUsername('not-a-profile-id'))
})
