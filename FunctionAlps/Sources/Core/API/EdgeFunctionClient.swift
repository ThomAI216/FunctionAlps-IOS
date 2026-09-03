import Foundation

/// Calls the backend's server-side logic (today: Supabase Edge Functions at
/// `/functions/v1/{name}`). Business logic stays server-side (PRD §41).
struct EdgeFunctionClient: Sendable {
    private let environment: AppEnvironment
    private let requester: AuthorizedRequester

    init(environment: AppEnvironment, requester: AuthorizedRequester) {
        self.environment = environment
        self.requester = requester
    }

    func invoke<Body: Encodable & Sendable, Result: Decodable & Sendable>(_ name: String, body: Body, snakeCase: Bool = true) async throws -> Result {
        let data = try await invokeRaw(name, body: body, snakeCase: snakeCase)
        return try JSON.decode(Result.self, from: data)
    }

    /// The raw response body, for functions whose result the app does not model
    /// (it only needs to know the call was accepted). Edge functions speak camelCase,
    /// so callers usually pass `snakeCase: false`.
    @discardableResult
    func invokeRaw<Body: Encodable & Sendable>(_ name: String, body: Body, snakeCase: Bool = true) async throws -> Data {
        let url = environment.supabaseURL.appending(path: "functions/v1/\(name)")
        let response = try await requester.send { token in
            try HTTPRequest.json(.post, url, headers: [
                "apikey": environment.supabasePublishableKey,
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ], body: body, snakeCase: snakeCase)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        return response.body
    }
}

/// `{}` body for functions that take no input.
struct EmptyBody: Encodable, Sendable {}
