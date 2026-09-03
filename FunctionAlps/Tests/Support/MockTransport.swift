import Foundation
@testable import FunctionAlps

/// Records requests and replays scripted responses. Thread-safe for concurrent callers.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) throws -> HTTPResponse

    private let lock = NSLock()
    private var handlers: [Handler]
    private(set) var requests: [HTTPRequest] = []
    /// Optional artificial latency so concurrency tests can overlap calls.
    var delayNanoseconds: UInt64 = 0

    init(_ handlers: [Handler] = []) {
        self.handlers = handlers
    }

    func enqueue(_ handler: @escaping Handler) {
        lock.withLock { handlers.append(handler) }
    }

    func enqueue(status: Int, json: String) {
        enqueue { _ in HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(json.utf8)) }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        let handler = record(request)
        guard let handler else {
            return HTTPResponse(status: 599, headers: [:], body: Data("no scripted response".utf8))
        }
        return try handler(request)
    }

    /// Synchronous critical section (NSLock.lock/unlock are unavailable in async contexts).
    private func record(_ request: HTTPRequest) -> Handler? {
        lock.withLock {
            requests.append(request)
            return handlers.isEmpty ? nil : handlers.removeFirst()
        }
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }
}

enum Fixtures {
    static let environment = AppEnvironment(
        name: .development,
        supabaseURL: URL(string: "https://example.supabase.co")!,
        supabasePublishableKey: "sb_publishable_test",
        apiBaseURL: nil
    )

    static func tokenJSON(access: String = "access-1", refresh: String = "refresh-1", expiresAt: Double = 4_102_444_800, userId: String = "11111111-2222-3333-4444-555555555555") -> String {
        """
        {"access_token":"\(access)","token_type":"bearer","expires_in":3600,"expires_at":\(Int(expiresAt)),"refresh_token":"\(refresh)","user":{"id":"\(userId)","email":"member@example.com","aud":"authenticated","created_at":"2026-01-01T00:00:00.000000Z"}}
        """
    }

    static func session(access: String = "access-1", refresh: String = "refresh-1", expiresAt: Date) -> AuthSession {
        AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, userId: "11111111-2222-3333-4444-555555555555", email: "member@example.com")
    }
}
