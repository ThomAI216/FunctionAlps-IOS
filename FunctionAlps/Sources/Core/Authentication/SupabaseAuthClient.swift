import Foundation

/// Supabase Auth (GoTrue) over plain HTTPS. No vendor SDK, so the surface the app
/// depends on is four calls that any future FunctionAlps auth gateway can offer.
struct SupabaseAuthClient: Sendable {
    private let environment: AppEnvironment
    private let transport: any HTTPTransport

    init(environment: AppEnvironment, transport: any HTTPTransport) {
        self.environment = environment
        self.transport = transport
    }

    // MARK: Public API

    func signIn(email: String, password: String) async throws -> AuthSession {
        struct Body: Encodable { let email: String; let password: String }
        let url = endpoint("token", query: [URLQueryItem(name: "grant_type", value: "password")])
        let request = try HTTPRequest.json(.post, url, headers: baseHeaders(), body: Body(email: email, password: password))
        let response = try await transport.send(request)
        guard response.isSuccess else { throw Self.mapAuthError(response) }
        return try Self.session(from: response.body)
    }

    enum SignUpOutcome: Sendable, Equatable {
        /// Auto-confirmed project: the session is live.
        case signedIn(AuthSession)
        /// Confirmation email sent; sign in after the link.
        case confirmEmail
    }

