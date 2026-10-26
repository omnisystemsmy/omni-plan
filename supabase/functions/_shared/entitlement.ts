// Pure rules that turn stored, Google-verified purchase rows into one answer.
// Nothing here talks to the network.

export type PurchaseState =
  | 'pending'
  | 'active'
  | 'cancelled'
  | 'grace'
  | 'on_hold'
  | 'paused'
  | 'expired'
  | 'revoked'

export interface PurchaseRow {
  purchase_token: string
  product_id: string
  kind: 'subscription' | 'lifetime'
  state: PurchaseState
  expires_at: string | null
  auto_renewing: boolean
  is_trial: boolean
}

export type EntitlementStatus =
  | 'free'
  | 'active'
  | 'cancelled_active'
  | 'pending'
  | 'expired'

export interface Entitlement {
  status: EntitlementStatus
  isPro: boolean
  lifetime: boolean
  expiresAt: string | null
  trial: boolean
  productId: string | null
}

export const PRODUCTS = {
  monthly: 'omni_plan_pro_monthly',
  yearly: 'omni_plan_pro_yearly',
  lifetime: 'omni_plan_pro_lifetime',
} as const

export const SUBSCRIPTION_IDS: string[] = [PRODUCTS.monthly, PRODUCTS.yearly]

const free: Entitlement = {
  status: 'free',
  isPro: false,
  lifetime: false,
  expiresAt: null,
  trial: false,
  productId: null,
}

/** Subscription states in which Google says the person still has access. */
function entitledNow(r: PurchaseRow, now: Date): boolean {
  if (r.kind === 'lifetime') return r.state === 'active'
  if (r.state !== 'active' && r.state !== 'cancelled' && r.state !== 'grace') {
    return false
  }
  return r.expires_at != null && new Date(r.expires_at).getTime() > now.getTime()
}

export function evaluate(rows: PurchaseRow[], now: Date = new Date()): Entitlement {
  const life = rows.find((r) => r.kind === 'lifetime' && entitledNow(r, now))
  if (life) {
    return { ...free, status: 'active', isPro: true, lifetime: true, productId: life.product_id }
  }
  const subs = rows
    .filter((r) => r.kind === 'subscription' && entitledNow(r, now))
    .sort((a, b) => new Date(b.expires_at!).getTime() - new Date(a.expires_at!).getTime())
  const best = subs[0]
  if (best) {
    const renewing = best.state === 'active' && best.auto_renewing
    return {
      status: renewing || best.state === 'grace' ? 'active' : 'cancelled_active',
      isPro: true,
      lifetime: false,
      expiresAt: best.expires_at,
      trial: best.is_trial,
      productId: best.product_id,
    }
  }
  if (rows.some((r) => r.state === 'pending')) return { ...free, status: 'pending' }
  if (rows.length > 0) return { ...free, status: 'expired' }
  return free
}
