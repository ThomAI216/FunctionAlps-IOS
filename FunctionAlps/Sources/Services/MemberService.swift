import Foundation

/// Resolves who is signed in: identity from the session, patient id via the ladder
/// (JWT metadata → RPC), profile from the backend. Mirrors the Expo `ensurePatientId`
/// ladder minus the third rung (`patient-register`), which belongs to sign-up (Phase A).
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

    func currentMember() async throws -> Member {
        guard let session = await sessions.restore() else { throw AppError.unauthorized }
        let patientId: String
        if let known = session.patientId {
            patientId = known
        } else if let resolved = try await backend.currentPatientId() {
            await sessions.rememberPatientId(resolved)
            patientId = resolved
        } else {
            throw MemberError.notRegistered
        }
        let profile = try await backend.memberProfile(patientId: patientId)
        let name = session.displayName
            ?? session.email.map { String($0.split(separator: "@").first ?? "") }
            ?? String(localized: "member.fallbackName", defaultValue: "Client")
        return Member(userId: session.userId, patientId: patientId, email: session.email, displayName: name, profile: profile)
    }
}
