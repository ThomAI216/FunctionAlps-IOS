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
