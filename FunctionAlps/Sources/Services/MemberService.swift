import Foundation

/// Resolves who is signed in: identity from the session, patient id via the ladder
/// (JWT metadata → RPC → `patient-register`), profile from the backend. Mirrors the Expo `ensurePatientId`.
/// Registration is idempotent server-side (email-hash dedupe), so retrying it is always safe.
struct MemberService: Sendable {
    private let sessions: SessionManager
    private let backend: any FunctionAlpsBackend

    init(sessions: SessionManager, backend: any FunctionAlpsBackend) {
        self.sessions = sessions
        self.backend = backend
    }

    enum MemberError: Error, Equatable {
        /// The account exists but has no `patients` row yet (registered elsewhere, never opened the app).
        case notRegistered
    }

    /// `patient-register` rejects empty names — the Expo fallback ladder.
    static func names(for session: AuthSession) -> (first: String, last: String) {
        if let f = session.firstName?.trimmingCharacters(in: .whitespaces), !f.isEmpty {
            return (f, session.lastName?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "Member")
        }
        let parts = (session.displayName ?? "").split(separator: " ").map(String.init)
        if parts.count >= 2 { return (parts[0], parts.dropFirst().joined(separator: " ")) }
        if let only = parts.first, !only.isEmpty { return (only, "Member") }
        return ("Member", "Member")
    }

    func currentMember() async throws -> Member {
        guard let session = await sessions.restore() else { throw AppError.unauthorized }
        let patientId: String
        if let known = session.patientId {
            patientId = known
        } else if let resolved = try await backend.currentPatientId() {
            await sessions.rememberPatientId(resolved)
            patientId = resolved
        } else {
            // Third rung: create (or link) the patient row. Names: the sign-up metadata, else the display name, else "Member".
            let names = Self.names(for: session)
            guard let email = session.email, let registered = try? await backend.registerPatient(firstName: names.first, lastName: names.last, email: email) else {
                throw MemberError.notRegistered
            }
            await sessions.rememberPatientId(registered)
            patientId = registered
        }
        let profile = try await backend.memberProfile(patientId: patientId)
        let name = session.displayName
            ?? session.email.map { String($0.split(separator: "@").first ?? "") }
            ?? String(localized: "member.fallbackName", defaultValue: "Client")
        return Member(userId: session.userId, patientId: patientId, email: session.email, displayName: name, profile: profile)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
