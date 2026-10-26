import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { evaluate, PRODUCTS, SUBSCRIPTION_IDS, type PurchaseRow } from './entitlement.ts'
import { acknowledge, fetchLifetime, fetchSubscription, type Verified } from './play.ts'

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  })
}

export const COLUMNS =
  'purchase_token, product_id, kind, state, expires_at, auto_renewing, is_trial'

/** Ask Google about one token. Throws when Google rejects it. */
export async function lookup(kind: 'subscription' | 'lifetime', token: string): Promise<Verified> {
  const v = kind === 'lifetime' ? await fetchLifetime(token) : await fetchSubscription(token)
  const expected = kind === 'lifetime' ? [PRODUCTS.lifetime] : SUBSCRIPTION_IDS
  if (!expected.includes(v.productId)) throw new Error('unknown_product')
  return v
}

/** Store what Google said, acknowledging the purchase when it is paid for. */
export async function save(
  db: SupabaseClient,
  userId: string,
  token: string,
  v: Verified,
): Promise<void> {
  let acknowledged = v.acknowledged
  if (!acknowledged && (v.state === 'active' || v.state === 'cancelled' || v.state === 'grace')) {
    try {
      await acknowledge(v, token)
      acknowledged = true
    } catch (e) {
      console.error('acknowledge failed', e instanceof Error ? e.message : e)
    }
  }
  const { error } = await db.from('plan_purchases').upsert(
    {
      purchase_token: token,
      user_id: userId,
      product_id: v.productId,
      kind: v.kind,
      state: v.state,
      expires_at: v.expiresAt,
      auto_renewing: v.autoRenewing,
      is_trial: v.isTrial,
      order_id: v.orderId,
      acknowledged,
      last_verified_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'purchase_token' },
  )
  if (error) throw new Error(`save failed: ${error.message}`)
}

export async function entitlementOf(db: SupabaseClient, userId: string) {
  const { data, error } = await db.from('plan_purchases').select(COLUMNS).eq('user_id', userId)
  if (error) throw new Error(`read failed: ${error.message}`)
  return evaluate((data ?? []) as PurchaseRow[])
}
