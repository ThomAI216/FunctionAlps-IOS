# Deployment — from a Windows desktop to TestFlight (Milestone 1)

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

Run: Actions → **iOS** → Run workflow → branch → `testflight = true`, **or** push the commit you want to ship to the `release/testflight` branch (`git push origin main:release/testflight`) — that route is what the coding agent uses, since its GitHub integration cannot press Run workflow and its git proxy blocks tags. The lane increments the build number from the latest TestFlight build, archives Release, uploads, and skips waiting for processing (check App Store Connect 5–30 min later).

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
workflow already uses (https://supabase.com/dashboard/account/tokens). **Until that secret exists the five
functions are not deployed** — the first push after adding it (or a manual run) deploys them.
`supabase/functions/build-wearables.sh` still bundles each function into `bundle/<name>.ts` (gitignored) as a
syntax check / fallback for the MCP `deploy_edge_function` path; CI does not use the bundles.

**Owner steps, once per vendor (developer portal → secrets → flip the row):**
1. Register the app. Redirect URI (exact): `https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-oauth-callback`.
   Webhook URL where the vendor asks for one: `https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-webhook/<vendor>`
   (`<vendor>` = `oura` | `whoop` | `polar` | `garmin` | `withings` | `suunto` | `google`). Privacy policy URL: the
   published FunctionAlps notice. Per vendor:
   - **Oura** — https://cloud.ouraring.com/oauth/applications (self-serve; > 10 users needs Oura's review). Webhooks are
     created by the backend itself (`ouraMaintain()` on first connect + hourly renewal) — nothing to click. Optional
     secret `OURA_VERIFICATION_TOKEN` (any random string; defaults to the client secret).
   - **WHOOP** — https://developer.whoop.com (self-serve). In the app's dashboard set the webhook URL above and
     enable events. The signature key is the client secret — no extra secret.
   - **Polar** — https://admin.polaraccesslink.com (self-serve). Webhooks are one per application, registered by API,
     and the signing secret is shown ONCE. Run once from your machine (client id/secret from the portal):
     `curl -u "$POLAR_CLIENT_ID:$POLAR_CLIENT_SECRET" -H "Content-Type: application/json" -d '{"events":["EXERCISE","SLEEP","CONTINUOUS_HEART_RATE","ACTIVITY_SUMMARY","PHYSICAL_INFORMATION"],"url":"https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-webhook/polar"}' https://www.polaraccesslink.com/v3/webhooks`
     (the webhook function must already be deployed — Polar pings it and needs a 200) → store `data.signature_secret_key`
     as secret `POLAR_WEBHOOK_SECRET`.
   - **Withings** — https://developer.withings.com/dashboard/ (Public Cloud; self-serve). Add BOTH URLs above to the
     app's Callback URIs (the webhook URL must be listed or `notify subscribe` is refused). No webhook secret
     (notifications are unsigned; the backend only treats them as a "pull now" hint).
   - **Suunto** — https://apizone.suunto.com (sign up, subscribe to "Developer API", file the partner form, sign the
     API agreement; 2–4 weeks). In the profile's OAuth section: app, redirect URI, a client secret YOU choose. Webhook:
     notification URL + a notification secret you choose. Secrets: `SUUNTO_SUBSCRIPTION_KEY` (Profile → Subscriptions),
     `SUUNTO_WEBHOOK_SECRET`. Field names are unverified (no official spec was reachable) — the first live payloads in
     `wearable_raw_events` are the truth.
   - **Garmin** — programme currently closed to new applicants; keep `wearable_vendors.status = 'planned'`. If a key is
     granted: https://developerportal.garmin.com, endpoints tool → PUSH for every summary type to the webhook URL;
     secrets `GARMIN_CLIENT_ID/_SECRET`.
   - **Google Health** — deferred (`planned`): restricted-scope verification + CASA before real users can consent.
     When pursued: Cloud project, OAuth client (Web), the five `googlehealth.*.readonly` scopes, a project-level
     subscriber pointing at the webhook URL with `endpointAuthorization.secret = "Bearer <GOOGLE_WEBHOOK_SECRET>"`.
2. Supabase → Project Settings → Edge Functions → Secrets: `<VENDOR>_CLIENT_ID`, `<VENDOR>_CLIENT_SECRET`
   (uppercase vendor key, e.g. `OURA_CLIENT_ID`), the per-vendor extras above, and ONCE `WEARABLE_TOKEN_KEY` = 32
   random bytes base64 (`openssl rand -base64 32`). Never paste any of these into chat or a repo.
3. Flip the vendor on: `update wearable_vendors set status = 'available' where key = '<vendor>';` — the app shows
   its Connect button on the next open (after Privacy Notice v10 is approved). `paused` hides it again.
4. Privacy Notice **v10** (`supabase/migrations/20260904_privacy_policy_v10_vendor_accounts.sql`, applied as a
   draft; v9 still current) must be approved before any vendor button appears
   (`WearableDisclosure.vendorNoticeVersion = 10`). Approval SQL in the file header.
5. Test with your own account: Devices → Connect → the vendor's consent page → back in the app → "Connected · since";
   `wearable_vendor_accounts` has the row, `wearable_sync_queue` a backfill job, and within 10 minutes
   `wearable_daily` rows under the vendor's source id (1000018 Oura, 1000042 WHOOP, 1000003 Polar, 1000002 Garmin,
   1000008 Withings, 1000050 Suunto, 1000011 Google).

**Not verifiable from the build environment:** the sandbox proxy blocks the vendor domains, so the adapters are
written from the specs and marked `VERIFY:` where a field name or endpoint could not be read on an official page.
The first real connection per vendor is the test; the raw payloads land verbatim in `wearable_raw_events`
(`vendor_webhook` / `vendor_api`) so a wrong field name is fixed from the stored payload, not guessed.

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
