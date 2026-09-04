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

    static var all: [WearableVendor] {
        [
            WearableVendor(key: "oura", name: "Oura", sourceId: 1_000_018, symbol: "circle.circle", tintHex: 0x3F3F46,
                           adds: String(localized: "vendor.oura.adds", defaultValue: "Nightly HRV, readiness, temperature deviation, daytime stress"),
                           viaAppleHealth: String(localized: "vendor.oura.relay", defaultValue: "Sleep, heart rate, steps, energy, workouts")),
            WearableVendor(key: "whoop", name: "WHOOP", sourceId: 1_000_042, symbol: "waveform.path.ecg", tintHex: 0x1F1F1F,
                           adds: String(localized: "vendor.whoop.adds", defaultValue: "HRV per sleep, recovery, strain, skin temperature"),
                           viaAppleHealth: String(localized: "vendor.whoop.relay", defaultValue: "Sleep, heart rate, resting heart rate, workouts")),
            WearableVendor(key: "polar", name: "Polar", sourceId: 1_000_003, symbol: "heart.circle", tintHex: 0xD7263D,
                           adds: String(localized: "vendor.polar.adds", defaultValue: "Nightly Recharge HRV and ANS charge, sleep stages, training load"),
                           viaAppleHealth: String(localized: "vendor.polar.relay", defaultValue: "Sleep, heart rate, steps, workouts")),
            WearableVendor(key: "garmin", name: "Garmin", sourceId: 1_000_002, symbol: "figure.run.circle", tintHex: 0x0F5FA6,
                           adds: String(localized: "vendor.garmin.adds", defaultValue: "Nightly HRV, stress, Body Battery, blood pressure, cycle"),
                           viaAppleHealth: String(localized: "vendor.garmin.relay", defaultValue: "Sleep, heart rate, steps, energy, workouts")),
            WearableVendor(key: "withings", name: "Withings", sourceId: 1_000_008, symbol: "scalemass", tintHex: 0x00A9A5,
                           adds: String(localized: "vendor.withings.adds", defaultValue: "HRV (RMSSD and SDNN), body composition, blood pressure, sleep score"),
                           viaAppleHealth: String(localized: "vendor.withings.relay", defaultValue: "Weight, sleep, heart rate, blood pressure, steps")),
            WearableVendor(key: "suunto", name: "Suunto", sourceId: 1_000_050, symbol: "mountain.2", tintHex: 0x2B2B2B,
                           adds: String(localized: "vendor.suunto.adds", defaultValue: "Sleep and recovery with HRV, training sessions"),
                           viaAppleHealth: String(localized: "vendor.suunto.relay", defaultValue: "Workouts, steps, heart rate, sleep")),
            WearableVendor(key: "google", name: "Google (Fitbit)", sourceId: 1_000_011, symbol: "g.circle", tintHex: 0x4285F4,
                           adds: String(localized: "vendor.google.adds", defaultValue: "Daily HRV, sleep stages, temperature deviation"),
                           viaAppleHealth: String(localized: "vendor.google.relay", defaultValue: "Sleep, heart rate, steps, energy (Google Health app sync)")),
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
        default: String(localized: "vendor.err.generic", defaultValue: "The connection didn't complete. Please try again in a moment.")
        }
    }
}
