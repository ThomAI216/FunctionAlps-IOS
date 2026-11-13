import Foundation
import Observation

/// The Trends page's one shared read, with the window the member chose. The page and its detail pages (a signal,
/// a device, the shared patterns) all show the same loaded value, so a push never re-reads and the window control
/// means the same thing everywhere. One batch of reads covers 56 days — the chosen window and the one before it —
/// and a window change only re-counts what is already here (`TrendsEngine.page`); it never goes back to the network.
///
/// Reads are the member's own rows under RLS. Only the daily check-in read is essential; every other read fails
/// soft to "nothing logged" so one missing table cannot blank the page.
@MainActor
@Observable
final class TrendsService {
    enum Phase: Equatable {
        case idle, loading, loaded, empty
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var page: TrendsEngine.Page?
    private(set) var window: TrendWindow = .fortnight

    @ObservationIgnored private var raw: TrendsRaw?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private let backend: any FunctionAlpsBackend
    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let wearables: WearableService
    @ObservationIgnored private let members: MemberService?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date

    /// A re-appearing page re-reads only when what it holds is older than this.
    static let staleAfter: TimeInterval = 60

    init(backend: any FunctionAlpsBackend, auth: AuthService, wearables: WearableService, members: MemberService? = nil,
         calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.auth = auth
        self.wearables = wearables
        self.members = members
        self.calendar = calendar
        self.now = now
    }

    func setWindow(_ newWindow: TrendWindow) {
        guard newWindow != window else { return }
        window = newWindow
        rebuild()
    }

    /// Sign-out: nothing of the previous member stays on screen or in memory.
    func reset() {
        raw = nil
        page = nil
        loadedAt = nil
        phase = .idle
    }

    /// For a page opened straight onto a detail (a link): read once when nothing has been read yet.
    func loadIfNeeded() async {
        guard page == nil, !isLoading else { return }
        await load()
    }

    /// Back on a page that already holds data: re-read only when it has gone stale.
    func refreshIfStale() async {
        guard page != nil, let loadedAt, now().timeIntervalSince(loadedAt) > Self.staleAfter else { return }
        await load(refresh: true)
    }

    func load(refresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if page == nil { phase = .loading }
        do {
            guard let patientId = try await MemberService.patientId(via: members, backend: backend) else {
                phase = .empty
                return
            }
            raw = try await read(patientId: patientId)
            loadedAt = now()
            rebuild()
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "trends.load")
            if case .forbidden = error { await members?.invalidate() }
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if page == nil { phase = .failed(error.userMessage) }
        } catch {
            Log.data.error("trends.load: \(String(describing: error), privacy: .public)")
            if page == nil { phase = .failed(AppError.unknown(detail: String(describing: error)).userMessage) }
        }
    }

    private func rebuild() {
        guard let raw else { return }
        page = TrendsEngine.page(raw, window: window, calendar: calendar)
        phase = .loaded
    }

    // MARK: The reads

    private func read(patientId: String) async throws -> TrendsRaw {
        let current = now()
        let today = ISO8601.dayString(current, calendar: calendar)
        let since = HabitEngine.shift(today, by: -(TrendWindow.readDays - 1))
        let mealsSince = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(TrendWindow.month.days - 1), to: current) ?? current)
        let backend = self.backend

        async let checkinsRead = backend.dailyCheckins(patientId: patientId, since: since)
        async let momentsRead = backend.checkinMomentsRange(patientId: patientId, since: since)
        async let gutRead = backend.gutDays(patientId: patientId, since: since)
        async let planRead = backend.habitPlan(patientId: patientId, day: today, since: since)
        async let carePlanRead = backend.carePlan(patientId: patientId)
        async let mealsRead = backend.meals(patientId: patientId, since: mealsSince)
        async let reactionsRead = backend.mealReactions(patientId: patientId, since: mealsSince)
        async let nightRowsRead = backend.wearableSleepRows(patientId: patientId, since: since)
        async let wearableRead = backend.wearableDaily(patientId: patientId, since: since)
        async let accountsRead = backend.wearableVendorAccounts(patientId: patientId)
        async let patternsRead = backend.userPatterns(patientId: patientId)

        var raw = TrendsRaw(today: today)
        raw.checkins = try await checkinsRead
        raw.momentsByDay = (try? await momentsRead) ?? [:]
        raw.gutDays = (try? await gutRead) ?? []
        raw.plan = try? await planRead
        raw.supplementNames = (try? await carePlanRead)?.supplements.map(\.name) ?? []
        raw.meals = (try? await mealsRead) ?? []
        raw.reactions = (try? await reactionsRead) ?? [:]
        raw.wearableRows = (try? await wearableRead) ?? []
        raw.vendorAccounts = (try? await accountsRead) ?? []
        raw.patterns = (try? await patternsRead) ?? []
        raw.appleHealthConnected = wearables.isConnected
        raw.appleHealthLastSync = wearables.lastSyncAt

        // One night per day, the richest source's. Apple Health on this phone fills today when the server has no night yet.
        let nightRows = (try? await nightRowsRead) ?? []
        var nights = Set(nightRows.map(\.day)).sorted().compactMap {
            WearableNightAssembler.night(from: nightRows, on: $0, fallback: calendar.timeZone)
        }
        if let local = await wearables.lastNight(now: current).map({ WearableNight(local: $0) }), !nights.contains(where: { $0.day == local.day }) {
            nights.append(local)
        }
        raw.nights = nights
        return raw
    }
}
