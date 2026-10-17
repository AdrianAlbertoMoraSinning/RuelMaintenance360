// Display decisions mirror the database read API; authorization is enforced there.
export function canViewCosts(role: string) {
  return ['super_admin', 'corporate_manager', 'unit_supervisor'].includes(role)
}

export function costFields<T extends Record<string, unknown>>(allowed: boolean, fields: T): Partial<T> {
  return allowed ? fields : {}
}
