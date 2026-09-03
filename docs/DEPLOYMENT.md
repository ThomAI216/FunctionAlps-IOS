# Deployment — from a Windows desktop to TestFlight (Milestone 1)

You have no Mac, so "the manual path" (PRD §38) is the CI path: a GitHub macOS
runner archives, signs (fastlane `match`) and uploads. Everything you do by hand
happens in a browser. Sections §2–§4 describe the Mac-local equivalent for
reference only.

## 1. App Store Connect setup (one-time, web)
1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+ App ID**.
   - Bundle ID: `ch.functionalps.app` (explicit). **Decide once; never change after the ASC app record exists.**
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

Run: Actions → **iOS** → Run workflow → branch → `testflight = true`. The lane increments the build number from the latest TestFlight build, archives Release, uploads, and skips waiting for processing (check App Store Connect 5–30 min later).

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

## 6. App Store Connect API for the agent (later)
Apple's ASC API (JWT signed with the `.p8`) can read builds, manage TestFlight groups/testers, and beta metadata. If an MCP is added for it, it runs **locally** on the Mac, reads the key from a local path, and is reviewed before use (PRD §35–36). Nothing in this repo assumes it exists.

## 7. Rollback / hygiene
- A bad TestFlight build is simply expired in ASC; never reuse a build number.
- Keep `MARKETING_VERSION` stable across builds of the same beta; bump it when the feature set changes.
