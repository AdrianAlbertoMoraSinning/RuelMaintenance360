import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { saveNewPassword, type PasswordPurpose } from '../lib/authFlow'

function WelcomeBrand() {
  return <div className="brand" aria-label="RUEL MAINTENANCE 360"><span className="brand-ruel">RUEL</span><span className="brand-label">MAINTENANCE 360</span></div>
}

export default function PasswordSetup({ email, purpose, onComplete, onCancel }: {
  email?: string; purpose: PasswordPurpose; onComplete: () => void; onCancel: () => Promise<void>
}) {
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function submit(event: FormEvent) {
    event.preventDefault(); if (busy) return
    setBusy(true); setError('')
    const problem = await saveNewPassword(password, confirmation, attributes => supabase.auth.updateUser(attributes))
    if (problem) { setError(problem); setBusy(false); return }
    setPassword(''); setConfirmation(''); onComplete()
  }
  async function cancel() {
    setBusy(true); setError('')
    try { await onCancel() } catch { setError('Unable to sign out. Please try again.'); setBusy(false) }
  }
  return <main className="login-page"><section className="login-card">
    <WelcomeBrand/><p className="eyebrow">{purpose === 'invite' ? 'Welcome to RUEL' : 'Secure account recovery'}</p>
    <h1>{purpose === 'invite' ? 'Create your password' : 'Set a new password'}</h1>
    <p className="muted">{email ? <>Account: <strong>{email}</strong>. </> : null}Choose a password to access Maintenance 360.</p>
    <form onSubmit={submit}>
      <label>New password<input type="password" autoComplete="new-password" minLength={10} required value={password} disabled={busy} onChange={e => setPassword(e.target.value)}/></label>
      <label>Confirm new password<input type="password" autoComplete="new-password" minLength={10} required value={confirmation} disabled={busy} onChange={e => setConfirmation(e.target.value)}/></label>
      <p className="field-help">Use at least 10 characters. Keep your password and invitation link private.</p>
      {error && <div className="error-box" role="alert">{error}</div>}
      <button className="primary-button" disabled={busy}>{busy ? 'Saving…' : 'Save password & continue'}</button>
      <button className="secondary-outline" type="button" disabled={busy} onClick={cancel}>Sign out</button>
    </form>
  </section></main>
}

export function AuthLinkProblem({ onReturn }: { onReturn: () => Promise<void> }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function returnToLogin() {
    setBusy(true)
    try { await onReturn() } catch { setError('Unable to sign out. Please try again.'); setBusy(false) }
  }
  return <main className="login-page"><section className="login-card"><WelcomeBrand/>
    <p className="eyebrow">Account access</p><h1>This link could not be verified</h1>
    <p className="muted">Your invitation or recovery link may have expired or already been used. Ask your RUEL administrator for a new link. If you already created your password, return to sign in.</p>
    {error && <div className="error-box" role="alert">{error}</div>}
    <button className="primary-button" disabled={busy} onClick={returnToLogin}>{busy ? 'Please wait…' : 'Return to sign in'}</button>
  </section></main>
}
