import Foundation

/// Mirrors the Expo app's `normalizeEmail` and the CM OS `canonical_email` SQL:
/// one email = one patient. No plus-aliases anywhere, no dot tricks on Gmail.
/// Apply at every auth entry point before the value reaches the backend.
enum EmailNormalizer {
    static func normalize(_ raw: String) -> String {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = e.lastIndex(of: "@"), at != e.startIndex, e.index(after: at) != e.endIndex else {
            return e // not an email shape — leave as-is
        }
        var local = String(e[..<at])
        var domain = String(e[e.index(after: at)...])
        if let plus = local.firstIndex(of: "+") {
            local = String(local[..<plus])
        }
        if domain == "gmail.com" || domain == "googlemail.com" {
            local = local.replacingOccurrences(of: ".", with: "")
            domain = "gmail.com"
        }
        return "\(local)@\(domain)"
    }
}

/// Build flavour helpers for showing developer detail only where testers expect it.
enum BuildInfo {
    /// True in Debug builds and in TestFlight installs (sandbox receipt); false on the App Store.
    static var showsTechnicalDetails: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
