-- Verified Google Play purchases for Omni Plan Pro.
-- Rows are written only by the `plan-billing` and `play-rtdn` Edge Functions
-- (service role) after Google Play confirmed the purchase. The app can read
-- its own rows and can never write.

create table if not exists public.plan_purchases (
  purchase_token   text primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  product_id       text not null
    check (product_id in ('omni_plan_pro_monthly', 'omni_plan_pro_yearly', 'omni_plan_pro_lifetime')),
  kind             text not null check (kind in ('subscription', 'lifetime')),
  state            text not null
    check (state in ('pending', 'active', 'cancelled', 'grace', 'on_hold', 'paused', 'expired', 'revoked')),
  expires_at       timestamptz,
  auto_renewing    boolean not null default false,
  is_trial         boolean not null default false,
  order_id         text,
  acknowledged     boolean not null default false,
  last_verified_at timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists plan_purchases_user_idx on public.plan_purchases (user_id);

alter table public.plan_purchases enable row level security;

drop policy if exists "plan_purchases_select_own" on public.plan_purchases;
create policy "plan_purchases_select_own"
  on public.plan_purchases for select
  to authenticated
  using (auth.uid() = user_id);

-- No insert/update/delete policy exists, and the grants are removed as well.
revoke insert, update, delete on public.plan_purchases from anon, authenticated;
revoke all on public.plan_purchases from anon;
