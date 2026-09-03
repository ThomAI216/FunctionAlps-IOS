# iOS tooling — how the coding agent, Xcode and Apple's pipeline fit together

Status: written 2026-09-02 from the four references the owner supplied, plus the
repo's own constraints. Where a fact could not be verified from the source
(network egress blocked some docs pages) it is marked **[verify on Mac]**.

Sources read:
- Anthropic, "Apple's Xcode now supports the Claude Agent SDK" (via search summary; anthropic.com was blocked from this sandbox)
- keskinonur/claude-code-ios-dev-guide (README read in full)
- getsentry/XcodeBuildMCP (README read; tool docs page blocked)
- fastlane/fastlane + fastlane/docs (`app-store-connect-api.md`, `codesigning/getting-started.md`, `getting-started/ios/beta-deployment.md`)

---

## 0. You develop on Windows — what that means (added 2026-09-02)

Xcode, the iOS simulator, code signing and archiving run **only on macOS**. Claude
in Xcode 26.3 and XcodeBuildMCP are therefore not available to you. The workflow
that works from a Windows desktop:

| Step | Where | How |
|---|---|---|
| Edit Swift, docs, tests | Windows | VS Code / Claude Code on this repo (the repo is plain files) |
| Compile + unit tests | **GitHub Actions macOS runner** | `.github/workflows/ios.yml` job `build-and-test` runs on every push (XcodeGen → xcodebuild build → xcodebuild test on an iPhone simulator; logs uploaded as artifacts). Claude can trigger runs and read the logs through the GitHub API and fix compile errors in a loop. |
| See the UI | iPhone via TestFlight | no interactive simulator without a Mac. Optional: rent a cloud Mac by the hour (MacinCloud, MacStadium, AWS EC2 Mac, Scaleway) for SwiftUI Previews / screenshots when a visual pass is needed. |
| Sign + upload | GitHub Actions job `testflight` | manual trigger (`workflow_dispatch` with `testflight=true`); fastlane `match` keeps certificates in a private git repo, the App Store Connect API key authenticates. See DEPLOYMENT.md §5. |
| Install on your iPhone | TestFlight app | internal group, no review |

Cost: macOS minutes count 10× on GitHub's free tier for private repos (2,000 → ~200
macOS minutes/month, roughly 15–20 build+test runs). Docs-only pushes are skipped
so writing never spends them. Alternatives with a bigger free tier:
Codemagic (500 macOS min/month), or Xcode Cloud (25 h/month, but its first setup
needs Xcode once).

Optional on Windows: the official Swift toolchain for Windows (swift.org) can
type-check `Core/` (Foundation-only) but not SwiftUI/UIKit — not worth setting up now.

## 1. Division of labour (the rule that avoids wasted effort)

| Who | Owns |
|---|---|
| **Coding agent (Claude Code / Claude in Xcode)** | Swift sources, SwiftUI views, models, networking, tests, navigation, refactors, docs, build scripts |
| **Xcode + Apple CLI (`xcodebuild`, `xcrun simctl`, `altool`/Transporter)** | compilation, SDKs, simulator, signing, provisioning, archiving, device builds |
| **App Store Connect (web + API)** | app record, TestFlight groups/testers, build processing, metadata |
| **fastlane** (later) | scripting the archive → upload → TestFlight lane once it has been done by hand at least once |

The sandbox this session ran in is **Linux with no Xcode**. Everything under
`ios/` was authored to compile under Swift 6 / iOS 17; the first `xcodebuild`
happens on the GitHub macOS runner (§0), not on a Mac you own.

## 2. Three ways to drive Xcode with Claude — pick per task

### 2a. Claude inside Xcode 26.3 (Claude Agent SDK integration)
- Xcode 26.3 ships a native integration of the **Claude Agent SDK** (the same harness that powers Claude Code): plan, edit files, run builds and tests, read build errors, iterate. It can **capture Xcode Previews** to see the UI it is building.
- It is built on **MCP**, so Xcode's capabilities are exposed as tools that any compatible agent can use (Claude, Codex).
- Sign-in uses your Claude account **[verify on Mac: Xcode → Settings → Intelligence → add Claude]**.
- Best for: UI iteration with Previews, fixing compiler errors in place, anything where seeing the running UI matters.

### 2b. Claude Code CLI + XcodeBuildMCP (terminal-first, scriptable)
- XcodeBuildMCP = MCP server **and** CLI for iOS/macOS projects. Requirements: **macOS 14.5+, Xcode 16+, Node 18+** (npm) or Homebrew.
- Install (either):
  ```bash
  brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp
  # or
  npm install -g xcodebuildmcp@latest
  ```
- Project config lives in `.mcp.json` (committed, no secrets):
  ```json
  {
    "mcpServers": {
      "XcodeBuildMCP": {
        "command": "npx",
        "args": ["-y", "xcodebuildmcp@latest"],
        "env": {
          "INCREMENTAL_BUILDS_ENABLED": "true",
          "XCODEBUILDMCP_SENTRY_DISABLED": "true",
          "XCODEBUILDMCP_DYNAMIC_TOOLS": "true",
          "XCODEBUILDMCP_ENABLED_WORKFLOWS": "simulator,device,project-discovery,swift-package"
        }
      }
    }
  }
  ```
  or one-liner: `claude mcp add --transport stdio XcodeBuildMCP -- npx -y xcodebuildmcp@latest`
