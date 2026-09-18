import Foundation
import Testing
@testable import FunctionAlps

@Suite("AppAccess — open windows")
struct AccessTests {
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 18))!

    private func row(_ type: String, status: String = "active", startsDaysAgo: Int? = nil, expiresInDays: Int? = nil) -> EntitlementRow {
        EntitlementRow(
            accessType: type, status: status,
            startsAt: startsDaysAgo.map { now.addingTimeInterval(Double(-$0) * 86_400) },
            expiresAt: expiresInDays.map { now.addingTimeInterval(Double($0) * 86_400) }
        )
    }

    // What the owner asked for on 2026-09-18: open to anybody with the link.

    @Test func discoveryNeverClosesTheDoorNorCountsDown() {
        // Ten days into a window that used to be three: the member who reported "only available for
        // 3 days" had exactly this row, granted automatically by patient-register.
        let access = AppAccess.resolve([row("discovery", startsDaysAgo: 10)], now: now)
        #expect(access.allowed)
        #expect(access.daysLeft == nil)
        #expect(access.windowEndsAt == nil)
        // No daysLeft ⇒ no countdown strip, without the countdown needing its own switch.
        #expect(AccessCountdown.describe(access) == nil)
    }

    @Test func betaNeverCountsDownEither() {
        // A LIVE beta: an expired one never reaches the beta branch at all (see below).
        let access = AppAccess.resolve([row("beta", expiresInDays: 5)], now: now)
        #expect(access.allowed)
        #expect(access.daysLeft == nil)
        #expect(AccessCountdown.describe(access) == nil)
    }

    /// Worth knowing before anyone reinstates the windows: `beta` never actually closed the door.
    /// `isLive` drops a row whose `expires_at` has passed, so an expired beta never reaches the beta
    /// branch — it leaves no live row, and no live row means `allowedUnknown`. Only `discovery`, whose
    /// 3-day window is computed app-side from `starts_at` and is invisible to `isLive`, ever locked
    /// anyone out. That is why the reports were all about three days.
    @Test func anExpiredBetaFallsToFailOpenNotToAClosedDoor() {
        for open in [true, false] {
            let access = AppAccess.resolve([row("beta", expiresInDays: -1)], now: now, windowsOpen: open)
            #expect(access == .allowedUnknown)
        }
    }

    @Test func theTierIsStillReportedHonestly() {
        // Open does not mean "pretend everyone is a client": the tier still resolves, so the dashboard
        // and any tier-specific copy keep telling the truth.
        #expect(AppAccess.resolve([row("discovery", startsDaysAgo: 10)], now: now).tier == .discovery)
        #expect(AppAccess.resolve([row("full_access")], now: now).tier == .fullAccess)
    }

    @Test func highestLiveTierStillWins() {
        let access = AppAccess.resolve([row("discovery", startsDaysAgo: 10), row("full_access")], now: now)
        #expect(access.tier == .fullAccess)
        #expect(access.allowed)
    }

    // Fail-open was already the rule and is unchanged: revocation has never locked the app.

    @Test func noLiveRowIsAllowedUnknown() {
        #expect(AppAccess.resolve([], now: now) == .allowedUnknown)
        #expect(AppAccess.resolve([row("discovery", status: "revoked", startsDaysAgo: 1)], now: now) == .allowedUnknown)
    }

    // And the arithmetic still works, so putting the windows back is one line and not a rewrite.

    @Test func theWindowsStillWorkWhenPutBack() {
        let closed = AppAccess.resolve([row("discovery", startsDaysAgo: 10)], now: now, windowsOpen: false)
        #expect(!closed.allowed)
        #expect(closed.daysLeft == 0)

        let live = AppAccess.resolve([row("discovery", startsDaysAgo: 1)], now: now, windowsOpen: false)
        #expect(live.allowed)
        #expect(live.daysLeft == 2)
        #expect(AccessCountdown.describe(live)?.tier == .discovery)

        let liveBeta = AppAccess.resolve([row("beta", expiresInDays: 5)], now: now, windowsOpen: false)
        #expect(liveBeta.allowed)
        #expect(liveBeta.daysLeft == 5)
        #expect(AccessCountdown.describe(liveBeta)?.tier == .beta)
    }
}
