import Foundation
import Testing
@testable import FunctionAlps

/// A hand-moved clock so TTL tests never sleep.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date = date.addingTimeInterval(seconds); lock.unlock() }
}

private actor LoadCounter {
    private(set) var calls = 0
    func hit() { calls += 1 }
}

private func member(_ patientId: String, user: String = "user-1") -> Member {
    Member(userId: user, patientId: patientId, email: nil, displayName: "Alex", profile: nil)
}

@Suite("MemberCache")
struct MemberCacheTests {
    @Test func answersFromMemoryWithinTheTTLAndAsksAgainAfterIt() async throws {
        let clock = TestClock()
        let cache = MemberCache(ttl: 600, now: { clock.now })
        let counter = LoadCounter()
        let load: @Sendable () async throws -> Member = { await counter.hit(); return member("p1") }

        _ = try await cache.member(userId: "user-1", forceRefresh: false, load: load)
        _ = try await cache.member(userId: "user-1", forceRefresh: false, load: load)
        #expect(await counter.calls == 1)

        clock.advance(599)
        _ = try await cache.member(userId: "user-1", forceRefresh: false, load: load)
        #expect(await counter.calls == 1)

        clock.advance(2)
        _ = try await cache.member(userId: "user-1", forceRefresh: false, load: load)
        #expect(await counter.calls == 2)
    }

    @Test func concurrentCallersShareOneResolution() async throws {
        let cache = MemberCache(ttl: 600, now: { Date() })
        let counter = LoadCounter()
        let load: @Sendable () async throws -> Member = {
            await counter.hit()
            try await Task.sleep(for: .milliseconds(150))
            return member("p1")
        }
        let results = try await withThrowingTaskGroup(of: Member.self) { group in
            for _ in 0..<8 { group.addTask { try await cache.member(userId: "user-1", forceRefresh: false, load: load) } }
            var out: [Member] = []
            for try await m in group { out.append(m) }
            return out
        }
        #expect(results.count == 8)
        #expect(results.allSatisfy { $0.patientId == "p1" })
        #expect(await counter.calls == 1)
    }

    @Test func aDifferentUserNeverSeesAnotherUsersEntry() async throws {
        let cache = MemberCache(ttl: 600, now: { Date() })
        let a = try await cache.member(userId: "user-1", forceRefresh: false) { member("p1", user: "user-1") }
        let b = try await cache.member(userId: "user-2", forceRefresh: false) { member("p2", user: "user-2") }
        #expect(a.patientId == "p1")
        #expect(b.patientId == "p2")
    }

    @Test func invalidateAndForceRefreshBothAskAgain() async throws {
        let cache = MemberCache(ttl: 600, now: { Date() })
        let counter = LoadCounter()
        let load: @Sendable () async throws -> Member = { await counter.hit(); return member("p1") }
        _ = try await cache.member(userId: "user-1", forceRefresh: false, load: load)
        await cache.invalidate()
        _ = try await cache.member(userId: "user-1", forceRefresh: false, load: load)
        #expect(await counter.calls == 2)
        _ = try await cache.member(userId: "user-1", forceRefresh: true, load: load)
        #expect(await counter.calls == 3)
    }

    @Test func aFailureIsNotCached() async throws {
        let cache = MemberCache(ttl: 600, now: { Date() })
        do {
            _ = try await cache.member(userId: "user-1", forceRefresh: false) { throw AppError.offline }
            Issue.record("expected a throw")
        } catch {}
        let m = try await cache.member(userId: "user-1", forceRefresh: false) { member("p1") }
        #expect(m.patientId == "p1")
    }

    @Test func aResolutionStartedBeforeInvalidateIsNotStored() async throws {
        let cache = MemberCache(ttl: 600, now: { Date() })
        let counter = LoadCounter()
        let slow: @Sendable () async throws -> Member = {
            await counter.hit()
            try await Task.sleep(for: .milliseconds(100))
            return member("old")
        }
        async let first = cache.member(userId: "user-1", forceRefresh: false, load: slow)
        try await Task.sleep(for: .milliseconds(20))
        await cache.invalidate()
        _ = try await first
        let fresh = try await cache.member(userId: "user-1", forceRefresh: false) { member("new") }
        #expect(fresh.patientId == "new")
    }

    @Test func patientIdIsRememberedOnlyWhenTheServerConfirmsOne() async throws {
        let cache = MemberCache(ttl: 600, now: { Date() })
        let counter = LoadCounter()
        let none: @Sendable () async throws -> String? = { await counter.hit(); return nil }
        _ = try await cache.patientId(userId: "user-1", load: none)
        _ = try await cache.patientId(userId: "user-1", load: none)
        #expect(await counter.calls == 2)   // "nobody owns this yet" is re-asked, registration may follow
        let some: @Sendable () async throws -> String? = { await counter.hit(); return "p1" }
        _ = try await cache.patientId(userId: "user-1", load: some)
        _ = try await cache.patientId(userId: "user-1", load: some)
        #expect(await counter.calls == 3)
    }
}

@Suite("MemberService cache")
struct MemberServiceCacheTests {
    private func sessions(userId: String = "user-1") -> (SessionManager, InMemorySessionStore) {
        let store = InMemorySessionStore(session: AuthSession(
            accessToken: "a", refreshToken: "r", expiresAt: .distantFuture,
            userId: userId, email: "alex@example.com", patientId: nil, displayName: "Alex Ginsburg"
        ))
        return (SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport()), store: store), store)
    }

    @Test func secondCallDoesNotAskTheServerAgain() async throws {
        let (manager, _) = sessions()
        let backend = StubBackend()
        backend.patientId = "p1"
        let service = MemberService(sessions: manager, backend: backend)
        _ = try await service.currentMember()
        _ = try await service.currentMember()
        _ = try await service.patientId()
        #expect(backend.patientIdCalls == 1)
        // The server stays the source: an explicit refresh asks again, and its answer wins.
        backend.patientId = "p2"
        let refreshed = try await service.currentMember(forceRefresh: true)
        #expect(refreshed.patientId == "p2")
        #expect(backend.patientIdCalls == 2)
    }

    @Test func invalidateMakesTheNextCallAskAgain() async throws {
        let (manager, _) = sessions()
        let backend = StubBackend()
        backend.patientId = "p1"
        let service = MemberService(sessions: manager, backend: backend)
        _ = try await service.currentMember()
        await service.invalidate()
        _ = try await service.currentMember()
        #expect(backend.patientIdCalls == 2)
    }

    @Test func signedOutThrowsUnauthorizedEvenWithAWarmCache() async throws {
        let (manager, _) = sessions()
        let backend = StubBackend()
        backend.patientId = "p1"
        let service = MemberService(sessions: manager, backend: backend)
        _ = try await service.currentMember()
        await manager.clearLocal()
        await #expect(throws: AppError.unauthorized) { _ = try await service.currentMember() }
    }
}
