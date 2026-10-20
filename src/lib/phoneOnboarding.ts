export function normalizePhone(value: string): string {
  let phone = value.trim().replace(/[\s().-]/g, '')
  if (/^\d{10}$/.test(phone)) phone = '+1' + phone
  else if (/^1\d{10}$/.test(phone)) phone = '+' + phone
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) throw new Error('Enter a valid mobile number including country code, e.g. +1 780 555 0123.')
  return phone
}

export function validSmsCode(value: string): boolean {
  return /^\d{6}$/.test(value.trim())
}
