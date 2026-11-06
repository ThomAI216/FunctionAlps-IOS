# Deployment — from a Windows desktop to TestFlight (Milestone 1)

> **Owner rule (2026-10-06): TestFlight builds go to INTERNAL testers only.** The `beta` lane uploads without external distribution unless a run sets `FA_TESTFLIGHT_EXTERNAL=true`, which needs the owner's explicit go for that build. The iOS workflow sets it for one run only: a push to `release/testflight` whose tip commit message contains `[external]` (2026-10-12; keep the marker off `main` commits, so a later `main:release/testflight` push cannot inherit it). Shipping itself (a push to `release/testflight`) also needs the owner's go.

You have no Mac, so "the manual path" (PRD §38) is the CI path: a GitHub macOS
runner archives, signs (fastlane `match`) and uploads. Everything you do by hand
happens in a browser. Sections §2–§4 describe the Mac-local equivalent for
reference only.

## 1. App Store Connect setup (one-time, web)
1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+ App ID**.
   - Bundle ID: `com.functionalps.patient` (explicit). **Decide once; never change after the ASC app record exists.**
   - Capabilities for v0.01: none beyond defaults. (Push, HealthKit, Sign in with Apple are added later, each needs an entitlement + a product reason.)
2. appstoreconnect.apple.com → My Apps → **+ New App**: platform iOS, name "FunctionAlps", primary language English, bundle ID above, SKU `functionalps-ios`.
3. TestFlight → Internal Testing → create group "Team" (up to 100 internal testers, no review). External groups need Beta App Review — later.
4. Users and Access → Integrations → **App Store Connect API** → generate a **Team Key** (role: App Manager is enough for uploads). Download the `.p8` immediately (it cannot be downloaded again). Store it outside the repo. Note Key ID + Issuer ID.

## 2. Signing (individual account)
- Xcode → target FunctionAlps → Signing & Capabilities → "Automatically manage signing" → Team = your personal team.
- Xcode creates the Development and Distribution certificates on first archive. Back up the private keys (Keychain Access → export `.p12`) to a password manager. Lost distribution keys cannot be recovered.
- The `project.yml` sets `CODE_SIGN_STYLE: Automatic` and reads `DEVELOPMENT_TEAM` from `Config/Local.xcconfig` (git-ignored) so the team id never lands in git.

## 3. Versioning
- `MARKETING_VERSION` = `0.1.0` for v0.01 (semantic, human-facing).
- `CURRENT_PROJECT_VERSION` = build number, integer, **must increase on every upload**. Manual for now; fastlane's `latest_testflight_build_number + 1` later.

## 4. Manual archive → upload
1. Select destination **Any iOS Device (arm64)**.
2. Product → **Archive**. Fix any archive-only errors (missing icons in `Assets.xcassets/AppIcon`, export compliance).
3. Organizer → Distribute App → **TestFlight & App Store** → Upload → automatic signing → Upload.
4. Wait for "Processing" to finish in App Store Connect (5–30 min). Missing-compliance prompt: set `ITSAppUsesNonExemptEncryption = NO` in Info.plist (we only use HTTPS) — already set in `project.yml`.
5. TestFlight → iOS builds → add the build to the internal group → testers get the TestFlight invite → install on iPhone.

## 5. The CI lane (the path that exists today)
Files: `.github/workflows/ios.yml` (job `testflight`, manual trigger), `FunctionAlps/fastlane/{Fastfile,Appfile,Matchfile}`, `Gemfile`.

How signing works without a Mac: `match` generates the Apple Distribution certificate + App Store provisioning profile on the runner using the App Store Connect API key, encrypts them with `MATCH_PASSWORD`, and commits them to the private certificates repo (`MATCH_GIT_URL`). Every later run pulls and reuses them. Revoking = delete the repo contents + revoke in the developer portal.

