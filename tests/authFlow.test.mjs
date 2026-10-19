import test from 'node:test'
import assert from 'node:assert/strict'
import {
  readAuthReturn, pendingPasswordSetup, rememberPasswordSetup,
  forgetPasswordSetup, cleanAuthPath, saveNewPassword,
} from '../src/lib/authFlow.ts'

function memoryStorage() {
  const values = new Map()
  return { values, getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) }
}

test('invitation callback captures purpose without retaining its credentials', () => {
  const result = readAuthReturn('', '#access_token=fixture-access&refresh_token=fixture-refresh&type=invite')
  assert.deepEqual(result, { purpose: 'invite', failed: false })
  assert.ok(!JSON.stringify(result).includes('fixture-'))
})

test('recovery, expired links and ordinary QR links are distinguished', () => {
  assert.deepEqual(readAuthReturn('', '#type=recovery'), { purpose: 'recovery', failed: false })
  assert.deepEqual(readAuthReturn('', '#error=access_denied&error_code=otp_expired'), { purpose: null, failed: true })
  assert.deepEqual(readAuthReturn('?type=invite&error_code=otp_expired', ''), { purpose: 'invite', failed: true })
  assert.deepEqual(readAuthReturn('?asset=fixture&mode=observation', ''), { purpose: null, failed: false })
  assert.deepEqual(readAuthReturn('', '#type=magiclink'), { purpose: null, failed: false })
})

test('unfinished setup resumes for the correct user and clears only after completion', () => {
  const storage = memoryStorage()
  rememberPasswordSetup(storage, 'user-a', 'invite')
  rememberPasswordSetup(storage, 'user-b', 'recovery')
  assert.equal(pendingPasswordSetup(storage, 'user-a'), 'invite')
  assert.equal(pendingPasswordSetup(storage, 'user-b'), 'recovery')
  assert.equal(pendingPasswordSetup(storage, 'user-c'), null)
  assert.deepEqual([...storage.values.values()], ['invite', 'recovery'])
  forgetPasswordSetup(storage, 'user-a')
  assert.equal(pendingPasswordSetup(storage, 'user-a'), null)
  assert.equal(pendingPasswordSetup(storage, 'user-b'), 'recovery')
})

test('blocked browser storage does not crash the password flow', () => {
  const storage = { getItem() { throw Error('blocked') }, setItem() { throw Error('blocked') }, removeItem() { throw Error('blocked') } }
  assert.doesNotThrow(() => rememberPasswordSetup(storage, 'user-a', 'invite'))
  assert.equal(pendingPasswordSetup(storage, 'user-a'), null)
  assert.doesNotThrow(() => forgetPasswordSetup(storage, 'user-a'))
  assert.equal(pendingPasswordSetup(undefined, 'user-a'), null)
})

test('auth URL cleanup removes credentials and preserves the intended asset context', () => {
  const clean = cleanAuthPath('/', '?asset=fixture&mode=observation&type=invite&access_token=secret&refresh_token=secret&error_description=private&code=secret')
  assert.equal(clean, '/?asset=fixture&mode=observation')
})

test('short or mismatched passwords never reach the account API', async () => {
  let calls = 0
  const update = async () => { calls++; return { error: null } }
  assert.equal(await saveNewPassword('short', 'short', update), 'Use at least 10 characters.')
  assert.equal(await saveNewPassword('fixture-password', 'different-password', update), 'The passwords do not match.')
  assert.equal(calls, 0)
})

test('server rejection and connection failure cannot be mistaken for success', async () => {
  const password = 'fixture-password'
  assert.equal(await saveNewPassword(password, password, async () => ({ error: { message: 'Link session expired' } })), 'Link session expired')
  assert.ok(await saveNewPassword(password, password, async () => ({ error: { message: '' } })))
  assert.match(await saveNewPassword(password, password, async () => { throw Error('network failure') }), /Check your connection/)
})

test('valid matching passwords are sent once without trimming or storing them', async () => {
  let received
  const password = '  fixture-password  '
  const storage = memoryStorage()
  rememberPasswordSetup(storage, 'user-a', 'invite')
  assert.equal(await saveNewPassword(password, password, async attributes => { received = attributes; return { error: null } }), null)
  assert.deepEqual(received, { password })
  assert.ok(!JSON.stringify([...storage.values]).includes(password))
})
