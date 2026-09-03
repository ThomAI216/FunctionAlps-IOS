import AuthenticationServices
import Foundation
import UIKit

/// Runs the system browser sheet for OAuth and returns the redirect URL.
/// Cookies are shared with Safari (`prefersEphemeralWebBrowserSession = false`)
/// so a member already signed into Google is one tap away.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum WebAuthError: Error { case cancelled, noCallback }

    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let error {
                    if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                        continuation.resume(throwing: WebAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AppError.network(detail: error.localizedDescription))
                    }
                    return
                }
                guard let callback else { continuation.resume(throwing: WebAuthError.noCallback); return }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AppError.unknown(detail: "web auth session failed to start"))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

/// Parses `functionalps://auth/callback?code=…` (or `?error=…&error_description=…`).
enum OAuthCallback {
    static func code(from url: URL) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value ?? error
            throw AppError.validation(message: description.replacingOccurrences(of: "+", with: " "))
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AppError.decoding(detail: "callback without code: \(url.absoluteString)")
        }
        return code
    }
}