Required GitHub secrets (Settings → Secrets and variables → Actions):
| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | 10-character team id (developer.apple.com → Membership) |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | from App Store Connect → Users and Access → Integrations → App Store Connect API |
| `ASC_KEY_P8_BASE64` | `base64 -w0 AuthKey_XXXX.p8` (PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`) |
| `MATCH_GIT_URL` | `https://github.com/ThomAI216/FunctionAlps-CERTS.git` (private, empty) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `githubusername:personal_access_token` (PAT with repo scope) |
| `MATCH_PASSWORD` | new passphrase; store it in your password manager |

Run: Actions → **iOS** → Run workflow → branch → `testflight = true`, **or** push the commit you want to ship to the `release/testflight` branch (`git push origin main:release/testflight`) — that route is what the coding agent uses, since its GitHub integration cannot press Run workflow and its git proxy blocks tags. The lane increments the build number from the latest TestFlight build, archives Release, uploads, and waits for processing (up to 40 min) so it can hand the build to testers.

The Fastfile (already committed) has this shape:
```ruby
default_platform(:ios)

platform :ios do
  desc "Build and push a new beta to TestFlight"
  lane :beta do
    api_key = app_store_connect_api_key(
      key_id: ENV["ASC_KEY_ID"],
      issuer_id: ENV["ASC_ISSUER_ID"],
      key_filepath: ENV["ASC_KEY_PATH"],   # e.g. ~/.private/AuthKey_XXXX.p8 — never in repo
      duration: 1200
    )
    increment_build_number(
      build_number: latest_testflight_build_number(api_key: api_key) + 1,
      xcodeproj: "FunctionAlps.xcodeproj"
    )
    build_app(scheme: "FunctionAlps", export_method: "app-store")
    upload_to_testflight(api_key: api_key, skip_waiting_for_build_processing: true)
  end
end
```
Then `deploy beta` in the agent maps to `fastlane beta`. Code-signing stays Xcode-automatic for an individual account; `match` is only worth it when a second machine or CI appears (it revokes/recreates certificates on adoption — do not run it casually).

## 5a. When the upload stops at `match` with "PLA Update available"
Apple refuses every API call (certificates, profiles, uploads) until the team's **Account Holder** accepts the latest
Program License Agreement on developer.apple.com (and App Store Connect, if it shows one). The `match` step then fails
with `Unable to process request - PLA Update available`. Nothing in the repo can fix it. This happened on 2026-10-29
(the meal-photo build never reached TestFlight) and on 2026-11-05; the owner accepted the agreement on 2026-11-05.
After the agreement is accepted, push to `release/testflight` again (the agent cannot press Re-run).

## 5b. What the first upload taught us (2026-09-03, build 1 accepted)
- App Store Connect **requires the iOS 26 SDK**: both CI jobs select `Xcode_26*` on the runner. Xcode 16 builds are rejected at upload with "SDK version issue".
- `match` must run with `readonly: false` on CI the first time (fastlane defaults to read-only when it detects CI); it created the Apple Distribution certificate + App Store profile and stored them in `FunctionAlps-CERTS`.
- The bundle must contain a 1024×1024 icon in the asset catalog plus `CFBundleIconName`; portrait-only apps need `UIRequiresFullScreen = true` (or all four orientations). The current icon is a generated placeholder — replace `AppIcon-1024.png` with the real mark.
- Trigger from the agent side: push to `release/testflight` (tags are blocked by the agent's git proxy; the Run-workflow button is not available to its GitHub integration).

## 6. App Store Connect API for the agent (later)
Apple's ASC API (JWT signed with the `.p8`) can read builds, manage TestFlight groups/testers, and beta metadata. If an MCP is added for it, it runs **locally** on the Mac, reads the key from a local path, and is reviewed before use (PRD §35–36). Nothing in this repo assumes it exists.

## 7. Rollback / hygiene
- A bad TestFlight build is simply expired in ASC; never reuse a build number.
- Keep `MARKETING_VERSION` stable across builds of the same beta; bump it when the feature set changes.


## CI minutes (2026-09-04)

The repository is **public** since 2026-09-04: GitHub Actions minutes are unlimited for public repos, including the 10× macOS runners, which is why the private-repo allowance (2,000 min/month ≈ 200 macOS minutes ≈ 20 builds) stopped every job on 2026-09-03 with "no runner assigned" failures. The workflow still keeps usage low: a Linux pre-check skips the simulator job on docs-only pushes, and a `release/testflight` push archives without re-running the unit tests (the same commit was already tested on `main`). Nothing sensitive is in the history — the app holds only the publishable Supabase key; certificates, the ASC `.p8` and the match passphrase live only in repository secrets.

## HealthKit (added 2026-09-04)

The target declares `com.apple.developer.healthkit` (read-only), `com.apple.developer.healthkit.access: []`
and `com.apple.developer.healthkit.background-delivery` (XcodeGen `entitlements.properties` in `project.yml`).
The simulator build ignores entitlements (`CODE_SIGNING_ALLOWED=NO`), but the TestFlight archive does not:
**the App ID `com.functionalps.patient` must have the HealthKit capability enabled** in
Certificates, Identifiers & Profiles (Identifiers → the App ID → Capabilities → HealthKit → Save) before
the next `release/testflight` push. `match` regenerates the provisioning profile (`force: true`) but cannot
add a capability; without it the archive fails with "Provisioning profile doesn't include the
com.apple.developer.healthkit entitlement". Background delivery does not need a background mode.
Test HealthKit on a device — background observer queries do not run on the Simulator.

**2026-09-04, later — release path cleared.** The owner enabled the HealthKit capability on the App ID and
declared **Health** + **Fitness** under App Privacy in App Store Connect (App Functionality, linked to
identity, no tracking). Three more things ship with build 14 so that disclosure follows the code:

1. **Privacy Notice v9** (`supabase/migrations/20260904_privacy_policy_v9_wearables.sql`, applied to CM OS
   as `draft_pending_legal_review`, v8 still current): v8 + Apple Health / wearable data in §1, §4, §5, §6,
   a new §9a and §13, both locales, built from the live v8 rows with anchor-checked `replace()`. Members
   keep seeing v8 until the operator approves v9 (the SQL for that is in the file header).
   **Approved 2026-09-04** (operator: "APPROVE V9"; migration `privacy_policy_v9_approve` on CM OS): v8 superseded,
   v9 current → the Devices screen offers Connect Apple Health on every phone.
2. **The Connect gate** (`WearableDisclosure`): the Devices screen reads the current approved
   `privacy_policy` row and shows **Connect Apple Health** only when its version is v9 or later; before
   that it shows "Connecting opens as soon as the updated Privacy Notice … is published". A phone that
   already connected keeps syncing (the member saw the sheet under the notice that was current then — v9
   is required for NEW connections).
3. **The connection record**: `wearable-ingest` v20 (source of truth `supabase/functions/wearable-ingest/index.ts`,
   deployed with the Supabase MCP, verify_jwt) accepts `connection: "connected" | "disconnected"` and upserts
   `wearable_connections` (source 1000001, name `apple_health`) — sent with the first batch after Connect and
   on Disconnect. A batch that carries rows implies `connected`.

HRV stays SDNN (catalogue 3112): the native `member-scores` does not read wearable rows yet; when it does,
the recovery factor is a ratio to the member's own baseline, so it reads the first available series per
member — `RmssdSleep`, then `Rmssd`, then `SDNN` — and never mixes them. No conversion.

## Direct wearable connectors (added 2026-09-04)

Owner decision: free, direct OAuth integrations only — **Withings, Suunto, Oura, Polar, WHOOP, Garmin, Google (Fitbit)**;
Thryve removed (its three functions answer 410 and its cron is unscheduled; delete `thryve-connect`,
`thryve-webhook`, `thryve-sync` in the Supabase dashboard → Edge Functions when convenient). Devices whose
vendor has no public service keep arriving through the Apple Health relay.

**Source of truth:** `supabase/functions/_shared/wearables/{core,registry,<vendor>}.ts` + the five functions
`wearable-oauth-start` (member, verify_jwt), `wearable-oauth-callback` (public — the vendor redirects the browser
here), `wearable-vendor-webhook/<vendor>` (public — the vendor signs), `wearable-vendor-sync` (pg_cron every 10 min
while `wearable_sync_queue` has pending vendor rows, `x-report-secret`; also the member's "Sync now"; keeps Oura's
expiring webhook subscriptions alive once an hour), `wearable-vendor-disconnect` (member). Migration
`20260904_wearable_direct_connectors.sql` (applied): `wearable_vendors`, `wearable_vendor_accounts` (tokens
AES-256-GCM, service role only), `wearable_oauth_states`, `wearable_sync_queue.vendor`, raw-event kinds, catalogue
rows ≥ 1000100, the two crons.

**Deploying the functions — CI, not by hand.** `.github/workflows/deploy-edge-functions.yml` deploys, with the
Supabase CLI, exactly the functions a push to `main` touched (a change under `_shared/wearables/` deploys all five;
`workflow_dispatch` → "wearables" or one slug). It reads the live `verify_jwt` of every function first and refuses
to deploy if the `NO_JWT` list disagrees with the dashboard. It needs ONE repository secret:
`SUPABASE_ACCESS_TOKEN` (Settings → Secrets and variables → Actions) — the same account token FunctionAlps-APP's
workflow already uses (https://supabase.com/dashboard/account/tokens). **Set on 2026-09-14** as a scoped token
(project CM OS only: Project Settings Read + Edge Functions Read-write, nothing else); run 6 deployed the six connector
functions (verify_jwt: start/disconnect true, callback/webhook/sync/reconcile false — verified live), run 7 the updated
`member-scores` and `wearable-ingest`. The GitHub App cannot press "Run workflow" (403): to redeploy without a code
change, edit the marker comment in `_shared/wearables/registry.ts` (all six) or in the function's own `index.ts`.
`supabase/functions/build-wearables.sh` still bundles each function into `bundle/<name>.ts` (gitignored) as a
syntax check / fallback for the MCP `deploy_edge_function` path; CI does not use the bundles.

**Owner steps, once per vendor (developer portal → secrets → flip the row):**
1. Register the app. Redirect URI (exact): `https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-oauth-callback`.
   Webhook URL where the vendor asks for one: `https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-webhook/<vendor>`
   (`<vendor>` = `oura` | `whoop` | `polar` | `garmin` | `withings` | `suunto` | `google`). Privacy policy URL: the
   published FunctionAlps notice. Per vendor:
   - **Oura** — https://cloud.ouraring.com/oauth/applications (self-serve; > 10 users needs Oura's review). The portal
     has NO webhook or verification-token field: subscriptions are created by the backend itself (`ouraMaintain()`,
     hourly, only when the secret `OURA_MAINTAIN_SUBSCRIPTIONS=1` is set). The verification token lives in ONE place —
     the Supabase secret `OURA_WEBHOOK_VERIFICATION_TOKEN` (any random string you invent, e.g. 32 base64 chars): the
     backend sends it to Oura when it creates a subscription and Oura echoes it on the GET challenge. No fallback to
     the client secret — unset means the webhook path stays closed (fail closed).
   - **WHOOP** — https://developer.whoop.com (self-serve). In the app's dashboard set the webhook URL above and
     enable events. The signature key is the client secret — no extra secret.
   - **Polar** — https://admin.polaraccesslink.com (self-serve). Client id + secret → Supabase secrets. The
     application webhook is registered BY THE BACKEND (Polar shows its signing key once, so it never passes through a
     screen): from the SQL editor, POST `{"probe":"polar-register-webhook"}` to `wearable-reconcile` with the
     `x-report-secret` header (see "Live checks"); the key is stored AES-GCM-encrypted (token key ring, AAD
     `app|polar|webhook|<version>`) in the app-level `wearable_webhook_subscriptions` row and `parseWebhook` reads it
     from there (`POLAR_WEBHOOK_SECRET`, if set, still wins). `{"probe":"polar-credentials"}` answers whether Polar
     accepts the stored client credentials (status + webhook list, never a secret). Deliveries are parsed only with
     `POLAR_WEBHOOKS_ENABLED=1` (v3-webhook / v4-data compatibility flag).
   - **Withings** — https://developer.withings.com/dashboard/ (Public Cloud; self-serve). Add BOTH URLs above to the
     app's Callback URIs (the webhook URL must be listed or `notify subscribe` is refused). No webhook secret
     (notifications are unsigned; the backend only treats them as a "pull now" hint).
   - **Suunto** — https://apizone.suunto.com (sign up, subscribe to "Developer API", file the partner form, sign the
     API agreement; 2–4 weeks). In the profile's OAuth section: app, redirect URI, a client secret YOU choose. Webhook:
     notification URL + a notification secret you choose. Secrets: `SUUNTO_SUBSCRIPTION_KEY` (Profile → Subscriptions),
     `SUUNTO_WEBHOOK_SECRET`. Field names are unverified (no official spec was reachable) — the first live payloads in
     `wearable_raw_events` are the truth.
   - **Garmin** — adapter rebuilt 2026-11-06 (see "Garmin, Fitbit and Strava (2026-11-06)" below for every step):
     https://developerportal.garmin.com → your app → redirect URI above; Endpoint Configuration → **PUSH** for each
     summary type we map, plus Deregistration and User Permission Change, all to
     `…/wearable-vendor-webhook/garmin?token=<GARMIN_WEBHOOK_TOKEN>`. Secrets `GARMIN_CLIENT_ID`, `GARMIN_CLIENT_SECRET`,
     `GARMIN_WEBHOOK_TOKEN`; `GARMIN_PULL_ENABLED=1` only on the Enterprise tier (Ping/Pull).
   - **Google Health (Fitbit)** — the only route left (the legacy Fitbit Web API was switched off on 2026-11-02).
     Restricted scopes: OAuth verification + an annual CASA assessment before real members can consent (below).
     When pursued: Cloud project, OAuth client (Web), the `googlehealth.*.readonly` scopes, a project-level subscriber
     pointing at the webhook URL with `endpointAuthorization.secret = "Bearer <GOOGLE_WEBHOOK_SECRET>"`.
2. Supabase → Project Settings → Edge Functions → Secrets: `<VENDOR>_CLIENT_ID`, `<VENDOR>_CLIENT_SECRET`
   (uppercase vendor key, e.g. `OURA_CLIENT_ID`), the per-vendor extras above, and ONCE `WEARABLE_TOKEN_KEY` = 32
   random bytes base64 (`openssl rand -base64 32`). Never paste any of these into chat or a repo.
3. Flip the vendor on: `update wearable_vendors set status = 'available' where key = '<vendor>';` — the app shows
   its Connect button on the next open (after Privacy Notice v10 is approved). `paused` hides it again.
4. Privacy Notice **v10** — approved 2026-09-14 (`supabase/migrations/20260914_privacy_policy_v10_amend_and_approve.sql`:
   amended with the delete-on-unlink choice, the member-readable log, the 30-day raw retention and the no-AI rule,
   then v9 superseded). `WearableDisclosure.vendorNoticeVersion = 10` is satisfied: a vendor's Connect button appears
   the moment its row is `available`. Members re-accept the notice on their next launch, as with every version.
5. Test with your own account: Devices → Connect → the vendor's consent page → back in the app → "Connected · since";
   `wearable_vendor_accounts` has the row, `wearable_sync_queue` a backfill job, and within 10 minutes
   `wearable_daily` rows under the vendor's source id (1000018 Oura, 1000042 WHOOP, 1000003 Polar, 1000002 Garmin,
   1000008 Withings, 1000050 Suunto, 1000011 Google).

**Not verifiable from the build environment:** the sandbox proxy blocks the vendor domains, so the adapters are
written from the specs and marked `VERIFY:` where a field name or endpoint could not be read on an official page.
The first real connection per vendor is the test; the raw payloads land verbatim in `wearable_raw_events`
(`vendor_webhook` / `vendor_api`) so a wrong field name is fixed from the stored payload, not guessed.

### Platform v2 (2026-09-14) — what changed and the secret names that are authoritative

Two additive migrations are applied on CM OS and kept in `supabase/migrations/`:
`20260914_wearable_catalogue_v2.sql` (catalogue reconciliation: `*Alt` aliases → canonical ids, glucose stored in mg/dL,
ids 1000114–1000118 and 1000130–1000138 reserved) and `20260914_wearables_platform_v2.sql` (nine account states, refresh
lease + `token_version` CAS, hashed OAuth state + encrypted PKCE verifier, queue lease/dedupe/retry scheduling,
webhook receipts, audit log, retention purge, `wearable_reconcile` cron 03:25 UTC, `wearable-retention-purge` 03:40 UTC).
A **sixth function**, `wearable-reconcile` (verify_jwt off, `x-report-secret`), re-pulls every live account nightly
(adapter window, default 3 d; Sundays 14 d) and re-encrypts tokens after a key rotation.
`deno test` (`.github/workflows/edge-functions.yml`) type-checks every function and runs the platform tests on each push.

| Secret (Supabase → Edge Functions → Secrets) | Used by | Notes |
|---|---|---|
| `WEARABLE_TOKEN_KEY` | all | key **version 1**: 32 random bytes base64 (`openssl rand -base64 32`). |
| `WEARABLE_TOKEN_KEY_V2`, `_V3`… + `WEARABLE_TOKEN_KEY_VERSION` | all | rotation: add the new key, set the version, the nightly reconcile re-encrypts every live account (v1 blobs still decrypt). |
| `<VENDOR>_CLIENT_ID` / `<VENDOR>_CLIENT_SECRET` | start · callback · sync | uppercase vendor key: `OURA_`, `WHOOP_`, `POLAR_`, `GARMIN_`, `WITHINGS_`, `SUUNTO_`, `GOOGLE_`. |
| `OURA_WEBHOOK_VERIFICATION_TOKEN` | webhook | the verification token you chose in the Oura portal (Phase 2 removes the client-secret fallback). |
| `OURA_MAINTAIN_SUBSCRIPTIONS=1` | sync (cron) | opt-in flag for the hourly subscription create/renew call (off until Phase 2 pins the operation). |
| `POLAR_WEBHOOK_SECRET` | webhook | optional override; normally the key lives encrypted in the app-level `wearable_webhook_subscriptions` row written by the backend registration. |
| `POLAR_WEBHOOKS_ENABLED=1` | webhook | opt-in: Polar webhooks are parsed only once v3-webhook / v4-data compatibility is confirmed in writing (the adapter runs on Dynamic API v4 since 2026-09-14). |
| `SUUNTO_SUBSCRIPTION_KEY`, `SUUNTO_WEBHOOK_SECRET` | sync · webhook | from the Suunto partner profile. |
| `GOOGLE_WEBHOOK_SECRET`, `GOOGLE_CLOUD_PROJECT_NUMBER` | webhook · callback | subscriber registration (Phase 2). |
| `WITHINGS_REGION=EU` | callback · sync | region pin. |
| `REPORT_SECRET` | sync · reconcile | already set: the Vault `report_secret` pg_cron sends as `x-report-secret`. |
| `WEARABLE_RAW_RETENTION_DAYS` (optional) | all | default: raw vendor events are kept; set to purge `wearable_raw_events` after N days. |
| `WEARABLE_DISCONNECT_RAW_RETENTION_DAYS` (optional, default 30) | disconnect | a disconnected vendor's raw events are purged after this window; **erase** purges on the next nightly run. |
| `WEARABLE_LOG_SALT` (optional) | all | salt for the hashed patient ids in log lines. |

Operator notes: the kill switch is `update wearable_vendors set status = 'paused' where key = '<vendor>'` — every outbound
call stops, tokens stay, members see "paused"; `available` resumes. `select * from wearable_platform_health` (service role)
shows queue depth per status, accounts per state and webhooks in the last 24 h. Members can read their own rows of
`wearable_vendor_accounts` (status columns only — the token columns are not granted) and `wearable_audit_log`.
The member's "Disconnect and delete synced data" calls `wearable-vendor-disconnect` with `erase: true` →
`wearable_erase_vendor_data()` deletes that vendor's `wearable_daily` / `wearable_epoch` rows and marks its raw events
for the nightly purge; nothing from another source is touched.

### Audit, the readiness probe and device requests (2026-11-06)

**State on CM OS, 2026-11-06** (read-only audit): `available` = Oura, WHOOP, Polar, Withings; `planned` = Garmin,
Google (Fitbit), Suunto. Exactly **one** direct account exists — Withings (connected 2026-09-26, nightly reconcile
`pull.ok` every night, last rows 2026-10-17 because no new measurement has been taken since; the Withings
notifications stopped the same day). Oura, WHOOP and Polar have **never** been connected by anyone: their first real
connection is still the test. The 60 Oura rows in `wearable_daily` are the demo seed (`normalization_version =
demo-seed-celine`), not a connection. Polar's credentials answered 200 on 2026-11-06 with the app webhook registered
at our URL. On 2026-09-14, when the webhook URLs were entered in the portals, WHOOP (20:20 UTC) and Oura (20:39 UTC)
each had one delivery rejected with `signature mismatch` — either a portal test ping signed differently or a client
secret in Supabase that differs from the portal's. Settle it with the first real connection (a wrong secret also
breaks the token exchange, which the callback logs as `oauth.callback_failed`).

