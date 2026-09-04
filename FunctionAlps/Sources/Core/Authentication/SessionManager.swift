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

    /// Completes a browser (PKCE) sign-in with the redirect's `code`.
    /// Sign-up; a live session (auto-confirm) is persisted, an email-confirmation outcome is passed through.
    func signUp(email: String, password: String, firstName: String, lastName: String, phone: String?) async throws -> SupabaseAuthClient.SignUpOutcome {
        let outcome = try await auth.signUp(email: email, password: password, firstName: firstName, lastName: lastName, phone: phone)
        if case .signedIn(let fresh) = outcome { try persist(fresh) }
        return outcome
    }

    func emailExists(_ email: String) async -> Bool? { await auth.emailExists(email) }
    func requestPasswordReset(email: String) async { await auth.recover(email: email) }

    func signIn(authCode: String, codeVerifier: String) async throws -> AuthSession {
        let fresh = try await auth.exchangeCode(authCode, codeVerifier: codeVerifier)
        try persist(fresh)
        Log.auth.info("signed in via OAuth user \(fresh.userId.prefix(8), privacy: .public)…")
        return fresh
    }

    /// Completes a native Sign in with Apple.
    func signIn(appleIdentityToken: String, nonce: String) async throws -> AuthSession {
        let fresh = try await auth.signInWithIdToken(provider: "apple", idToken: appleIdentityToken, nonce: nonce)
        try persist(fresh)
        Log.auth.info("signed in via Apple user \(fresh.userId.prefix(8), privacy: .public)…")
        return fresh
    }

    /// Builds the Google authorize URL (the caller keeps the verifier for the exchange).
    func googleAuthorizeURL(codeChallenge: String) -> URL {
        auth.authorizeURL(provider: "google", codeChallenge: codeChallenge)
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
