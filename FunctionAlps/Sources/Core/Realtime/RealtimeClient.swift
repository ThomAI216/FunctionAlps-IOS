import Foundation

/// The lifecycle values a channel reports — the same four supabase-js hands `.subscribe(cb)`, so the watcher
/// logic ported from the Expo app reads unchanged.
enum RealtimeLifecycle: Sendable, Equatable { case subscribed, channelError, timedOut, closed }

/// A handle to a live channel. Cancelling closes the socket; cancelling twice is safe.
struct RealtimeSubscription: Sendable {
    private let onCancel: @Sendable () -> Void
    init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
    /// A subscription that never delivers — test stubs and preview wiring. The watcher's grace timer then
    /// falls back to polling, which is exactly the path a dead socket takes in production.
    static let inert = RealtimeSubscription(onCancel: {})
    func cancel() { onCancel() }
}

/// Opens Supabase Realtime channels. One socket per channel: a meal watch lives a couple of minutes at most,
/// and a shared multiplexed socket is complexity the app has no use for yet.
struct RealtimeClient: Sendable {
    private let environment: AppEnvironment
    private let sessions: SessionManager

    init(environment: AppEnvironment, sessions: SessionManager) {
        self.environment = environment
        self.sessions = sessions
    }

    /// `wss://<project>/realtime/v1/websocket?apikey=…&vsn=1.0.0` — the Phoenix JSON serializer (v1), which is
    /// what supabase-js speaks by default.
    var socketURL: URL? {
        guard var comps = URLComponents(url: environment.supabaseURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "wss"
        comps.path = "/realtime/v1/websocket"
        comps.queryItems = [URLQueryItem(name: "apikey", value: environment.supabasePublishableKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return comps.url
    }

    func channel(topic: String, change: RealtimeChannel.PostgresChange,
                 onRecord: @escaping @Sendable (Data) -> Void,
                 onLifecycle: @escaping @Sendable (RealtimeLifecycle) -> Void) -> RealtimeChannel {
        RealtimeChannel(url: socketURL, sessions: sessions, topic: topic, change: change, onRecord: onRecord, onLifecycle: onLifecycle)
    }
}

/// One Phoenix channel over one `URLSessionWebSocketTask`.
///
/// Join: `phx_join` on `realtime:<topic>` with the `postgres_changes` config and the member's JWT (RLS runs on
/// the socket — without the token the poll works and events never arrive, the first thing to check when a
/// watcher looks dead). `phx_reply` ok ⇒ `.subscribed`. Data arrives as `postgres_changes` events whose
/// `payload.data.record` is the NEW row; it is re-serialised and handed to the caller as JSON so the same
/// decoder that reads PostgREST reads it. A heartbeat on the `phoenix` topic every 30 s keeps the socket open.
/// Any error on the socket reports `.closed` once and stops — the watcher's poll fallback takes over; there is
/// no reconnect, because a meal watch is short and polling is a fine second transport.
final class RealtimeChannel: @unchecked Sendable {
    struct PostgresChange: Sendable {
        let event: String
        let schema: String
        let table: String
        let filter: String
    }

    static let heartbeatInterval: Duration = .seconds(30)
    static let joinTimeout: Duration = .seconds(10)

    private let url: URL?
    private let sessions: SessionManager
    private let topic: String
    private let change: PostgresChange
    private let onRecord: @Sendable (Data) -> Void
    private let onLifecycle: @Sendable (RealtimeLifecycle) -> Void

    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var joinWatchdog: Task<Void, Never>?
    private var nextRef = 1
    private var joinRef: String?
    private var joined = false
    private var stopped = false

    init(url: URL?, sessions: SessionManager, topic: String, change: PostgresChange,
         onRecord: @escaping @Sendable (Data) -> Void, onLifecycle: @escaping @Sendable (RealtimeLifecycle) -> Void) {
        self.url = url
        self.sessions = sessions
        self.topic = topic
        self.change = change
        self.onRecord = onRecord
        self.onLifecycle = onLifecycle
    }

    func start() {
        Task { [self] in
            guard let url else { finish(.channelError); return }
            let token: String
            do { token = try await sessions.validAccessToken() } catch { finish(.channelError); return }
            let opened: Bool = lock.withLock {
                guard !stopped, task == nil else { return false }
                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: url)
                self.session = session
                self.task = task
                task.resume()
                return true
            }
            guard opened else { return }
            let payload: [String: Any] = [
                "config": [
                    "broadcast": ["self": false],
                    "presence": ["key": ""],
                    "postgres_changes": [["event": change.event, "schema": change.schema, "table": change.table, "filter": change.filter]],
                ],
                "access_token": token,
            ]
            let ref = send(topic: "realtime:\(topic)", event: "phx_join", payload: payload)
            lock.withLock { joinRef = ref }
            receive()
            let beat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.heartbeatInterval)
                    guard !Task.isCancelled, let self else { return }
                    _ = self.send(topic: "phoenix", event: "heartbeat", payload: [:])
                }
            }
            let watchdog = Task { [weak self] in
                try? await Task.sleep(for: Self.joinTimeout)
                guard !Task.isCancelled, let self else { return }
                let pending = self.lock.withLock { !self.joined && !self.stopped }
                if pending { self.finish(.timedOut) }
            }
            let alreadyStopped: Bool = lock.withLock {
                heartbeat = beat
                joinWatchdog = watchdog
                return stopped
            }
            if alreadyStopped { beat.cancel(); watchdog.cancel() }
        }
    }

    func stop() {
        let (session, task, heartbeat, watchdog): (URLSession?, URLSessionWebSocketTask?, Task<Void, Never>?, Task<Void, Never>?) = lock.withLock {
            guard !stopped else { return (nil, nil, nil, nil) }
            stopped = true
            defer { self.session = nil; self.task = nil; self.heartbeat = nil; self.joinWatchdog = nil }
            return (self.session, self.task, self.heartbeat, self.joinWatchdog)
        }
        heartbeat?.cancel()
        watchdog?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    /// Report once, then close. Nothing is reported after `stop()`.
    private func finish(_ status: RealtimeLifecycle) {
        let report = lock.withLock { !stopped }
        guard report else { return }
        onLifecycle(status)
        stop()
    }

    @discardableResult
    private func send(topic: String, event: String, payload: [String: Any]) -> String {
        let (task, ref): (URLSessionWebSocketTask?, String) = lock.withLock {
            let r = String(nextRef)
            nextRef += 1
            return (stopped ? nil : self.task, r)
        }
        guard let task else { return ref }
        let message: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": ref]
        guard let data = try? JSONSerialization.data(withJSONObject: message), let text = String(data: data, encoding: .utf8) else { return ref }
        task.send(.string(text)) { [weak self] error in
            if error != nil { self?.finish(.closed) }
        }
        return ref
    }

    private func receive() {
        let task = lock.withLock { stopped ? nil : self.task }
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.finish(.closed)
            case .success(let message):
                switch message {
                case .string(let text): self.handle(Data(text.utf8))
                case .data(let data): self.handle(data)
                @unknown default: break
                }
                self.receive()
            }
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return }
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch event {
        case "phx_reply":
            let isJoin = lock.withLock { (object["ref"] as? String) == joinRef }
            guard isJoin else { return }
            if (payload["status"] as? String) == "ok" {
                let watchdog: Task<Void, Never>? = lock.withLock { joined = true; return joinWatchdog }
                watchdog?.cancel()
                onLifecycle(.subscribed)
            } else {
                finish(.channelError)
            }
        case "system":
            // Realtime confirms or refuses the postgres_changes extension separately from the join.
            if (payload["status"] as? String) == "error" { finish(.channelError) }
        case "postgres_changes":
            guard let inner = payload["data"] as? [String: Any], let record = inner["record"] as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: record) else { return }
            onRecord(json)
        case "phx_error":
            finish(.channelError)
        case "phx_close":
            finish(.closed)
        default:
            break
        }
    }
}