**Readiness probe** (`{"probe":"vendor-readiness"}` → `wearable-reconcile`, `x-report-secret`; deployed with the next
`main` push that touches `_shared/wearables/`). Per vendor: which Edge Function secrets are SET (names → true/false,
never a value), whether the OAuth authorisation URL builds with them (origin, path, parameter names, exact
redirect), the status row, live accounts and the last successful sync. Calls no vendor, writes nothing. From the SQL
editor:

```sql
select net.http_post(
  url := 'https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-reconcile',
  headers := jsonb_build_object('Content-Type','application/json','x-report-secret',
             (select decrypted_secret from vault.decrypted_secrets where name = 'report_secret')),
  body := '{"probe":"vendor-readiness"}'::jsonb);
-- then: select content from net._http_response order by id desc limit 1;
```

**Strava — assessed and not added.** An adapter was written and tested on 2026-11-06, then withdrawn the same day:
Strava's API Policy (effective 2026-06-01, https://www.strava.com/legal/api_policy) forbids what every connector here
does — storing Strava data beyond a transient 7-day cache (§5.5, §6.2), combining it with other data or deriving
insights from it (§5.4), disclosing it to anyone but the athlete "even if a user … consents" (§5.10, §2.3), and any AI
use (§5.3). New apps also need a paid Strava subscription and start at 1 athlete (10 self-serve, more after a review
with no timeline). A member's Strava workouts still reach us the compliant way: the Strava iPhone app writes them to
Apple Health, and most of them were recorded on a Garmin, Polar, Suunto, COROS or Apple Watch in the first place.
`ai-policy.ts` keeps `strava` in the AI-forbidden set as a guard. Revisit only with a written exception from Strava.