    /// `POST /auth/v1/signup` with the Expo metadata (`first_name`, `last_name`, `phone` when given).
    func signUp(email: String, password: String, firstName: String, lastName: String, phone: String?) async throws -> SignUpOutcome {
        struct Meta: Encodable { let firstName: String; let lastName: String; let phone: String? }
        struct Body: Encodable { let email: String; let password: String; let data: Meta }
        let trimmedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(email: email, password: password, data: Meta(firstName: firstName, lastName: lastName, phone: (trimmedPhone?.isEmpty ?? true) ? nil : trimmedPhone))
        let request = try HTTPRequest.json(.post, endpoint("signup"), headers: baseHeaders(), body: body)
        let response = try await transport.send(request)
        guard response.isSuccess else { throw Self.mapAuthError(response) }
        // With "confirm email" on, GoTrue answers with the bare user (no access_token).
        if let obj = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any], obj["access_token"] == nil { return .confirmEmail }
        var session = try Self.session(from: response.body)
        session.firstName = firstName
        session.lastName = lastName
        return .signedIn(session)
    }

    /// `POST /auth/v1/recover` — always resolves, so the UI never leaks whether the address exists.
    func recover(email: String) async {
        struct Body: Encodable { let email: String }
        guard let request = try? HTTPRequest.json(.post, endpoint("recover"), headers: baseHeaders(), body: Body(email: email)) else { return }
        _ = try? await transport.send(request)
    }

    /// RPC `email_exists(p_email)` under the publishable key (no session yet). nil = could not tell.
    func emailExists(_ email: String) async -> Bool? {
        struct Body: Encodable { let pEmail: String }
        var headers = baseHeaders()
        headers["Content-Type"] = "application/json"
        let url = environment.supabaseURL.appending(path: "rest/v1/rpc/email_exists")
        guard let request = try? HTTPRequest.json(.post, url, headers: headers, body: Body(pEmail: email)) else { return nil }
        guard let response = try? await transport.send(request), response.isSuccess else { return nil }
        let text = String(decoding: response.body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "true" ? true : text == "false" ? false : nil
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        struct Body: Encodable { let refreshToken: String }
        let url = endpoint("token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        let request = try HTTPRequest.json(.post, url, headers: baseHeaders(), body: Body(refreshToken: refreshToken))
        let response = try await transport.send(request)
        guard response.isSuccess else {
            // Any refresh failure other than connectivity means the session is dead.
            let mapped = Self.mapAuthError(response)
            if case .offline = mapped { throw mapped }
            throw AppError.unauthorized
        }
        return try Self.session(from: response.body)
    }

    /// The custom-scheme URL Supabase redirects to after a browser sign-in.
    /// Must be listed under Authentication → URL Configuration → Redirect URLs.
    static let oauthRedirectURL = URL(string: "functionalps://auth/callback")!

    /// Browser URL for an OAuth provider (Google) using PKCE.
    func authorizeURL(provider: String, codeChallenge: String) -> URL {
        endpoint("authorize", query: [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: Self.oauthRedirectURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ])
    }

    /// Exchanges the `code` from the redirect for a session (PKCE).
    func exchangeCode(_ authCode: String, codeVerifier: String) async throws -> AuthSession {
        struct Body: Encodable { let authCode: String; let codeVerifier: String }
        let url = endpoint("token", query: [URLQueryItem(name: "grant_type", value: "pkce")])
        let request = try HTTPRequest.json(.post, url, headers: baseHeaders(), body: Body(authCode: authCode, codeVerifier: codeVerifier))
        let response = try await transport.send(request)
        guard response.isSuccess else { throw Self.mapAuthError(response) }
        return try Self.session(from: response.body)
    }

    /// Native Sign in with Apple: the identity token + the raw nonce used in the request.
    func signInWithIdToken(provider: String, idToken: String, nonce: String?) async throws -> AuthSession {
        struct Body: Encodable { let provider: String; let idToken: String; let nonce: String? }
        let url = endpoint("token", query: [URLQueryItem(name: "grant_type", value: "id_token")])
        let request = try HTTPRequest.json(.post, url, headers: baseHeaders(), body: Body(provider: provider, idToken: idToken, nonce: nonce))
        let response = try await transport.send(request)
        guard response.isSuccess else { throw Self.mapAuthError(response) }
        return try Self.session(from: response.body)
    }

    func signOut(accessToken: String) async throws {
        let request = HTTPRequest(.post, endpoint("logout"), headers: baseHeaders(bearer: accessToken))
        let response = try await transport.send(request)
        // 204 on success; 401/403 means the token was already invalid — treat as signed out.
        guard response.isSuccess || response.status == 401 || response.status == 403 else {
            throw AppError.fromStatus(response.status, body: response.body)
        }
    }

    func user(accessToken: String) async throws -> AuthUser {
        let request = HTTPRequest(.get, endpoint("user"), headers: baseHeaders(bearer: accessToken))
        let response = try await transport.send(request)
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        return try JSON.decode(AuthUser.self, from: response.body)
    }

    // MARK: Wire format

    /// GoTrue token response. `expires_at` is epoch seconds; `user.id` is the auth user id.
    struct TokenResponse: Decodable {
        struct Metadata: Decodable {
            let patientId: String?
            let fullName: String?
            let name: String?
            let firstName: String?
            let lastName: String?
            let givenName: String?
            let familyName: String?
        }
        struct User: Decodable {
            let id: String
            let email: String?
            let userMetadata: Metadata?
        }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int?
        let expiresAt: Double?
        let user: User
    }

    static func session(from data: Data, now: Date = Date()) throws -> AuthSession {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token: TokenResponse
        do {
            token = try decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw AppError.decoding(detail: "token response: \(error)")
        }
        let expiresAt: Date
        if let epoch = token.expiresAt {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else {
            expiresAt = now.addingTimeInterval(TimeInterval(token.expiresIn ?? 3600))
        }
        let meta = token.user.userMetadata
        let display = [meta?.fullName, meta?.name, meta?.firstName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return AuthSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: expiresAt,
            userId: token.user.id,
            email: token.user.email,
            patientId: meta?.patientId,
            displayName: display,
            firstName: meta?.firstName ?? meta?.givenName,
            lastName: meta?.lastName ?? meta?.familyName
        )
    }

    /// GoTrue error bodies: new shape `{code, error_code, msg}`, legacy `{error, error_description}`.
    static func mapAuthError(_ response: HTTPResponse) -> AppError {
        let code = ErrorBody.errorCode(from: response.body) ?? ""
        let message = ErrorBody.message(from: response.body)
        switch (response.status, code) {
        case (400, "invalid_credentials"), (400, "invalid_grant"), (401, _):
            return .invalidCredentials
        case (400, "email_not_confirmed"):
            return .validation(message: String(localized: "auth.emailNotConfirmed", defaultValue: "Please confirm your email address first."))
        case (422, _), (400, _):
            return .validation(message: message ?? String(localized: "error.validation", defaultValue: "Please check what you entered."))
        case (429, _):
            return .validation(message: String(localized: "auth.rateLimited", defaultValue: "Too many attempts. Please wait a moment and try again."))
        default:
            return AppError.fromStatus(response.status, body: response.body)
        }
    }

    // MARK: Helpers

    private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: environment.supabaseURL.appending(path: "auth/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func baseHeaders(bearer: String? = nil) -> [String: String] {
        var headers = [
            "apikey": environment.supabasePublishableKey,
            "Accept": "application/json",
        ]
        headers["Authorization"] = "Bearer \(bearer ?? environment.supabasePublishableKey)"
        return headers
    }
}