- Tool families (names are the ones documented by the iOS guide; run the server's tool listing on the Mac to confirm the exact current names — they changed between v1 and v2 **[verify on Mac]**):
  - discovery: `discover_projects`, `list_schemes`
  - simulator: `list_simulators`, `boot_simulator`, `build_sim_name_proj`, `build_run_sim…`, `install_app`, `launch_app`, `screenshot`, `capture_logs`
  - device: `build_device_proj` (+ install/launch on device — **requires signing configured in Xcode first**)
  - test: `test_sim_name_proj`, `swift_package_test`
  - swift package: `swift_package_build`, `swift_package_test`
  - UI automation via AXe (tap/swipe/type/describe_ui) — useful for smoke checks, not for unit tests
- Notes from the README: it asks `xcodebuild` to **skip macro validation** (avoids Swift-macro build errors); dynamic tool loading keeps the tool list small.
- Best for: headless build/test loops, log capture, scripted smoke runs, CI-like discipline from the terminal.

### 2c. Plain `xcodebuild` / `xcrun simctl` (always available fallback)
```bash
cd FunctionAlps
xcodegen generate                                   # project.yml → FunctionAlps.xcodeproj
xcodebuild -project FunctionAlps.xcodeproj -scheme FunctionAlps \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project FunctionAlps.xcodeproj -scheme FunctionAlps \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
xcrun simctl list devices booted
```

## 3. Project generation: XcodeGen (decision)

We do **not** hand-write `project.pbxproj`. The project is described in
`FunctionAlps/project.yml` and generated with **XcodeGen** (`brew install xcodegen`).
Reasons: pbxproj merges are hostile to agents; the guide's permission set already
whitelists `xcodegen`; the spec is reviewable in a diff. The generated
`*.xcodeproj` is git-ignored. (Tuist/SPM-app were considered; XcodeGen is the
smallest tool that gives us a real `.xcodeproj` with signing settings.)

## 4. Conventions the guide recommends (adopted)

- iOS 17 minimum, Swift 6 strict concurrency, SwiftUI only, `@Observable` view models, `NavigationStack` with typed routes, typed `AppError`, Swift Testing (`@Test`, `#expect`).
- Extract views above ~100 lines; no force unwraps without a comment; no UITests during scaffolding.
- `CLAUDE.md` (project context) + `.claude/settings.json` with the XcodeBuildMCP allowlist and **deny** rules for `.env*`, `*.p8`, `*.p12`, `*.mobileprovision`, `Secrets.xcconfig`.
- Hooks (optional, later): SessionStart banner, PostToolUse SwiftLint on edited `.swift` files, PreToolUse guard on protected files.

## 5. Credentials and secrets — non-negotiable

- **Never** commit: `AuthKey_*.p8`, `*.p12`, `*.mobileprovision`, `*.cer`, `Secrets.xcconfig`, `.env*`, `fastlane/*.json` API-key files. `.gitignore` enforces this.
- The App Store Connect API key (`.p8`) lives in the Mac's keychain / `~/.private/` or a CI secret store; fastlane reads it via `app_store_connect_api_key(key_id:, issuer_id:, key_filepath:)` or `api_key_path:`.
- **No Supabase service-role key, no `SOVEREIGN_KEK_HEX`, no Infomaniak key in the app.** The iOS app only ever holds the **publishable/anon** key + the user's own session JWT (in Keychain).
- The only per-environment values in the app are `API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `ENVIRONMENT_NAME` — injected via `Config/*.xcconfig` (Development/Staging/Production). `Config/Secrets.xcconfig` is git-ignored and optional.

## 6. First build — checklist (CI, no Mac)

1. Push to any branch → the `iOS` workflow runs `build-and-test`. Read the annotations / the `xcodebuild-logs` artifact; fix Swift errors; push again until green.
2. In the browser (Windows is fine): App Store Connect → register the App ID + app record; Users and Access → create an API key; note Key ID, Issuer ID, download the `.p8` (DEPLOYMENT.md §1).
3. Create a **private** empty repo for certificates (e.g. `FunctionAlps-CERTS`) and a GitHub PAT that can read/write it.
4. Add repository secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (base64 of the `.p8`), `MATCH_GIT_URL`, `MATCH_GIT_BASIC_AUTHORIZATION` (base64 of `username:PAT`), `MATCH_PASSWORD` (a new passphrase).
5. Actions → iOS → Run workflow → `testflight = true`. First run creates the distribution certificate + profile via `match` and uploads build 1. Add yourself to the internal TestFlight group; install on the iPhone.
6. Sign in with a real member account; verify Home shows real rows.

## 6b. If you ever sit at a Mac — checklist

1. Xcode 26.3+ installed; `xcode-select --install`; `brew install xcodegen`.
2. `cd FunctionAlps && xcodegen generate && open FunctionAlps.xcodeproj`.
3. Xcode → Signing & Capabilities → Team = the individual Apple Developer account; Bundle ID `ch.functionalps.app` (see DEPLOYMENT.md §1 before changing it).
4. Fill `Config/Development.xcconfig` with the CM OS URL + publishable key (values are already in the Expo app's Vercel env; never the secret key).
5. Build + run on simulator; run tests (`⌘U`); fix anything the Linux authoring session could not compile-check.
6. Plug in an iPhone; Run; sign in with a real member account; verify Home shows real rows.
7. Only then: DEPLOYMENT.md (archive → App Store Connect → TestFlight).

## 7. Things we deliberately do NOT do now
- No fastlane until the manual archive/upload has succeeded once (PRD §38).
- No CI. No `match` (an individual account with one Mac does not need shared signing; Xcode automatic signing + a manual distribution certificate is enough for TestFlight).
- No Supabase Swift SDK (vendor lock at the feature layer; see `ARCHITECTURE.md`).
