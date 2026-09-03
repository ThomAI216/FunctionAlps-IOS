import Foundation

/// Where the session lives at rest. Production = Keychain. Tests = memory.
protocol SessionStore: Sendable {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

struct KeychainSessionStore: SessionStore {
    private let keychain: Keychain
    private let account = "auth.session.v1"

    init(keychain: Keychain = Keychain()) {
        self.keychain = keychain
    }

    func load() throws -> AuthSession? {
        guard let data = try keychain.read(account) else { return nil }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            // A corrupt or old-format blob must not brick launch: drop it and sign in again.
            try? keychain.delete(account)
            return nil
        }
    }

    func save(_ session: AuthSession) throws {
        try keychain.write(try JSONEncoder().encode(session), account: account)
    }

    func clear() throws {
        try keychain.delete(account)
    }
}

/// In-memory store for unit tests and previews.
final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    init(session: AuthSession? = nil) {
        self.session = session
    }

    func load() throws -> AuthSession? {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    func save(_ session: AuthSession) throws {
        lock.lock(); defer { lock.unlock() }
        self.session = session
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        session = nil
    }
}
