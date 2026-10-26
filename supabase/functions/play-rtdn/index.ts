// Google Play Real-time Developer Notifications, delivered by a Pub/Sub push
// subscription to  <function url>?secret=<RTDN_SHARED_SECRET>.
//
// A notification only tells us "something changed for this token". The new
// state is always read back from the Google Play Developer API.

import { PACKAGE_NAME, NotConfigured } from '../_shared/play.ts'
import { adminClient, lookup, save } from '../_shared/sync.ts'

const ok = () => new Response('ok', { status: 200 })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 })
  const secret = Deno.env.get('RTDN_SHARED_SECRET')
  if (!secret) return new Response('not configured', { status: 503 })
  if (new URL(req.url).searchParams.get('secret') !== secret) {
    return new Response('forbidden', { status: 403 })
  }

  try {
    const envelope = await req.json()
    const data = envelope?.message?.data
    if (!data) return ok()
    const note = JSON.parse(atob(data))
    if (note.packageName !== PACKAGE_NAME) return ok()

    const token: string | undefined =
      note.subscriptionNotification?.purchaseToken ??
      note.oneTimeProductNotification?.purchaseToken ??
      note.voidedPurchaseNotification?.purchaseToken
    if (!token) return ok() // test notification or an event we do not use

    const db = adminClient()
    const { data: row } = await db
      .from('plan_purchases')
      .select('user_id, kind')
      .eq('purchase_token', token)
      .maybeSingle()
    // Unknown token: the person has not verified it in the app yet.
    if (!row) return ok()

    await save(db, row.user_id, token, await lookup(row.kind, token))
    return ok()
  } catch (e) {
    console.error('play-rtdn', e instanceof Error ? e.message : e)
    // Pub/Sub retries on a non-2xx answer, except when we are not set up.
    return new Response(e instanceof NotConfigured ? 'not configured' : 'error', {
      status: e instanceof NotConfigured ? 503 : 500,
    })
  }
})
