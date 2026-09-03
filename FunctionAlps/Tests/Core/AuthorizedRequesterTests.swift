import Foundation
import Testing
@testable import FunctionAlps

@Suite("AuthorizedRequester")
struct AuthorizedRequesterTests {
    @Test func retriesOnceAfter401() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(3600)))
        let transport = MockTransport()
        transport.enqueue(status: 401, json: #"{"message":"JWT expired"}"#)                       // first API call
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "access-2", refresh: "refresh-2")) // refresh
        transport.enqueue(status: 200, json: #"[{"ok":true}]"#)                                    // retry
        let manager = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store, now: { now })
        let requester = AuthorizedRequester(sessions: manager, transport: transport)

        let response = try await requester.send { token in
            HTTPRequest(.get, URL(string: "https://example.supabase.co/rest/v1/profiles")!, headers: ["Authorization": "Bearer \(token)"])
        }

        #expect(response.status == 200)
        #expect(transport.requests[0].headers["Authorization"] == "Bearer access-1")
        #expect(transport.requests[2].headers["Authorization"] == "Bearer access-2")
    }

    @Test func secondUnauthorizedSignsOut() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(3600)))
        let transport = MockTransport()
        transport.enqueue(status: 401, json: "{}")
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "access-2"))
        transport.enqueue(status: 401, json: "{}")
        let manager = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store, now: { now })
        let requester = AuthorizedRequester(sessions: manager, transport: transport)

        await #expect(throws: AppError.unauthorized) {
            _ = try await requester.send { token in
                HTTPRequest(.get, URL(string: "https://example.supabase.co/rest/v1/profiles")!, headers: ["Authorization": "Bearer \(token)"])
            }
        }
        #expect(try store.load() == nil)
    }
}
