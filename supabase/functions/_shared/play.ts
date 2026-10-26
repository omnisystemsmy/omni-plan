// Google Play Developer API access. The service-account key is read from a
// Supabase secret and never leaves the server.

import { PRODUCTS, type PurchaseState } from './entitlement.ts'

export const PACKAGE_NAME = Deno.env.get('PLAY_PACKAGE_NAME') ?? 'com.omnisystems.omniplan'
export const TRIAL_OFFER_ID = 'yearly-free-trial'

export class NotConfigured extends Error {}
export class PlayError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

const enc = new TextEncoder()
const b64url = (data: ArrayBuffer | string) => {
  const bytes = typeof data === 'string' ? enc.encode(data) : new Uint8Array(data)
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

let cached: { token: string; until: number } | null = null

async function accessToken(): Promise<string> {
  if (cached && cached.until > Date.now() + 60_000) return cached.token
  const raw = Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON')
  if (!raw) throw new NotConfigured('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not set')
  let sa: { client_email: string; private_key: string }
  try {
    sa = JSON.parse(raw)
  } catch {
    throw new NotConfigured('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not valid JSON')
  }
  const iat = Math.floor(Date.now() / 1000)
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat,
      exp: iat + 3600,
    }),
  )
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(`${head}.${claims}`))
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${head}.${claims}.${b64url(sig)}`,
    }),
  })
  if (!res.ok) throw new PlayError(res.status, `Google token request failed (${res.status})`)
  const body = await res.json()
  cached = { token: body.access_token, until: Date.now() + (body.expires_in ?? 3000) * 1000 }
  return cached.token
}

async function play(method: string, path: string, body?: unknown) {
  const res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}/${path}`,
    {
      method,
      headers: {
        authorization: `Bearer ${await accessToken()}`,
        'content-type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    },
  )
  if (!res.ok) throw new PlayError(res.status, `Google Play API ${res.status}: ${await res.text()}`)
  const text = await res.text()
  return text ? JSON.parse(text) : {}
}

/** What Google says about one purchase, in the shape the table stores. */
export interface Verified {
  productId: string
  kind: 'subscription' | 'lifetime'
  state: PurchaseState
  expiresAt: string | null
  autoRenewing: boolean
  isTrial: boolean
  orderId: string | null
  acknowledged: boolean
  accountId: string | null
}

// deno-lint-ignore no-explicit-any
export function mapSubscription(j: any, now: Date = new Date()): Verified {
  const line = (j.lineItems ?? [])[0] ?? {}
  const stateMap: Record<string, PurchaseState> = {
    SUBSCRIPTION_STATE_PENDING: 'pending',
    SUBSCRIPTION_STATE_ACTIVE: 'active',
    SUBSCRIPTION_STATE_CANCELED: 'cancelled',
    SUBSCRIPTION_STATE_IN_GRACE_PERIOD: 'grace',
    SUBSCRIPTION_STATE_ON_HOLD: 'on_hold',
    SUBSCRIPTION_STATE_PAUSED: 'paused',
    SUBSCRIPTION_STATE_EXPIRED: 'expired',
    SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: 'revoked',
  }
  const start = j.startTime ? new Date(j.startTime).getTime() : 0
  const inTrialWindow = start > 0 && now.getTime() < start + 8 * 24 * 3600 * 1000
  return {
    productId: line.productId ?? '',
    kind: 'subscription',
    state: stateMap[j.subscriptionState] ?? 'expired',
    expiresAt: line.expiryTime ?? null,
    autoRenewing: line.autoRenewingPlan?.autoRenewEnabled === true,
    isTrial: line.offerDetails?.offerId === TRIAL_OFFER_ID && inTrialWindow,
    orderId: j.latestOrderId ?? null,
    acknowledged: j.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    accountId: j.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
  }
}

// deno-lint-ignore no-explicit-any
export function mapLifetime(productId: string, j: any): Verified {
  // purchaseState: 0 purchased, 1 canceled (refunded), 2 pending.
  const state: PurchaseState =
    j.purchaseState === 0 ? 'active' : j.purchaseState === 2 ? 'pending' : 'revoked'
  return {
    productId,
    kind: 'lifetime',
    state,
    expiresAt: null,
    autoRenewing: false,
    isTrial: false,
    orderId: j.orderId ?? null,
    acknowledged: j.acknowledgementState === 1,
    accountId: j.obfuscatedExternalAccountId ?? null,
  }
}

export async function fetchSubscription(token: string): Promise<Verified> {
  return mapSubscription(await play('GET', `purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`))
}

export async function fetchLifetime(token: string): Promise<Verified> {
  return mapLifetime(
    PRODUCTS.lifetime,
    await play('GET', `purchases/products/${PRODUCTS.lifetime}/tokens/${encodeURIComponent(token)}`),
  )
}

/** Google refunds an unacknowledged purchase after three days. */
export async function acknowledge(v: Verified, token: string) {
  const t = encodeURIComponent(token)
  if (v.kind === 'subscription') {
    await play('POST', `purchases/subscriptions/${v.productId}/tokens/${t}:acknowledge`, {})
  } else {
    await play('POST', `purchases/products/${v.productId}/tokens/${t}:acknowledge`, {})
  }
}
