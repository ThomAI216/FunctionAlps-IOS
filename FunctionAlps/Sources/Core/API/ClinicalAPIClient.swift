import Foundation

/// The CLINICAL web app's public library API (`FA_CLINICAL_API_URL`, https://dashboard.functionalps.ch) — where
/// "The FunctionAlps Show" is published. A second host next to CM OS, so it does NOT go through
/// `AuthorizedRequester`: a 401 from this host must never sign the member out of the app. The member's own
/// Supabase access token goes along as a Bearer token when there is a session; CLINICAL verifies it and only
/// then adds the member documents (research, article, guide, FAQ). No key, no secret.
struct ClinicalAPIClient: Sendable {
    private let baseURL: URL
    private let sessions: SessionManager
    private let transport: any HTTPTransport

    init(baseURL: URL, sessions: SessionManager, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.sessions = sessions
        self.transport = transport
    }

    /// `GET {base}/{path}` with `Accept: application/json` (+ the member's bearer when signed in). Any status comes
    /// back as is; the caller decides what a non-2xx means.
    func get(_ path: String) async throws -> HTTPResponse {
        var headers = ["Accept": "application/json"]
        if let token = try? await sessions.validAccessToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        return try await transport.send(HTTPRequest(.get, baseURL.appending(path: path), headers: headers))
    }
}
