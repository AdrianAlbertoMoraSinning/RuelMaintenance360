export type PasswordPurpose = 'invite' | 'recovery'
type SetupStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>
const setupKey = (userId: string) => `ruel.password-setup.${userId}`

// Capture only the purpose/error flag. Never retain tokens from the URL.
export function readAuthReturn(search: string, hash: string) {
  const query = new URLSearchParams(search)
  const fragment = new URLSearchParams(hash.replace(/^#/, ''))
  const type = fragment.get('type') || query.get('type')
  const purpose: PasswordPurpose | null = type === 'invite' || type === 'recovery' ? type : null
  return { purpose, failed: ['error', 'error_code'].some(key => query.has(key) || fragment.has(key)) }
}

export function setupStorage(): SetupStorage | undefined {
  try { return window.localStorage } catch { return undefined }
}

export function pendingPasswordSetup(storage: SetupStorage | undefined, userId: string): PasswordPurpose | null {
  try { const value = storage?.getItem(setupKey(userId)); return value === 'invite' || value === 'recovery' ? value : null } catch { return null }
}

export function rememberPasswordSetup(storage: SetupStorage | undefined, userId: string, purpose: PasswordPurpose) {
  try { storage?.setItem(setupKey(userId), purpose) } catch { /* The current page still holds the intent. */ }
}

export function forgetPasswordSetup(storage: SetupStorage | undefined, userId: string) {
  try { storage?.removeItem(setupKey(userId)) } catch { /* Storage can be unavailable in private browsing. */ }
}

export function cleanAuthPath(pathname: string, search: string) {
  const query = new URLSearchParams(search)
  for (const key of ['type', 'error', 'error_code', 'error_description', 'access_token', 'refresh_token', 'token_hash', 'code', 'setup']) query.delete(key)
  return pathname + (query.size ? `?${query.toString()}` : '')
}

export async function saveNewPassword(
  password: string,
  confirmation: string,
  update: (attributes: { password: string }) => Promise<{ error: { message: string } | null }>,
): Promise<string | null> {
  if (password.length < 10) return 'Use at least 10 characters.'
  if (password !== confirmation) return 'The passwords do not match.'
  try { const { error } = await update({ password }); return error ? (error.message || 'Unable to save your password. Please try again.') : null }
  catch { return 'Unable to save your password. Check your connection and try again.' }
}
