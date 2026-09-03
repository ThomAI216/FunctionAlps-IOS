import Foundation

/// The authenticated state the app persists (in Keychain only — PRD §17).
/// This is the FunctionAlps notion of a session; the fact that it is currently a
/// Supabase GoTrue token pair is a transport detail confined to `SupabaseAuthClient`.
struct AuthSession: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    /// `auth.users.id`. NOT the patient id — see `patientId`.
    let userId: String
    let email: String?
    /// `public.patients.id`, stamped into `user_metadata.patient_id` by `patient-register`.
    /// Nil for accounts registered before that stamp existed; resolved via RPC then.
    var patientId: String?
    /// From `user_metadata.full_name` / `name` / `first_name` — never fetched from the PII vault.
    var displayName: String? = nil

    /// True when the access token expires within `leeway` seconds.
    func isExpiring(within leeway: TimeInterval = 60, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

/// Minimal identity returned by the auth provider. Never logged in full.
struct AuthUser: Decodable, Sendable, Equatable {
    let id: String
    let email: String?
    let createdAt: String?
}
