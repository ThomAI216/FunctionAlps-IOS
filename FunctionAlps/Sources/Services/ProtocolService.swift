import Foundation

/// The Protocol Lens on the phone: the member's active protocols (5-minute cache, the Expo `protocol-load`),
/// the coached-only flags for a list of foods, and the week's wins-first summary. Every read is best effort —
/// a failed fetch reads as "no protocol" and the feature stays invisible for that interaction; it never blocks
/// a meal, a page or a save.
struct ProtocolService: Sendable {
    static let cacheTTL: TimeInterval = 5 * 60

    private let backend: any FunctionAlpsBackend
    private let cache = Cache()
    private let now: @Sendable () -> Date

    init(backend: any FunctionAlpsBackend, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    func active(patientId: String) async -> ProtocolData {
        if let hit = cache.get(patientId, now: now(), ttl: Self.cacheTTL) { return hit }
        do {
            let data = try await backend.activeProtocols(patientId: patientId)
            cache.set(patientId, data, at: now())
            return data
        } catch {
            Log.data.error("protocols.load: \(String(describing: error), privacy: .public)")
            return .none
        }
    }

    /// A sign-out / user switch must not leak the previous member's protocol state.
    func clear() { cache.clear() }

    /// The flags a COACHED surface may show for these foods: nil = the layer stays invisible (no protocol, or
    /// none coached); [] = a clean meal (the positive line). A flag surfaces only when its own protocol is coached.
    func coachedFlags(items: [String], data: ProtocolData) -> [ProtocolLens.Flag]? {
        guard ProtocolLens.effectiveVisibility(data.protocols) == .coached else { return nil }
        let strictness = ProtocolLens.strictness(of: data.protocols)
        return ProtocolLens.match(items: items, protocols: data.protocols, overrides: data.overrides)
            .filter { ProtocolLens.isFlagged($0, strictness: strictness) && ProtocolLens.visibility(of: $0.protocolKey, in: data.protocols) == .coached }
    }

    /// The Home card's week: flags tagged to a SILENT protocol are dropped before summarising; nil vs [] is kept.
    func week(meals: [MealLog], data: ProtocolData) -> ProtocolLens.Week {
        let rows: [[ProtocolLens.Flag]?] = meals.map { meal in
            meal.protocolFlags.map { $0.filter { ProtocolLens.visibility(of: $0.protocolKey, in: data.protocols) != .silent } }
        }
        return ProtocolLens.summarizeWeek(rows, strictness: ProtocolLens.strictness(of: data.protocols))
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entry: (patientId: String, at: Date, data: ProtocolData)?
        func get(_ patientId: String, now: Date, ttl: TimeInterval) -> ProtocolData? {
            lock.withLock {
                guard let e = entry, e.patientId == patientId, now.timeIntervalSince(e.at) < ttl else { return nil }
                return e.data
            }
        }
        func set(_ patientId: String, _ data: ProtocolData, at: Date) { lock.withLock { entry = (patientId, at, data) } }
        func clear() { lock.withLock { entry = nil } }
    }
}
