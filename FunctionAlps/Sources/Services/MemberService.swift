import Foundation

/// Resolves who is signed in: identity from the session, patient id via the ladder
/// (JWT metadata → RPC → `patient-register`), profile from the backend. Mirrors the Expo `ensurePatientId`.
/// Registration is idempotent server-side (email-hash dedupe), so retrying it is always safe.
struct MemberService: Sendable {
    private let sessions: SessionManager
    private let backend: any FunctionAlpsBackend
    /// One answer shared by every caller for `ttl`; see `MemberCache`. A reference type, so copies of this
    /// struct (it is passed around by value) all share it.
    private let cache: MemberCache

    init(sessions: SessionManager, backend: any FunctionAlpsBackend,
         ttl: TimeInterval = MemberCache.defaultTTL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.sessions = sessions
        self.backend = backend
        self.cache = MemberCache(ttl: ttl, now: now)
    }

    /// Drops what is remembered: after a profile write, a sign-out, or when a call using the id was refused.
    func invalidate() async { await cache.invalidate() }

    /// The patient id the server confirms for this session (`current_member_patient_id`), answered from the
    /// same short-lived cache as `currentMember()`. Nil = nobody owns this auth user yet. Use this instead of
    /// `backend.currentPatientId()`; the server is still the source, it is just not asked again within the TTL.
    func patientId() async throws -> String? {
        guard let session = await sessions.restore() else { throw AppError.unauthorized }
        let backend = self.backend
        return try await cache.patientId(userId: session.userId) { try await backend.currentPatientId() }
    }

    /// For services that may or may not have been given a `MemberService`: cached when there is one, else the raw read.
    static func patientId(via members: MemberService?, backend: any FunctionAlpsBackend) async throws -> String? {
        if let members { return try await members.patientId() }
        return try await backend.currentPatientId()
    }

    /// The member, from the cache when it is fresh and belongs to the signed-in user; otherwise one
    /// resolution that concurrent callers share. `forceRefresh` always asks the server.
    func currentMember(forceRefresh: Bool = false) async throws -> Member {
        guard let session = await sessions.restore() else {
            await cache.invalidate()
            throw AppError.unauthorized
        }
        do {
            return try await cache.member(userId: session.userId, forceRefresh: forceRefresh) { try await self.resolveMember() }
        } catch let error as AppError {
            if error == .unauthorized || error == .forbidden { await cache.invalidate() }
            throw error
        }
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

    private func resolveMember() async throws -> Member {
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

/// In-memory memory of who the member is, so ~50 callers do not each pay the RPC + profile read.
/// Keyed by the session's user id (a different user never sees another's entry), expires after `ttl`, and
/// shares one in-flight resolution between concurrent callers. Failures are never cached. Nothing is
/// persisted: a launch always asks the server once.
actor MemberCache {
    static let defaultTTL: TimeInterval = 600

    private struct Entry { let userId: String; let member: Member; let at: Date }
    private struct IdEntry { let userId: String; let id: String?; let at: Date }
    private struct Inflight { let token: Int; let userId: String; let task: Task<Member, Error> }

    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var entry: Entry?
    private var idEntry: IdEntry?
    private var inflight: Inflight?
    private var generation = 0
    private var tokens = 0

    init(ttl: TimeInterval, now: @escaping @Sendable () -> Date) {
        self.ttl = ttl
        self.now = now
    }

    func member(userId: String, forceRefresh: Bool, load: @escaping @Sendable () async throws -> Member) async throws -> Member {
        if !forceRefresh {
            if let entry, entry.userId == userId, now().timeIntervalSince(entry.at) < ttl { return entry.member }
            if let inflight, inflight.userId == userId { return try await inflight.task.value }
        }
        tokens += 1
        let token = tokens
        let gen = generation
        let task = Task<Member, Error> {
            do {
                let member = try await load()
                await self.finish(token: token, generation: gen, userId: userId, member: member)
                return member
            } catch {
                await self.fail(token: token)
                throw error
            }
        }
        inflight = Inflight(token: token, userId: userId, task: task)
        return try await task.value
    }

    func patientId(userId: String, load: @escaping @Sendable () async throws -> String?) async throws -> String? {
        if let entry, entry.userId == userId, now().timeIntervalSince(entry.at) < ttl { return entry.member.patientId }
        if let idEntry, idEntry.userId == userId, now().timeIntervalSince(idEntry.at) < ttl { return idEntry.id }
        let gen = generation
        let id = try await load()
        // Only a confirmed id is remembered: "nobody owns this yet" must be re-asked (registration may follow).
        if gen == generation, id != nil { idEntry = IdEntry(userId: userId, id: id, at: now()) }
        return id
    }

    func invalidate() {
        generation += 1
        entry = nil
        idEntry = nil
        inflight = nil
    }

    private func finish(token: Int, generation gen: Int, userId: String, member: Member) {
        if inflight?.token == token { inflight = nil }
        guard gen == generation else { return }   // invalidated while resolving: do not store a stale answer
        entry = Entry(userId: userId, member: member, at: now())
        idEntry = IdEntry(userId: userId, id: member.patientId, at: now())
    }

    private func fail(token: Int) {
        if inflight?.token == token { inflight = nil }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
