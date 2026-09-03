# FunctionAlps — native iOS app

**Status:** foundation (Milestone 1, "v0.01") — authored 2026-09-02 in a Linux
sandbox without Xcode. First compile happens on a Mac; see `docs/TOOLING.md` §6.

This folder is the native SwiftUI replacement for the **FunctionAlps patient app**
(currently Expo / React Native in the `FunctionAlps-APP` repo). Everything else in
the FunctionAlps ecosystem (STUDIO, MEMBERS, WEBSITE, CLINICAL) stays web.

> **History.** Built 2026-09-02 on a branch of `FunctionAlps-STUDIO`
> (`claude/web-to-ios-native-6bwhlx`, commit 3755c5c) and moved here the same day
> so iOS builds, secrets and TestFlight live in one place. The Expo app it replaces
> stays in `FunctionAlps-APP` as the UX/behaviour reference.

## Layout
```
FunctionAlps-IOS/
├── README.md                this file
├── CLAUDE.md                agent context for iOS work
├── .mcp.json                XcodeBuildMCP config (no secrets)
├── .claude/settings.json    tool allow/deny list (denies .p8/.p12/xcconfig secrets)
├── docs/                    audit + architecture + tooling + deployment
│   ├── APP_MAP.md · SUPABASE_DEPENDENCY_MAP.md · DATA_MODEL.md · AUTH_FLOW.md
│   ├── API_MAP.md · IOS_MIGRATION_MAP.md · ARCHITECTURE.md
│   └── TOOLING.md · DEPLOYMENT.md
├── openapi.yaml             the v1 contract the Swift client codes against
└── FunctionAlps/
    ├── project.yml          XcodeGen spec → FunctionAlps.xcodeproj (git-ignored)
    ├── Config/*.xcconfig    Development / Staging / Production (+ Local.xcconfig, ignored)
    ├── Sources/
    │   ├── App/             entry, AppState, AppDependencies (composition root), router
    │   ├── Core/            Environment · Errors · Networking · Authentication · API · Security · Logging
    │   ├── DesignSystem/    tokens (FAColor, FATypography, FASpacing) + FA* components
    │   ├── Features/        Authentication · Home · Profile · Settings (view + view model each)
    │   ├── Models/          domain types (Member, DashboardSnapshot, …)
    │   ├── Services/        feature services over the backend protocol
    │   └── Resources/       Assets.xcassets · Localizable.xcstrings (en, fr)
    └── Tests/               Swift Testing unit tests (auth, session, API mapping, models)
```

## Build (no Mac: GitHub Actions is the Mac)
Push anything in this repo → the **iOS** workflow builds and runs the unit tests on a macOS runner; logs are attached as artifacts. TestFlight uploads are a manual run of the same workflow with `testflight=true` (see `docs/DEPLOYMENT.md` §5 for the secrets). Details for a Windows desktop: `docs/TOOLING.md` §0.

## Build (if a Mac is available)
```bash
brew install xcodegen
cd FunctionAlps
cp Config/Local.xcconfig.example Config/Local.xcconfig   # add your DEVELOPMENT_TEAM
xcodegen generate
open FunctionAlps.xcodeproj      # or: xcodebuild -scheme FunctionAlps -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Milestone 1 flow
Launch → (Keychain session?) → Login (email + password against the existing
FunctionAlps account) → Home (real member data) → Profile → Logout.
Acceptance criteria: PRD §23. Tracking: `docs/IOS_MIGRATION_MAP.md`.
