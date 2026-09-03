# FunctionAlps iOS — agent context

## Quick reference
- Platform iOS 17+ · Swift 6 (strict concurrency) · SwiftUI only · `@Observable` view models · `NavigationStack` typed routes · Swift Testing.
- Project is generated: edit `FunctionAlps/project.yml`, then `xcodegen generate`. Never hand-edit `*.pbxproj`.
- The owner develops on **Windows**: there is no local Xcode. Build/test = the `iOS` GitHub Actions workflow (push to a branch, then read the run logs via the GitHub API and fix). `.mcp.json` / XcodeBuildMCP only matter if a Mac appears. See `docs/TOOLING.md` §0.

## Read first
`docs/ARCHITECTURE.md` → `docs/API_MAP.md` → `docs/DATA_MODEL.md` → `docs/AUTH_FLOW.md`. The Expo app in `FunctionAlps-APP` is the **UX and behaviour reference**, not code to port.

## Rules (each one names its reason)
1. Views never call the network or touch tables. View → ViewModel → Service → `FunctionAlpsBackend` → transport. (PRD §6/§16; keeps the Supabase→Swiss migration a one-file swap.)
2. Only `Core/API/*` may know table or edge-function names. (PRD §61.)
3. Tokens live in Keychain (`KeychainSessionStore`) — never UserDefaults, never logs. (PRD §17/§52.)
4. Never add a secret to any xcconfig or Swift file; the app holds only the publishable key. (PRD §30/§36.)
5. Every network-backed screen renders loading / error / empty / unauthorized. Use `FALoadingState` / `FAErrorState` / `FAEmptyState`. (PRD §43.)
6. No clinical or health wording invented in Swift — copy from the Expo app's i18n strings or the backend. (PRD §47.)
7. User-facing text goes through `String(localized:defaultValue:)` and `Resources/Localizable.xcstrings` (en, fr). (PRD §49.)
8. No third-party packages without a written justification in `docs/ARCHITECTURE.md`. (PRD §13.)
9. Business/health calculations stay server-side (edge functions / RPCs); Swift only formats. (PRD §41.)
10. Accessibility: Dynamic Type, labels on icons, status never by colour alone. (PRD §50.)

## Do not
- Wrap the web app in a WebView, add Capacitor, or add the Supabase Swift SDK.
- Change the bundle id after the first App Store Connect upload.
- Commit `.p8`, `.p12`, `.mobileprovision`, `Local.xcconfig`, `Secrets.xcconfig`.

## Workflow
Small vertical slices (PRD §21): real data · navigation · loading/error/empty · auth · tests · runs on a physical iPhone. Update `docs/IOS_MIGRATION_MAP.md` when a slice lands.
