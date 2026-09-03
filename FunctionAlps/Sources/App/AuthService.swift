import Foundation
import Observation

/// App-facing authentication (PRD §17): login, logout, restore, and the single
/// place that flips `AppState.phase`. Token mechanics live in `SessionManager`.
@MainActor
@Observable
final class AuthService {
    private let sessions: SessionManager
    private let state: AppState

    init(sessions: SessionManager, state: AppState) {
        self.sessions = sessions
        self.state = state
    }

    /// Called once at launch. Keychain only — no network, so launch stays fast and offline-safe.
    func restore() async {
        if let session = await sessions.restore() {
            state.phase = .signedIn(userId: session.userId)
        } else {
            state.phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await sessions.signIn(email: EmailNormalizer.normalize(email), password: password)
        state.phase = .signedIn(userId: session.userId)
    }

    /// Google via the system browser sheet + PKCE. Throws `WebAuthenticator.WebAuthError.cancelled` on dismiss.
    func signInWithGoogle() async throws {
        let verifier = PKCE.codeVerifier()
        let url = await sessions.googleAuthorizeURL(codeChallenge: PKCE.codeChallenge(for: verifier))
        let callback = try await WebAuthenticator().authenticate(url: url, callbackScheme: "functionalps")
        let code = try OAuthCallback.code(from: callback)
        let session = try await sessions.signIn(authCode: code, codeVerifier: verifier)
        state.phase = .signedIn(userId: session.userId)
    }

    /// Native Sign in with Apple: pass the identity token and the raw nonce used for the request.
    func signInWithApple(identityToken: String, nonce: String) async throws {
        let session = try await sessions.signIn(appleIdentityToken: identityToken, nonce: nonce)
        state.phase = .signedIn(userId: session.userId)
    }

    func signOut() async {
        await sessions.signOut()
        state.phase = .signedOut
    }

    /// Any service that receives `.unauthorized` routes here so the UI returns to login exactly once.
    func handleUnauthorized() async {
        await sessions.clearLocal()
        state.phase = .signedOut
    }

    var currentUserId: String? {
        if case .signedIn(let id) = state.phase { return id }
        return nil
    }
}
