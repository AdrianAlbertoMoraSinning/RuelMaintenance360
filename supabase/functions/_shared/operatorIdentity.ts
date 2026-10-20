// Internal Auth address only. It is never a contact address or mail destination.
const domain = 'operators.ruelmaintenance360.invalid'
export function operatorUsername(profileId: string): string {
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(profileId)) throw new Error('Invalid operator account')
  return 'op-' + profileId.replaceAll('-', '').slice(0,12).toLowerCase()
}
export function operatorAuthAddress(username: string): string {
  const value = username.trim().toLowerCase()
  if (!/^op-[a-f0-9]{12}$/.test(value)) throw new Error('Enter your assigned operator username, or your work email address.')
  return value + '@' + domain
}
export function loginAddress(identifier: string): string {
  const value=identifier.trim()
  return value.includes('@') ? value : operatorAuthAddress(value)
}
