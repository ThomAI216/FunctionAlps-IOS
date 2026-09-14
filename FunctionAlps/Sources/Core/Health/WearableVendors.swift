import Foundation

/// The seven direct vendors (owner decision 2026-09-04: free, direct OAuth; no aggregator). The phone
/// carries the copy; CM OS `wearable_vendors.status` says which are open to members today, so a vendor
/// goes live with a row update, not a release. `sourceId` = `wearable_connections.data_source_id`.
struct WearableVendor: Identifiable, Sendable, Equatable {
    let key: String
    let name: String
    let sourceId: Int
    let symbol: String
    let tintHex: UInt32
    /// What the direct connection adds beyond the Apple Health relay (one line).
    let adds: String
    /// What the vendor's own iPhone app already writes into Apple Health (so the relay has it).
    let viaAppleHealth: String
    var id: String { key }

    /// The asset-catalog image set for the brand's monochrome mark (`Assets.xcassets/vendor-<key>.imageset`,
    /// template-rendered in `tintHex`). Bundled 2026-09-14 for every vendor but Withings (no open-licence mark
    /// exists); a missing set falls back to the `wordmark` — never a generic symbol.
    var logoAsset: String { "vendor-\(key)" }

    /// The brand's own spelling of its name, for the fallback mark.
    var wordmark: String {
        switch key {
        case "oura": "ŌURA"
        case "whoop": "WHOOP"
        case "polar": "Polar"
        case "garmin": "GARMIN"
        case "withings": "withings"
        case "suunto": "SUUNTO"
        case "google": "Fitbit"
        default: name
        }
    }

    static var all: [WearableVendor] {
        [
            WearableVendor(key: "oura", name: "Oura", sourceId: 1_000_018, symbol: "circle.circle", tintHex: 0x3F3F46,
                           adds: String(localized: "vendor.oura.adds", defaultValue: "Nightly HRV, readiness, temperature deviation, daytime stress"),
                           viaAppleHealth: String(localized: "vendor.oura.relay", defaultValue: "Sleep with stages, heart rate, steps, energy, workouts (no HRV, no readiness)")),
            WearableVendor(key: "whoop", name: "WHOOP", sourceId: 1_000_042, symbol: "waveform.path.ecg", tintHex: 0x1F1F1F,
                           adds: String(localized: "vendor.whoop.adds", defaultValue: "HRV per sleep, recovery, strain, skin temperature"),
                           viaAppleHealth: String(localized: "vendor.whoop.relay", defaultValue: "Sleep without stages, resting heart rate, blood oxygen, breathing rate, workouts (no HRV)")),
            WearableVendor(key: "polar", name: "Polar", sourceId: 1_000_003, symbol: "heart.circle", tintHex: 0xD7263D,
                           adds: String(localized: "vendor.polar.adds", defaultValue: "Nightly Recharge HRV and ANS charge, sleep stages, training load"),
                           viaAppleHealth: String(localized: "vendor.polar.relay", defaultValue: "Sleep without stages, steps, weight, workout heart rate (no HRV, no 24/7 heart rate)")),
            WearableVendor(key: "garmin", name: "Garmin", sourceId: 1_000_002, symbol: "figure.run.circle", tintHex: 0x0F5FA6,
                           adds: String(localized: "vendor.garmin.adds", defaultValue: "Nightly HRV, stress, Body Battery, blood pressure, cycle"),
                           viaAppleHealth: String(localized: "vendor.garmin.relay", defaultValue: "Sleep with stages, heart rate, steps, calories, workouts (no HRV, no Body Battery)")),
            WearableVendor(key: "withings", name: "Withings", sourceId: 1_000_008, symbol: "scalemass", tintHex: 0x00A9A5,
                           adds: String(localized: "vendor.withings.adds", defaultValue: "HRV (RMSSD and SDNN), body composition, blood pressure, sleep score"),
                           viaAppleHealth: String(localized: "vendor.withings.relay", defaultValue: "Weight and body composition, sleep with stages, heart rate, blood pressure, steps (no HRV)")),
            WearableVendor(key: "suunto", name: "Suunto", sourceId: 1_000_050, symbol: "mountain.2", tintHex: 0x2B2B2B,
                           adds: String(localized: "vendor.suunto.adds", defaultValue: "Sleep and recovery with HRV, training sessions"),
                           viaAppleHealth: String(localized: "vendor.suunto.relay", defaultValue: "Workouts, steps, workout heart rate (no sleep, no HRV)")),
            WearableVendor(key: "google", name: "Google (Fitbit)", sourceId: 1_000_011, symbol: "g.circle", tintHex: 0x4285F4,
                           adds: String(localized: "vendor.google.adds", defaultValue: "Daily HRV, sleep stages, temperature deviation"),
                           viaAppleHealth: String(localized: "vendor.google.relay", defaultValue: "Sleep with stages, steps, workouts, vitals from the Google Health app (no HRV)")),
        ]
    }

