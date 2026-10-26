# Omni Plan backend (Supabase)

Project ref: `oqsnrzfoohhjqqenxmhl` (Omni Apps, shared with Omni Tools). Omni Plan
only uses objects prefixed `docs_` and the functions below. Omni Tools is not
touched, and buying Pro in one app does **not** unlock the other.

| Piece | Purpose |
| --- | --- |
| `migrations/20261025000000_plan_purchases.sql` | table `plan_purchases` (RLS: a person can read only their own rows; nobody can write from the app) |
| `functions/plan-billing` | the app calls it to verify a purchase, refresh, or read status. It asks Google Play, then writes the row. |
| `functions/play-rtdn` | receives Google Play Real-time Developer Notifications (renewal, cancel, refund, revoke) and re-reads the state from Google |
| `functions/_shared/entitlement.ts` | the rule that turns rows into "Pro or not" |

No service-account key and no service-role key is in the app.

## One-time setup (none of this has been done by the code)

1. **Google Cloud**: create a service account in a Google Cloud project, create a
   JSON key, and enable the *Google Play Android Developer API* in that project.
2. **Play Console → Users and permissions → Invite new users**: add the service
   account's email and give it, for Omni Plan only, *View financial data* and
   *Manage orders and subscriptions*. It can take up to a few hours to take effect.
3. **Database**: from this folder's parent run
   `supabase link --project-ref oqsnrzfoohhjqqenxmhl` then `supabase db push`
   (or paste the migration into the SQL editor).
4. **Secrets**:
   ```
   supabase secrets set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="$(cat key.json)"
   supabase secrets set PLAY_PACKAGE_NAME=com.omnisystems.omniplan
   supabase secrets set RTDN_SHARED_SECRET=<a long random string>
   ```
5. **Deploy**:
   ```
   supabase functions deploy plan-billing
   supabase functions deploy play-rtdn --no-verify-jwt
   ```
6. **Real-time notifications** (recommended, so refunds and renewals arrive
   without waiting for the app to open): in Google Cloud create a Pub/Sub topic,
   grant `google-play-developer-notifications@system.gserviceaccount.com` the
   *Pub/Sub Publisher* role on it, create a **push** subscription to
   `https://oqsnrzfoohhjqqenxmhl.supabase.co/functions/v1/play-rtdn?secret=<RTDN_SHARED_SECRET>`,
   then in Play Console → *Monetization setup* set the topic name and send a test.

Until steps 1 to 5 are done the function answers `not_configured`, the app grants
nothing, and a purchase stays unconfirmed (and un-acknowledged on the device).
Google refunds an unacknowledged purchase after three days.

## How it decides

- A purchase token is bound to the first signed-in (non-guest) account that
  verifies it. Another account presenting it gets `owned_by_another_account`.
- The app attaches the buyer's user id as the Play *obfuscated account id*; the
  server rejects the purchase if Google reports a different one.
- Subscription: entitled while Google's state is active, cancelled (paid period
  not over), or in grace period, and the expiry is in the future. On hold,
  paused, expired and pending are not entitled.
- Lifetime: entitled while Google reports `purchaseState = 0`. A refund makes it
  1, and the next check (app launch, Restore, or a notification) removes Pro.
- The server acknowledges each paid purchase itself.
