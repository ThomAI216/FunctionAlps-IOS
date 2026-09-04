import AuthenticationServices
import Foundation
import Observation

/// The Expo `(auth)/login` flow: Google / Apple OR email → exists? → sign in | create account, with
/// forgot-password and the "check your inbox" states. Sign-up's consent tick gates account creation
/// only; the legal record is the consent gate on first authenticated launch (D-21).
@MainActor
@Observable
final class LoginViewModel {
    enum Flow: Equatable { case email, login, signup, signupDone, forgot, forgotSent }

    var flow: Flow = .email
    var email = ""
    /// The address the email step captured — read-only on the later steps, "change" goes back.
    private(set) var capturedEmail = ""
    var password = ""
    var confirmPassword = ""
    var firstName = ""
    var lastName = ""
    var phone = ""
    var consent = false
    var isSubmitting = false
    var errorMessage: String?
    /// Developer-facing cause, shown only in Debug/TestFlight builds.
    var errorDetail: String?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    // MARK: Social

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
            await run(social: true) { try await self.auth.signInWithApple(identityToken: token, nonce: self.appleNonce) }
        }
    }

    func signInWithGoogle() async {
        await run(social: true) { try await self.auth.signInWithGoogle() }
    }

    // MARK: Email-first

    var canContinue: Bool { !isSubmitting && OnboardingLogic.isEmailShaped(email) }

    /// exists → sign in; unknown or absent → create account (the "Already a member?" link keeps existing users one tap away).
    func continueWithEmail() async {
        let value = email.trimmingCharacters(in: .whitespaces)
        guard OnboardingLogic.isEmailShaped(value) else {
            errorMessage = String(localized: "login.invalidEmail", defaultValue: "Invalid email address.")
            return
        }
        errorMessage = nil
        errorDetail = nil
        isSubmitting = true
        let exists = await auth.emailExists(value)
        isSubmitting = false
        capturedEmail = value
        flow = exists == true ? .login : .signup
    }

    func backToEmail() {
        flow = .email
        email = capturedEmail
        password = ""
        confirmPassword = ""
        consent = false
        errorMessage = nil
        errorDetail = nil
    }

    func show(_ next: Flow) {
        errorMessage = nil
        errorDetail = nil
        flow = next
    }

    // MARK: Sign in

    var canSubmit: Bool { !isSubmitting && !password.isEmpty }

    func submit() async {
        guard !isSubmitting else { return }
        guard !password.isEmpty else {
            errorMessage = String(localized: "login.passwordRequired", defaultValue: "Password required.")
            return
        }
        await run(social: false) { try await self.auth.signIn(email: self.capturedEmail, password: self.password) }
    }

    // MARK: Sign up

    var passwordCheck: OnboardingLogic.PasswordCheck { OnboardingLogic.checkPassword(password) }
    var passwordsMatch: Bool { !confirmPassword.isEmpty && password == confirmPassword }
    var canSignUp: Bool {
        !isSubmitting && passwordCheck.ok && passwordsMatch && consent
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func signUp() async {
        guard canSignUp else { return }
        await run(social: false) {
            let outcome = try await self.auth.signUp(
                email: self.capturedEmail, password: self.password,
                firstName: self.firstName.trimmingCharacters(in: .whitespaces),
                lastName: self.lastName.trimmingCharacters(in: .whitespaces),
                phone: self.phone.trimmingCharacters(in: .whitespaces).nonEmpty
            )
            // A live session flips the app phase itself; the confirmation flow waits on the inbox.
            if case .confirmEmail = outcome { self.flow = .signupDone }
        }
    }

    // MARK: Forgot

    /// Always lands on "sent" — whether the address exists is not something this screen may reveal.
    func requestReset() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        await auth.requestPasswordReset(email: capturedEmail)
        isSubmitting = false
        show(.forgotSent)
    }

    // MARK: Shared error handling

    private func run(social: Bool, _ operation: @MainActor () async throws -> Void) async {
        if social { isSocialBusy = true } else { isSubmitting = true }
        errorMessage = nil
        errorDetail = nil
        defer { if social { isSocialBusy = false } else { isSubmitting = false } }
        do {
            try await operation()
        } catch WebAuthenticator.WebAuthError.cancelled {
            // user dismissed the sheet — not an error
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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
