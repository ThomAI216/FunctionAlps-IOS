import Foundation

/// Sends requests with a valid bearer token; on 401 refreshes once and retries once.
/// A second 401 surfaces as `.unauthorized`, which the app treats as "signed out".
struct AuthorizedRequester: Sendable {
    private let sessions: SessionManager
    private let transport: any HTTPTransport

    init(sessions: SessionManager, transport: any HTTPTransport) {
        self.sessions = sessions
        self.transport = transport
    }

    func send(_ build: @Sendable (_ accessToken: String) throws -> HTTPRequest) async throws -> HTTPResponse {
        let token = try await sessions.validAccessToken()
        let first = try await transport.send(try build(token))
        guard first.status == 401 else { return first }
        let refreshed = try await sessions.forceRefresh()
        let second = try await transport.send(try build(refreshed))
        if second.status == 401 {
            await sessions.clearLocal()
            throw AppError.unauthorized
        }
        return second
    }
}
