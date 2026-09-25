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
        /// The mailbox already owns a patient under ANOTHER auth user — the same person, signed in a
        /// different way (a Gmail dot alias through Google after an email/password account, 2026-09-25).
        /// A patient row has one owner, so this session can never read or write as that member; the app
        /// says which door to use. `providers` is how the owning account signs in, empty when unknown.
        case registeredElsewhere(providers: [String])
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
        // Ownership is the SERVER's answer, never the JWT's. `current_member_patient_id()` is
        // `select id from patients where auth_user_id = auth.uid()` — the same fact every RLS policy
        // uses. `user_metadata.patient_id` is only a cache, and it CAN name a patient this session does
        // not own: `patient-register` stamps it even on its "existing-identity" path, where the row was
        // already linked to a DIFFERENT auth user. That happens with two accounts for one mailbox — a
        // Gmail dot alias signing in with Google after an email/password account — and trusting the
        // claim mints a session whose every own-row read is denied. The member is then shown empty
        // screens and gates they already passed, with no error to explain it.
        if let owned = try await backend.currentPatientId() {
            await sessions.rememberPatientId(owned)   // no-ops when unchanged; corrects a stale cache
            patientId = owned
        } else {
            // Nobody owns this auth user yet: create or link. Deliberately NOT falling back to the
            // cached id here — an id the server just declined to confirm is the very thing not to trust.
            // Names: the sign-up metadata, else the display name, else "Member".
            let names = Self.names(for: session)
            guard let email = session.email, let outcome = try? await backend.registerPatient(firstName: names.first, lastName: names.last, email: email) else {
                throw MemberError.notRegistered
            }
            switch outcome {
            case .existingIdentity(let providers):
                throw MemberError.registeredElsewhere(providers: providers)
            case .patient(let id):
                // Ownership is checked AGAIN after registration, against the same server fact as above.
                // `patient-register` lives in four repos; an older copy answers the existing-identity
                // case with the OTHER account's id and a 200, and taking that id at its word is how a
                // member reached the consent gate and had every save refused (2026-09-25, HTTP 403
                // "no member context"). An id the server does not confirm as this session's is not used.
                guard try await backend.currentPatientId() == id else {
                    throw MemberError.registeredElsewhere(providers: [])
                }
                await sessions.rememberPatientId(id)
                patientId = id
            }
        }
        let profile = try await backend.memberProfile(patientId: patientId)
        let name = session.displayName
            ?? session.email.map { String($0.split(separator: "@").first ?? "") }
            ?? String(localized: "member.fallbackName", defaultValue: "Client")
        return Member(userId: session.userId, patientId: patientId, email: session.email, displayName: name, profile: profile)
    }

    /// "an email address and password", "Google", "Apple" — joined with "or" — for the screen that
    /// sends the member to the account that owns their record. Nothing recognisable ⇒ "another sign-in
    /// method", never a raw provider slug.
    static func signInMethodPhrase(providers: [String]) -> String {
        var seen: Set<String> = []
        let known: [String] = providers.compactMap { provider in
            let key = provider.lowercased()
            guard seen.insert(key).inserted else { return nil }
            switch key {
            case "email": return String(localized: "gate.registeredElsewhere.method.email", defaultValue: "an email address and password")
            case "google": return String(localized: "gate.registeredElsewhere.method.google", defaultValue: "Google")
            case "apple": return String(localized: "gate.registeredElsewhere.method.apple", defaultValue: "Apple")
            default: return nil
            }
        }
        guard !known.isEmpty else { return String(localized: "gate.registeredElsewhere.method.unknown", defaultValue: "another sign-in method") }
        return known.joined(separator: String(localized: "gate.registeredElsewhere.method.or", defaultValue: " or "))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