    static func vendor(_ key: String) -> WearableVendor? { all.first { $0.key == key } }
}

/// `wearable_vendors` (R, authenticated): which vendors the practice has opened.
struct WearableVendorRow: Decodable, Sendable, Equatable {
    let key: String
    let name: String
    let dataSourceId: Int
    let status: String
    var isAvailable: Bool { status == "available" }
}

/// `wearable-oauth-start`'s answer.
struct VendorConnectStart: Decodable, Sendable, Equatable {
    let url: URL
    let vendor: String
}

/// `functionalps://wearables/callback?vendor=oura&status=ok|error&reason=…` — what the callback function sends back.
enum VendorCallback {
    enum Outcome: Sendable, Equatable { case ok(vendor: String), failed(vendor: String?, reason: String) }

    static func parse(_ url: URL) -> Outcome {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let vendor = items.first { $0.name == "vendor" }?.value
        let status = items.first { $0.name == "status" }?.value
        let reason = items.first { $0.name == "reason" }?.value ?? "unknown"
        if status == "ok", let vendor { return .ok(vendor: vendor) }
        return .failed(vendor: vendor, reason: reason)
    }

    static func message(for reason: String) -> String {
        switch reason {
        case "denied", "access_denied": String(localized: "vendor.err.denied", defaultValue: "You didn't allow the connection. Nothing was linked.")
        case "expired": String(localized: "vendor.err.expired", defaultValue: "The sign-in took too long. Please try again.")
        case "already_linked": String(localized: "vendor.err.alreadyLinked", defaultValue: "This wearable account is already linked to another FunctionAlps account. Unlink it there first.")
        case "vendor_paused": String(localized: "vendor.err.paused", defaultValue: "This connection is paused by the practice for the moment. Please try again later.")
        default: String(localized: "vendor.err.generic", defaultValue: "The connection didn't complete. Please try again in a moment.")
        }
    }
}

/// One `wearable_vendor_accounts` row as the member may read it (platform v2: status columns only, never the
/// tokens — the column grant + RLS on CM OS enforce that). The nine server states collapse into what the
/// Devices card shows.
struct WearableVendorAccountRow: Decodable, Sendable, Equatable {
    let vendor: String
    let status: String
    let reconnectRequired: Bool?
    let lastSuccessfulSyncAt: Date?
    let lastErrorCode: String?
    let connectedAt: Date?

    enum Presentation: Sendable, Equatable { case live, syncing, degraded, reconnect, off }

    var presentation: Presentation {
        switch status {
        case "connected": .live
        case "syncing": .syncing
        case "degraded": .degraded
        case "reconnect_required", "revoked", "error": .reconnect
        default: .off   // not_connected · connecting · disconnected
        }
    }

    /// The account still holds a credential and the backend keeps pulling.
    var isLive: Bool { presentation == .live || presentation == .syncing || presentation == .degraded }
}
