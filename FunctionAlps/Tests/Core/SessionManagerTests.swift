import Foundation
import Testing
@testable import FunctionAlps

@Suite("SessionManager")
struct SessionManagerTests {
    private func make(store: InMemorySessionStore, transport: MockTransport, now: Date) -> SessionManager {
        SessionManager(
            auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport),
            store: store,
            now: { now }
        )
    }

    @Test func restoreReturnsPersistedSession() async {
        let now = Date()
        let stored = Fixtures.session(expiresAt: now.addingTimeInterval(3600))
        let manager = make(store: InMemorySessionStore(session: stored), transport: MockTransport(), now: now)
        let restored = await manager.restore()
        #expect(restored == stored)
    }

    @Test func freshTokenIsReturnedWithoutNetwork() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(3600)))
        let transport = MockTransport()
        let manager = make(store: store, transport: transport, now: now)
        let token = try await manager.validAccessToken()
        #expect(token == "access-1")
        #expect(transport.requestCount == 0)
    }

    @Test func expiringTokenIsRefreshedAndPersisted() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(10)))
        let transport = MockTransport()
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "access-2", refresh: "refresh-2"))
        let manager = make(store: store, transport: transport, now: now)

        let token = try await manager.validAccessToken()

        #expect(token == "access-2")
        #expect(try store.load()?.refreshToken == "refresh-2")
        #expect(transport.requestCount == 1)
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(10)))
        let transport = MockTransport()
        transport.delayNanoseconds = 50_000_000
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "access-2", refresh: "refresh-2"))
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "access-3", refresh: "refresh-3"))
        let manager = make(store: store, transport: transport, now: now)

        async let a = manager.validAccessToken()
        async let b = manager.validAccessToken()
        let (ta, tb) = try await (a, b)

        #expect(ta == "access-2")
        #expect(tb == "access-2")
        #expect(transport.requestCount == 1)
    }

    @Test func rejectedRefreshClearsSession() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(10)))
        let transport = MockTransport()
        transport.enqueue(status: 400, json: #"{"error":"invalid_grant"}"#)
        let manager = make(store: store, transport: transport, now: now)

        await #expect(throws: AppError.unauthorized) {
            _ = try await manager.validAccessToken()
        }
        #expect(try store.load() == nil)
        let remaining = await manager.session
        #expect(remaining == nil)
    }

    @Test func offlineRefreshKeepsSession() async throws {
        let now = Date()
        let stored = Fixtures.session(expiresAt: now.addingTimeInterval(10))
        let store = InMemorySessionStore(session: stored)
        let transport = MockTransport()
        transport.enqueue { _ in throw AppError.offline }
        let manager = make(store: store, transport: transport, now: now)

        await #expect(throws: AppError.offline) {
            _ = try await manager.validAccessToken()
        }
        #expect(try store.load() == stored)
    }

    @Test func signOutClearsEvenIfServerFails() async throws {
        let now = Date()
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: now.addingTimeInterval(3600)))
        let transport = MockTransport()
        transport.enqueue { _ in throw AppError.offline }
        let manager = make(store: store, transport: transport, now: now)
        await manager.signOut()
        #expect(try store.load() == nil)
    }
}
