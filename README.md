# TJ Earn — Stage 1 Foundation

Production Flutter Android rewards app. **Stage 1 only**: auth, home dashboard,
server-side wallet, transaction history, withdrawal requests, in-app updater,
Urdu + English. No ads SDKs in Stage 1 (and never AdMob for cash rewards —
see below).

- **Package (fixed forever):** `com.tjearn.app`
- **Version:** 1.0.0+1
- **Backend:** Supabase (PostgreSQL) — delivered as files here, not yet applied
  to any live project. No Supabase / provider / Play accounts exist yet.
- **Signing:** a dedicated TJ Earn keystore (NOT the Aman/TJ keystore, NOT an
  ephemeral CI key). The keystore file and passwords live ONLY in this repo's
  GitHub Actions secrets (`KEYSTORE_BASE64`, `KEYSTORE_STORE_PASSWORD`,
  `KEYSTORE_KEY_PASSWORD`). CI debug builds are signed with it, so the
  update chain is stable from the first install: same package + same key +
  higher versionCode = update, never reinstall.
- **No live channels yet:** no manifest, no website link, no Drive file.
  Stage 1 builds are TEST builds only.

## The one rule that shapes everything

**The wallet balance is never stored as a user-editable value in the app.**
Balance = `SUM(ledger.amount_coins)` on the server. The app only reads it
(`get-balance` Edge Function) and reads its own ledger rows. Coins are
granted only by Edge Functions (service role) after a verified callback.
Proof: `grep -rn "from('ledger').insert" lib/` returns zero matches.

## Coin economy (config, not hardcoded)

- 1 coin = Rs 0.01 (100 coins = Rs 1)
- Minimum withdrawal: 20,000 coins = Rs 200
- Maximum 2 pending withdrawal requests per user
- Withdrawal amounts must be whole rupees (multiples of 100 coins)

These live in `app_config` and are re-validated by `request-withdrawal`.

## Advertising providers (Stage 2)

Only providers that permit the reward model: **Unity Offerwall** and **AdGem**
(offerwall offers = the cash engine). **AdMob is excluded** — its policy bans
cash-per-view apps, and using it here would endanger the existing AdMob
account under review for the other apps. Rewarded video only after a
provider's written permission. No provider SDK is wired in Stage 1; the
Offers page shows an honest empty state instead of fake offers.

## Setup (free tier)

### 1. Create a Supabase project (free tier)

1. Create a project at supabase.com (no card required on free tier).
2. Note the project URL and anon key (Project Settings → API).
3. Open the SQL editor and run, in order:
   `supabase/migrations/20261028000001_tj_earn_stage1.sql`
   (creates profiles, ledger, withdrawals, audit_logs, app_config,
   app_versions, RLS policies, append-only triggers, and the
   new-user profile trigger).
4. Deploy the Edge Functions (Supabase CLI, logged in, linked to the
   project):
   ```
   supabase functions deploy get-balance
   supabase functions deploy request-withdrawal
   supabase functions deploy version-check --no-verify-jwt
   supabase functions deploy simulate-callback --no-verify-jwt
   ```
   `simulate-callback` is TEST ONLY: it also requires the project setting
   `ALLOW_TEST_CALLBACKS=true`, and must be deleted (or the flag turned
   off) before any production use.
5. After the first test APK exists, update the `app_versions` row with its
   real `apk_url` so the in-app updater can find it:
   `update app_versions set apk_url = '<test apk url>' where version_code = 1;`

### 2. Run the app

```
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

Without these defines the app shows a clear "App not configured" screen
and never displays a fake balance.

### 3. Test the full loop (no providers needed)

1. Register, then confirm the user in Supabase Auth (or disable email
   confirmation on the test project).
2. Credit test coins (project with `ALLOW_TEST_CALLBACKS=true`):
   ```
   curl -X POST https://YOUR-PROJECT.supabase.co/functions/v1/simulate-callback \
     -H "apikey: YOUR-ANON-KEY" -H "Content-Type: application/json" \
     -d '{"user_id":"<uuid>","amount_coins":25000,"idempotency_key":"test-1","provider":"test","type":"offer"}'
   ```
   Replaying the same `idempotency_key` must return 409 `already_credited`.
3. In the app: Home shows the balance, Wallet shows history, Withdraw
   accepts Rs 200+ whole-rupee requests and lists them as `pending`.

### 4. Checks

```
flutter analyze
flutter test
```

## Stage 1 file list

- `lib/main.dart` — app entry, locale state, auth gate, config-error screen
- `lib/config.dart` — `--dart-define` Supabase config (never fake data)
- `lib/services/validation.dart` — pure rules (conversion, minimums, caps,
  version comparison, idempotency guard) — unit-tested
- `lib/services/supabase_service.dart` — auth, balance, ledger, withdrawals
  (reads only; no ledger writes anywhere in `lib/`)
- `lib/services/updater_service.dart` — version-check → dialog → download →
  platform install intent (same package + key + higher versionCode = update)
- `lib/screens/` — auth, home, offers (honest Stage 2 empty state), wallet,
  withdraw, settings (language switch en/ur, logout), bottom-nav shell
- `lib/l10n/` — `app_en.arb` + `app_ur.arb` (Urdu script, RTL for `ur`)
- `android/` — package `com.tjearn.app`, label "TJ Earn", keystore signing
  config, FileProvider + install-permission flow for the updater
- `supabase/migrations/` — schema + RLS + append-only guards + seeds
- `supabase/functions/` — get-balance, request-withdrawal,
  simulate-callback (TEST ONLY), version-check
- `.github/workflows/build-apk.yml` — analyze + test + keystore-signed
  debug APK + artifact

## Known Stage 1 gaps (Stage 2+)

- No provider SDKs or signed callbacks yet (Stage 2: Unity Offerwall, AdGem).
- No admin web dashboard yet (Stage 4; admin reads/writes go through the
  service role, never through app roles).
- Withdrawals store only the **masked** account (`account_masked`). MVP
  payouts are manual: the admin obtains the full account from the user for
  the transfer. A Stage 3 decision is whether to add an encrypted payout
  details store.
- No Play Integrity / emulator detection yet (Stage 5 hardening).
- Device testing on a real phone is pending (no emulator path on the build
  machine); CI proves compile, analyze, tests, and a signed installable APK.
