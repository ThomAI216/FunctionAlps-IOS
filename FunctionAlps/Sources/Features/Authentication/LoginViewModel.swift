import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    var isSubmitting = false
    var errorMessage: String?
    /// Developer-facing cause, shown only in Debug/TestFlight builds.
    var errorDetail: String?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    var isSocialBusy = false
    /// Raw nonce for the in-flight Apple request (its SHA-256 goes into the request).
    private(set) var appleNonce = PKCE.nonce()

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleNonce = PKCE.nonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce = PKCE.sha256Hex(appleNonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            Log.auth.error("apple sign-in: \(String(describing: error), privacy: .public)")
            errorMessage = AppError.unknown(detail: "").userMessage
            errorDetail = String(describing: error)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = AppError.unknown(detail: "").userMessage
                errorDetail = "Apple credential without identity token"
                return
            }
            await run { try await self.auth.signInWithApple(identityToken: token, nonce: self.appleNonce) }
        }
    }

    func signInWithGoogle() async {
        await run { try await self.auth.signInWithGoogle() }
    }

    /// Shared error handling for the social flows.
    private func run(_ operation: @MainActor () async throws -> Void) async {
        isSocialBusy = true
        errorMessage = nil
        errorDetail = nil
        defer { isSocialBusy = false }
        do {
            try await operation()
        } catch WebAuthenticator.WebAuthError.cancelled {
            // user dismissed the sheet — not an error
        } catch let error as AppError {
            Log.error(error, in: Log.auth, context: "social-login")
            errorMessage = error.userMessage
            errorDetail = error.debugDescription
        } catch {
            Log.auth.error("social-login: \(String(describing: error), privacy: .public)")
            errorMessage = AppError.unknown(detail: "").userMessage
            errorDetail = String(describing: error)
        }
    }

    var canSubmit: Bool {
        !isSubmitting && email.contains("@") && password.count >= 6
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        errorDetail = nil
        defer { isSubmitting = false }
        do {
            try await auth.signIn(email: email, password: password)
        } catch let error as AppError {
            Log.error(error, in: Log.auth, context: "login")
            errorMessage = error.userMessage
            errorDetail = error.debugDescription
        } catch {
            Log.auth.error("login: \(String(describing: error), privacy: .public)")
            errorMessage = AppError.unknown(detail: "").userMessage
            errorDetail = String(describing: error)
        }
    }
}
