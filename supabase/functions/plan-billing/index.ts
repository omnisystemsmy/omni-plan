// Omni Plan Pro: verifies Google Play purchases and answers "is this person Pro?".
//
//   POST { "action": "verify", "productId": "...", "purchaseToken": "..." }
//   POST { "action": "refresh" }
//   POST { "action": "status" }
//
// The caller must be signed in (a normal, non-guest account). Every answer
// comes from Google Play via the Developer API, never from the app.

import { PRODUCTS } from '../_shared/entitlement.ts'
import { NotConfigured, PlayError } from '../_shared/play.ts'
import { adminClient, COLUMNS, entitlementOf, lookup, save } from '../_shared/sync.ts'

const cors = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
}

const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'content-type': 'application/json' },
  })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return reply(405, { ok: false, error: 'method_not_allowed' })

  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!jwt) return reply(401, { ok: false, error: 'not_signed_in' })
  // Auth validates the caller's own access token (signature, expiry, user exists).
  const { data: auth, error: authError } = await adminClient().auth.getUser(jwt)
  const user = auth?.user
  if (authError || !user) return reply(401, { ok: false, error: 'not_signed_in' })
  if (user.is_anonymous) return reply(403, { ok: false, error: 'guest_not_allowed' })

  // deno-lint-ignore no-explicit-any
  let input: any
  try {
    input = await req.json()
  } catch {
    return reply(400, { ok: false, error: 'bad_request' })
  }

  const db = adminClient()
  try {
    if (input.action === 'verify') {
      const productId = String(input.productId ?? '')
      const token = String(input.purchaseToken ?? '')
      const kind =
        productId === PRODUCTS.lifetime
          ? 'lifetime'
          : productId === PRODUCTS.monthly || productId === PRODUCTS.yearly
            ? 'subscription'
            : null
      if (!kind || token.length < 10 || token.length > 4096) {
        return reply(400, { ok: false, error: 'bad_request' })
      }
      const { data: existing } = await db
        .from('plan_purchases')
        .select('user_id')
        .eq('purchase_token', token)
        .maybeSingle()
      if (existing && existing.user_id !== user.id) {
        return reply(409, { ok: false, error: 'owned_by_another_account' })
      }
      let v
      try {
        v = await lookup(kind, token)
      } catch (e) {
        if (e instanceof PlayError && e.status >= 400 && e.status < 500) {
          return reply(422, { ok: false, error: 'rejected' })
        }
        if (e instanceof Error && e.message === 'unknown_product') {
          return reply(422, { ok: false, error: 'rejected' })
        }
        throw e
      }
      // The purchase was made while signed in as somebody else.
      if (v.accountId && v.accountId !== user.id) {
        return reply(409, { ok: false, error: 'owned_by_another_account' })
      }
      await save(db, user.id, token, v)
    } else if (input.action === 'refresh') {
      const { data: rows } = await db
        .from('plan_purchases')
        .select(COLUMNS)
        .eq('user_id', user.id)
        .limit(20)
      for (const r of rows ?? []) {
        try {
          await save(db, user.id, r.purchase_token, await lookup(r.kind, r.purchase_token))
        } catch (e) {
          // Keep what is stored if Google cannot be reached right now.
          if (e instanceof NotConfigured) throw e
          console.error('refresh failed', e instanceof Error ? e.message : e)
          if (!(e instanceof PlayError) || e.status >= 500) throw e
        }
      }
    } else if (input.action !== 'status') {
      return reply(400, { ok: false, error: 'bad_request' })
    }
    return reply(200, { ok: true, entitlement: await entitlementOf(db, user.id) })
  } catch (e) {
    if (e instanceof NotConfigured) return reply(503, { ok: false, error: 'not_configured' })
    console.error('plan-billing', e instanceof Error ? e.message : e)
    return reply(502, { ok: false, error: 'unavailable' })
  }
})