**"Don't see your device?"** (Devices screen, under the vendor cards): a member types a brand and model; it is sent
on the product feedback channel as `Device request: <text>` (`member-feedback` → `beta_feedback` + the admin alert
mail). Count the demand with `select message, created_at from beta_feedback where message like 'Device request:%'`.
A `wearable_vendors` row the app has no copy for still gets a card (`WearableVendor.catalogue(rows:)`), so a brand
added later server-side (adapter + row) needs no app release.

### Garmin, Fitbit and Strava (2026-11-06)

**Garmin — what the app and the server need now** (adapter `_shared/wearables/garmin.ts`, tests `tests/garmin_test.ts`):

| Item | Value |
|---|---|
| OAuth | 2.0 + PKCE S256 (required). Authorize `https://connect.garmin.com/oauth2Confirm`; token + refresh `POST https://connectapi.garmin.com/di-oauth2-service/oauth/token` (Garmin's public OAuth2 PKCE spec, June 2025). A new refresh token on every refresh; we refresh 600 s before `expires_in`. |
| Redirect URI to register | `https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-oauth-callback` |
| Webhook URL to register (every summary type + Deregistration + User Permission Change) | `https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-webhook/garmin?token=<GARMIN_WEBHOOK_TOKEN>` |
| Delivery | **PUSH** (data inline). Starter tier = push only, no backfill. Ping/Pull + backfill = Enterprise: set `GARMIN_PULL_ENABLED=1` only then. A PING callback URL is never fetched; only its upload window is used, and only from `https://apis.garmin.com/wellness-api/rest/…`. |
| Webhook security | Garmin documents no signature. Our own secret in the URL (`GARMIN_WEBHOOK_TOKEN`, constant-time compare, fail closed); the `garmin-client-id` header is never trusted; pushes land only on a Garmin user id we already hold; every write is an idempotent upsert. |
| Scopes | Fixed by Garmin. The member chooses permissions on the consent page (HEALTH_EXPORT, ACTIVITY_EXPORT, MCT_EXPORT); we read them after connect (`/user/permissions`, kept in the account `meta`). |
| Disconnect | `DELETE /wellness-api/rest/user/registration` — Garmin says it MUST be called when the app offers its own disconnect; `wearable-vendor-disconnect` does. A deregistration push revokes the account. |
| Secrets | `GARMIN_CLIENT_ID`, `GARMIN_CLIENT_SECRET`, `GARMIN_WEBHOOK_TOKEN` (32 random bytes, base64url — you invent it; it goes in the portal URL and in Supabase). Optional `GARMIN_PULL_ENABLED=1`. |
| Summary types to enable (PUSH) | dailies, sleeps, hrv, stressDetails, bodyComps, userMetrics, skinTemp, bloodPressures, activities, mct (Women's Health). Leave epochs, pulseOx and allDayRespiration off — not mapped. |

Catalogue mapping (`data_source_id` 1000002; field names **VERIFY** against the Health API spec PDF — every push body is
stored verbatim in `wearable_raw_events` first, so a wrong name is fixed from the stored payload):
dailies → Steps 1000, CoveredDistance 1001, FloorsClimbed 1002, ActiveBurnedCalories 1011, BurnedCalories 1010 (active +
BMR, only when both are sent), ActivityDuration 1100, ActivityMid/High 1102/1103 (minutes, as the Oura adapter), resting
HR 3001, average HR 3000, AverageStress 6010 (negative "no data" sentinels dropped), High/Medium/Low stress minutes
6011–6013 · sleeps → 2300 asleep, 2301 in bed (asleep + awake), 2302 REM, 2303 deep, 2305 light, 2306 awake, 2402
interruptions, 1000105 sleep score, 4002 / 3009 sleep means, 2400/2401 start/end, stage epochs 2002/2003/2005/2006 ·
stressDetails → BodyBattery 1000103 (day high, low in details) · bodyComps → 5020 kg, 5021, 5022, 5025, 5026 · skinTemp →
1000106 · bloodPressures → 3300/3301 (epoch + day) · userMetrics → VO2max 3030 · activities → workout epochs 1200 (type),
1011, 1001, 3000, 1003 (the activity title is never stored) · mct → MenstrualCycleDay 1000108.
**HRV (decision D4):** `lastNightAvg` / `hrvValues` are NOT written to an HRV id until the spec's definition is read
(RMSSD over the sleep window?) — flip `HRV_RMSSD_CONFIRMED` in `garmin.ts` (one line, its tests already cover both
states) and they go to RmssdSleep 3106 / RmssdSleepHighest 3107 / Rmssd 3100 epochs.

Owner steps, in order:
1. Developer portal: the redirect URI and the PUSH endpoints above; download the **Health API** and **Push/Ping
   notification** spec PDFs and the **Garmin Connect** brand tile, and put the PDFs in `docs/vendors/garmin/` (they are
   what turns every VERIFY above into a pinned field).
2. Secrets through the secure form (never chat): `GARMIN_CLIENT_ID`, `GARMIN_CLIENT_SECRET`, `GARMIN_WEBHOOK_TOKEN`.
3. Deploy (merge to `main`), run the readiness probe: `garmin.authorize.ok = true`, all three secrets `true`.
4. The first real connection. There is no private test lane: `wearable-oauth-start` only starts an `available` vendor
   and the app only shows Connect for one. So, at a quiet moment and with your go: `available` → connect your own
   Garmin → sync the watch → within minutes `wearable_raw_events` has `garmin / vendor_webhook` rows and
   `wearable_daily` rows under 1000002. Anything wrong → `paused` (hides it, keeps the tokens) and fix from the stored
   push. Rows there → it stays `available`.
5. Before members: the official "Garmin Connect™" tile on the Devices card and "Garmin [device model]" attribution next
   to every view of Garmin data (Garmin API Brand Guidelines v6.30.2025) — the app and the dashboard don't do this yet.
   Read the developer agreement you accepted: the 2026 China variant adds an AI-transparency clause; the International
   one (2023) does not. Starter apps are capped in users and show "unverified" until Garmin reviews them.

**Fitbit — the realistic route.** The legacy Fitbit Web API is gone (switched off 2026-11-02; no new apps). Google Fit
REST is deprecated. The only route is the **Google Health API** (`health.googleapis.com/v4`, launched 2026-03-24), which
`_shared/wearables/google.ts` already implements (OAuth web flow, signed webhooks with Google's ECDSA keyset, RMSSD/SDNN
mapping). Its scopes are **restricted**: (1) Google OAuth app verification (Trust & Safety), (2) a **CASA** security
assessment by an authorised lab, renewed **yearly** — 2–3 weeks (tier 2) or 4–6 weeks (tier 3), **USD 500–4,500** paid to
the assessor (an existing SOC 2 / ISO 27001 helps but still goes through a CASA lab), plus an in-app disclosure. Before
that the project runs in Testing mode: ≤ 100 named test users and refresh tokens that **expire after 7 days** (members
would re-link weekly) — fine for your own test, not for members. Members must also link their Google account in the
Google Health app first. Get the Google Health API data policy read against our use (no use in a product that may
qualify as a medical device; PHI only with Google's written approval) before paying for CASA. Meanwhile Fitbit
users' sleep (with stages), steps and workouts already arrive through Apple Health; HRV does not.

### Apple Health relay — FunctionAlps sleep rule (own rule, 2026-09-14) and decision D7

**Sleep rule** (`SleepAssembler`, `FunctionAlps/Sources/Core/Health/WearableCatalog.swift` — FunctionAlps' own rule, not a
vendor convention): (1) a gap of more than **3 h** between two HealthKit sleep samples starts a new session; (2) a session
counts as the **main sleep only when it holds ≥ 3 h asleep** (or one explicit in-bed sample ≥ 3 h) — shorter sessions are
naps and are dropped; (3) **one main sleep per day: the longest session wins** (the night, not the siesta); (4) the day a
night belongs to is **the local day the sleep ended**. Durations travel in seconds on the catalogue ids 2300–2307, 2402, 2200.

**D7 (wearables strategy):** the relay keeps its **rolling-window resync (30 d backfill on the first sync, 3 d on every
later sync) as a documented deviation** — HealthKit deletions and edits older than 3 days are not picked up, and a day is
re-upserted whole. `dailyTypes` now also reads **flights climbed** (1002 `FloorsClimbed`, day sum), **body fat %**
(5025 `FatRatio`, day mean ×100, rounded) and **body temperature** (5040 `BodyTemperature`, °C, day mean); blood glucose is
parked (CGM later). Every workout epoch and every assembled night carries **`source_record_id` = the HealthKit object UUID
and `source_device_id` = the writing app's bundle id** (a night uses its FIRST sample's); `wearable-ingest` writes them with
`normalization_version` and a null `source_connection_id`. Anchored queries (`HKAnchoredObjectQuery`), deletions and an
outbox come in a later phase.

### Vendor logos on the Devices screen (2026-09-14)
Six brand marks are bundled as template SVG image sets (`vendor-oura`, `vendor-whoop`, `vendor-polar`, `vendor-suunto`,
`vendor-garmin`, `vendor-google`) and tinted in the brand colour at runtime; sources and licences in
`THIRD_PARTY_NOTICES.md`. Withings has no open-licence mark, so its card draws the wordmark. To replace any mark with
the official press-kit logo: drop the SVG/PNG into the matching `vendor-<key>.imageset`, update its `Contents.json`
(`filename`; remove `template-rendering-intent` for a full-colour logo) — for Withings, create `vendor-withings.imageset`.

### Public legal pages (2026-09-14)
`legal-page` (verify_jwt off) serves the CURRENT approved documents from `consent_definitions` as HTML, in EN and FR.
**Public address (give this one to vendor portals — WHOOP, Oura, Withings… — and App Store Connect):**
`https://app.functionalps.ch/privacy` (also `/terms`, `/legal-notice`, `/health-data`, `/ai`; `?lang=fr`).
It is served by `api/legal.js` in FunctionAlps-APP (Vercel), which proxies
`https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/legal-page/<slug>`. Do NOT hand out the supabase.co URL:
the Supabase gateway serves HTML from the shared functions domain as `text/plain` with a sandbox CSP
(anti-phishing), so a browser shows raw source there. Approving a new notice version changes the pages with no
deploy (5-minute cache).

### Shipping a new Privacy Notice / Terms version (2026-09-15)
Nothing in the app is hard-coded to a version — the whole loop is data:

1. Add the row (a migration in `supabase/migrations/`, cloned from the current one, which is then
   stamped `superseded_at`). Both locales, `review_status='approved'`, a bumped `version`.
2. `member_pending_consents` only ever reports the CURRENT row, and computes `accepted` with
   `c.version = d.version`. So a member holding v7 comes back `accepted = false` the moment v8 lands.
3. `MemberGateView.resolve()` re-reads the bundle on **every launch** and blocks while any
   `required && !accepted` remains. No push, no flag, no app release needed.
4. Since 2026-09-15 the RPC also returns `accepted_version` (the member's last standing grant for that
   key, whatever its version). The gate uses it to tell a first sitting from a re-acceptance: a returning
   member gets "We have updated our terms" plus an `Updated · v8` chip on each row that moved, instead of
   "Before you start".

⚠ **Only `doc_kind='consent'` rows reopen the gate** — today `terms_of_use` and `health_data_processing`.
`privacy_policy`, `ai_analysis` and `legal_notice` are `doc_kind='notice'`: shown on the screen, never
ticked, so bumping one of those ALONE asks nobody for anything. That is why v11/v8 shipped together —
the Terms bump is what brings members back to the screen where the new notice is displayed.

⚠ Re-creating `member_pending_consents` (the return type changed, so `create or replace` refuses and it
must be dropped) silently re-grants EXECUTE to **PUBLIC** and to **anon** — Postgres' own default plus
Supabase's default privileges on `public`. The original had neither. The migration revokes both; check
`proacl` reads `{postgres,authenticated,service_role}` after any future change to it.

### Where the in-app messages and feedback alerts land (2026-09-15)
Both channels are complete on both sides; what decides the inbox is two edge-function secrets on CM OS
(Project Settings → Edge Functions → Secrets), not code:

| Channel | App entry | Edge function | Recipient | Secret |
|---|---|---|---|---|
| Product feedback | Profile → Your feedback | `member-feedback` | the team | `ADMIN_ALERT_EMAIL` (code default `thomas@functionalps.ch`) |
| "Ask your nutritionist" | Profile → Messages | none from the app (2026-11-05): CLINICAL's cron `member-message-alerts` reads `patient_messages` every 5 minutes and emails the member's primary coach, else the owner | the coach / Thomas | CLINICAL env (`CONVERSATION_OWNER_USER_ID`, `CLINIC_NOTIFY_EMAIL`) |

The clinician alert is **content-free by design** (no body, no name — the link is the payload); the
feedback mail does carry the member's words, their email and their tier. A patient message also gets a
15-minute `pg_cron` sweep as a safety net, so a failed fire-and-forget invoke is retried; feedback mail
is best-effort with no retry, but the row is already saved in `beta_feedback` either way.

SMTP itself is live — `send-review-digest` returned `{"email":"sent"}` on 2026-09-15 03:35 through the
same `_shared/email.ts` both of these use. `SMTP_PORT` must stay **465**.

## Notifications (added 2026-09-04)

**Phone:** local reminders are planned on the device (`NotificationPlanner` → `LocalNotifications`), no server
involved: morning / midday / evening check-in at the member's times, lunch (13:30) and dinner (20:15) "not logged",
"how do you feel?" 2½ h after each meal, the weekly summary (Sunday 18:00), Apple Health silent for 3 days. All
respect the member's quiet hours and are dropped for anything already done. Preferences live in
`patient_notification_preferences` (Settings → Notifications).

**Server push (APNs):** `push-send` (deployed, verify_jwt false, `x-report-secret`) sends content-free pushes —
the body never carries health data, the link is the payload. DB triggers (migration `20260904_notifications_push.sql`,
applied) call it through `notify_member_push()` + pg_net for: a practitioner message, an approved report, a care-plan
change, a meal that needs input. The APNs token is uploaded by the app to the same preferences row.

**Owner steps, once:**
1. **Push Notifications capability on the App ID** (same place as HealthKit: https://developer.apple.com/account/resources/identifiers/list
   → `com.functionalps.patient` → Capabilities → Push Notifications → Save). ⚠ Do this BEFORE the next
   `release/testflight` push: the app now carries the `aps-environment` entitlement and the archive is refused until
   the profile includes it (match regenerates the profile, it cannot add the capability).
2. **APNs key:** https://developer.apple.com/account/resources/authkeys/list → `+` → name "FunctionAlps APNs",
   tick Apple Push Notifications service (APNs) → Continue → Register → **Download the .p8 once** (it cannot be
   downloaded again) and note the Key ID. Supabase → Edge Functions → Secrets:
   `APNS_TEAM_ID` (Team ID), `APNS_KEY_ID`, `APNS_KEY_P8` (the .p8 file base64-encoded on one line:
   `base64 -i AuthKey_XXXX.p8 | tr -d '\n'`), `APNS_TOPIC` = `com.functionalps.patient`. Never paste the .p8 in chat.
3. Test: send yourself a message from the practitioner side → the phone shows "New message from your practitioner"
   within seconds; `patient_notifications` has the row.

## Consent gate refusals (2026-09-25)

Two members were refused at "Agree and continue" the same day, both on build 35, both shown *"check your connection"*:
a 403 (`record_consent` → `no member context`: a Google sign-in that was a second auth user for a mailbox whose password
account owns the record) and a 400 (X0018: no date of birth on file, and the age screen had been removed on 2026-09-18).
Neither was a version problem — builds 35 and 40 carry the same gate code. Three things changed:

1. **Migration `20260925_record_consent_terms_is_the_declaration.sql` — applied on CM OS 2026-09-25.** `record_consent`
   no longer refuses an unconfirmed member; a granted `terms_of_use` stamps `nb_patient_app_profiles.adult_confirmed_at`
   (`source = terms_declaration`, a row is created when missing). Also revokes anon EXECUTE on `record_consent_batch`.
   Rollback is in the file header.
2. **`patient-register` v57 — deployed 2026-09-25 from `supabase/functions/patient-register/index.ts`** (verify_jwt
   true, NOT in `NO_JWT`; `workflow_dispatch` with `target=patient-register` redeploys it). The existing-identity case
   answers 409 and records nothing; the dedup key is the verified session email. ⚠ The same file lives in the MEMBERS,
   CLINICAL and APP repos: copy this version there before anyone deploys from those, or the fix is overwritten.
3. **App (this branch):** the third rung re-checks ownership after registration, models the 409, shows *"This email
   already has an account"*, and the consent gate stops blaming the connection for a server refusal.

## Meal identification on OpenAI (2026-09-27)

**Why.** From 2026-09-26 ~09:00 UTC Infomaniak's vision model (`google/gemma-4-31B-it`) stopped answering inside
`analyze-meal`'s 9 s deadline: 5 of 10 photo meals ended `needs_input` or looping in the retry worker with
`IDENTIFY_FAILED: UPSTREAM_TIMEOUT`, and the few that succeeded took 5.5–6.7 s on the worker's last attempt. The iOS
client was not at fault (row, upload, attach and the `analyze-meal` call all landed). Owner decision: identify meals with
OpenAI.

**Source of truth moved here.** `analyze-meal` (live v92) and `retry-meal-analysis` (live v28) were imported verbatim
from the deployed CM OS bundles into `supabase/functions/`, their helpers under `supabase/functions/_shared/meals/`.
Both are `verify_jwt=false` and listed in `NO_JWT`; a change under `_shared/meals/` deploys the pair. ⚠ The same
functions still live in FunctionAlps-APP — a deploy from there overwrites this version and silently puts meals back on
Infomaniak. Copy `_shared/meals/meal-analysis.ts` across (or stop deploying them from APP) first.

**The switch is a secret, not a deploy.** `identifyMeal` reads `MEAL_AI_PROVIDER` once per cold start:

| Secret (Supabase → Edge Functions → Secrets) | Value |
|---|---|
| `MEAL_AI_PROVIDER` | `openai` (anything else, or unset = Infomaniak, unchanged) |
| `OPENAI_API_KEY` | the key; an OpenAI key on its own never moves meals |
| `OPENAI_MEAL_MODEL` | optional, default `gpt-5.4-mini` |

OpenAI path: one Chat Completions call with `response_format: json_object`, no temperature, 20 s deadline and one
hedge at 10 s (`ANALYZE_MEAL_TIMEOUT_MS` / `ANALYZE_MEAL_HEDGE_MS` still override). Provider selected without its key
→ both functions answer 500 naming the missing key, and queued rows wait untouched for the worker.
`preprocess-meal`, `transcribe-audio`, reports and tips are not affected — they stay on Infomaniak.

**Go-live order — do not reorder.**
1. Sign OpenAI's DPA (with the SCCs the Privacy Notice §12 already promises for non-CH/EEA providers).
2. Apply `supabase/migrations/20260927_consents_openai_meal_identification.sql` — **applied 2026-09-27** (privacy_policy v12, ai_analysis v8, health_data_processing v7).
   It bumps `health_data_processing` (a `doc_kind='consent'` row), so every member re-accepts on next launch and sees
   the new `privacy_policy` / `ai_analysis` beside it. Until then all three documents promise data is *not* sent to OpenAI.
3. Merge to `main` (deploys the pair — still Infomaniak), then set `OPENAI_API_KEY` and `MEAL_AI_PROVIDER=openai`.
4. Ship the build carrying the new in-app wording (`privacy.collect.ai.body2`, `privacy.banner.body2`, `login.swiss2`).
5. Rows stuck in `needs_input` from the outage do not retry by themselves: the member taps "try the photo again", or
   reset them to `queued` with `analysis_attempts = 0`.
Rollback: unset `MEAL_AI_PROVIDER` (next cold start is back on Infomaniak).

## TestFlight distribution to members (2026-09-28)

Members are **external** testers in the group **BetaTesters**. Until 2026-09-28 the `beta` lane uploaded and stopped:
a build reached only the internal team (automatic distribution), and members stayed on build 35 while 36–43 shipped.
The lane waits for processing and, on a run marked `[external]` (see the owner rule at the top), hands the build to
BetaTesters (`distribute_external`, `groups`, override with `FA_TESTFLIGHT_GROUP`), notifying testers; every other run
reaches the internal team only (since 2026-10-05). Apple may hold a build for Beta App Review first.

Old builds are **not** expired by the lane (a build held in review would leave members nothing to open). Once a build
is live in BetaTesters: App Store Connect → TestFlight → iOS Builds → each older build → Expire Build. An expired build
no longer opens, so testers move to the current one.
