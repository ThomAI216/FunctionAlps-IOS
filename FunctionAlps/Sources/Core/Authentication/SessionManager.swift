import Foundation

/// Owns the persisted session and hands out valid access tokens.
/// An actor so refreshes are serialized; an in-flight refresh is shared so two
/// concurrent callers never rotate the same refresh token twice.
actor SessionManager {
    private let auth: SupabaseAuthClient
    private let store: any SessionStore
    private let now: @Sendable () -> Date
    private(set) var session: AuthSession?
    private var inflightRefresh: Task<AuthSession, Error>?

    init(auth: SupabaseAuthClient, store: any SessionStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.auth = auth
        self.store = store
        self.now = now
    }

    /// Loads the persisted session without touching the network. Nil = signed out.
    @discardableResult
    func restore() -> AuthSession? {
        if let session { return session }
        do {
            session = try store.load()
        } catch {
            Log.auth.error("session restore failed: \(String(describing: error), privacy: .public)")
            session = nil
        }
        return session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let fresh = try await auth.signIn(email: email, password: password)
        try persist(fresh)
        Log.auth.info("signed in user \(fresh.userId.prefix(8), privacy: .public)…")
        return fresh
    }

    /// Best-effort server logout, then always clears local state.
    func signOut() async {
        if let session {
            do { try await auth.signOut(accessToken: session.accessToken) } catch {
                Log.auth.info("server sign-out skipped: \(String(describing: error), privacy: .public)")
            }
        }
        clearLocal()
    }

    /// Clears local state only (used when the server says the session is dead).
    func clearLocal() {
        session = nil
        inflightRefresh?.cancel()
        inflightRefresh = nil
        do { try store.clear() } catch {
            Log.auth.error("session clear failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Returns a token that is valid for at least `leeway` seconds, refreshing if needed.
    func validAccessToken(leeway: TimeInterval = 60) async throws -> String {
        guard let current = session ?? restore() else { throw AppError.unauthorized }
        if !current.isExpiring(within: leeway, now: now()) {
            return current.accessToken
        }
        return try await refresh(from: current).accessToken
    }

    /// Forces a refresh (after a 401 from the API). Returns the new token or throws `.unauthorized`.
    func forceRefresh() async throws -> String {
        guard let current = session ?? restore() else { throw AppError.unauthorized }
        return try await refresh(from: current).accessToken
    }

    /// Persists a patient id resolved after sign-in (RPC ladder) so later launches skip the lookup.
    func rememberPatientId(_ patientId: String) {
        guard var current = session ?? restore(), current.patientId != patientId else { return }
        current.patientId = patientId
        try? persist(current)
    }

    // MARK: Internals

    private func refresh(from current: AuthSession) async throws -> AuthSession {
        if let inflight = inflightRefresh {
            return try await inflight.value
        }
        let task = Task<AuthSession, Error> { [auth] in
            try await auth.refresh(refreshToken: current.refreshToken)
        }
        inflightRefresh = task
        defer { inflightRefresh = nil }
        do {
            var fresh = try await task.value
            if fresh.patientId == nil { fresh.patientId = current.patientId }
            try persist(fresh)
            return fresh
        } catch let error as AppError {
            if case .offline = error { throw error }
            // Refresh token rejected: the session is gone for good.
            clearLocal()
            throw AppError.unauthorized
        } catch {
            clearLocal()
            throw AppError.unauthorized
        }
    }

    private func persist(_ fresh: AuthSession) throws {
        session = fresh
        do { try store.save(fresh) } catch {
            Log.auth.error("session persist failed: \(String(describing: error), privacy: .public)")
            throw AppError.configuration(detail: "keychain write failed")
        }
    }
}
