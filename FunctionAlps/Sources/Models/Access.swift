import Foundation

/// One `member_entitlements` row the member may read (RLS self-select).
struct EntitlementRow: Decodable, Sendable, Equatable {
    let accessType: String
    let status: String
    let startsAt: Date?
    let expiresAt: Date?
}

/// The app access window (the Expo `lib/access/entitlement.ts`). FAIL-OPEN, deliberately:
/// every unknown resolves to "allowed" — access is revoked from the dashboard, not enforced
/// by a phone with flaky connectivity.
struct AppAccess: Sendable, Equatable {
    enum Tier: String, Sendable { case fullAccess = "full_access", paid, beta, discovery, unknown }
    let allowed: Bool
    let tier: Tier
    let windowEndsAt: Date?
    let daysLeft: Int?

    static let allowedUnknown = AppAccess(allowed: true, tier: .unknown, windowEndsAt: nil, daysLeft: nil)
    static let discoveryDays = 3
    private static let dayMs: Double = 86_400

    private static let rank: [String: Double] = ["full_access": 3, "paid": 2, "beta": 1, "discovery": 0.5, "trial": 0]

    private static func isLive(_ row: EntitlementRow, now: Date) -> Bool {
        guard row.status == "active" || row.status == "grace" else { return false }
        guard let exp = row.expiresAt else { return true }
        return exp > now
    }

    static func resolve(_ rows: [EntitlementRow], now: Date = Date()) -> AppAccess {
        let best = rows.filter { isLive($0, now: now) }
            .sorted { (rank[$0.accessType] ?? 0) > (rank[$1.accessType] ?? 0) }
            .first
        guard let best else { return allowedUnknown }
        switch best.accessType {
        case "paid", "full_access":
            return AppAccess(allowed: true, tier: Tier(rawValue: best.accessType) ?? .unknown, windowEndsAt: nil, daysLeft: nil)
        case "beta":
            guard let exp = best.expiresAt else { return AppAccess(allowed: true, tier: .beta, windowEndsAt: nil, daysLeft: nil) }
            let secs = exp.timeIntervalSince(now)
            return AppAccess(allowed: exp > now, tier: .beta, windowEndsAt: exp, daysLeft: max(0, Int(ceil(secs / dayMs))))
        case "discovery":
            guard let start = best.startsAt else { return allowedUnknown }
            let end = start.addingTimeInterval(Double(discoveryDays) * dayMs)
            let secs = end.timeIntervalSince(now)
            return AppAccess(allowed: end > now, tier: .discovery, windowEndsAt: end, daysLeft: max(0, Int(ceil(secs / dayMs))))
        default:
            return allowedUnknown
        }
    }
}

/// The countdown copy for a windowed tier, or nil when there is nothing to say (a client has
/// no deadline and must never see one). The Expo `lib/access/countdown.ts`.
struct AccessCountdown: Sendable, Equatable {
    let tier: AppAccess.Tier
    let label: String
    let headline: String
    let detail: String
    let urgent: Bool

    static func describe(_ access: AppAccess, locale: Locale = .current) -> AccessCountdown? {
        guard access.tier == .beta || access.tier == .discovery, let daysLeft = access.daysLeft else { return nil }
        let headline: String
        if daysLeft <= 0 { headline = String(localized: "access.endsToday", defaultValue: "Ends today") }
        else if daysLeft == 1 { headline = String(localized: "access.lastDay", defaultValue: "Last day") }
        else { headline = String(localized: "access.daysLeft", defaultValue: "\(daysLeft) days left") }

        if access.tier == .beta {
            let endsOn = access.windowEndsAt.map { $0.formatted(.dateTime.day().month(.wide).locale(locale)) } ?? ""
            return AccessCountdown(
                tier: .beta,
                label: String(localized: "access.beta.label", defaultValue: "Beta access"),
                headline: headline,
                detail: endsOn.isEmpty
                    ? String(localized: "access.beta.detail.noDate", defaultValue: "Everything you record stays yours after your thirty days.")
                    : String(localized: "access.beta.detail", defaultValue: "Your thirty days end on \(endsOn). Everything you record stays yours after that."),
                urgent: daysLeft <= 7
            )
        }
        return AccessCountdown(
            tier: .discovery,
            label: String(localized: "access.discovery.label", defaultValue: "Discovery access"),
            headline: headline,
            detail: String(localized: "access.discovery.detail", defaultValue: "Ask for full access whenever you are ready and we will take it from there."),
            urgent: daysLeft <= 1
        )
    }

    static let membersRequestURL = URL(string: "https://members.functionalps.ch/dashboard/request-access")!
}
