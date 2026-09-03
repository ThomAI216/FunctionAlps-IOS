import Foundation

/// Domain operations the app needs. Implementations own the transport.
/// Today: `SupabaseBackend` (PostgREST + Edge Functions on CM OS).
/// Later: `GatewayBackend` for `api.functionalps.ch` — same protocol, no feature changes.
protocol FunctionAlpsBackend: Sendable {
    /// `patients.id` for the signed-in account, or nil when the account has no patient row yet.
    func currentPatientId() async throws -> String?
    func memberProfile(patientId: String) async throws -> MemberProfile?
    func meals(patientId: String, since: Date) async throws -> [MealLog]
    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin?
    func unreadClinicianMessageCount(patientId: String) async throws -> Int
}
