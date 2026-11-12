import Foundation
import Observation

/// The practice's signal explanations (`signal_explanations`), read once per launch and shared by the Trends rows, the
/// signal pages and the "About <signal>" pages. Fail-soft by design: with no content (no rows yet, the table not applied, no
/// network) every block that shows it is simply hidden and nothing else changes — the app never words an explanation itself.
@MainActor
@Observable
final class SignalContentService {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The newest approved explanation per signal, in the app's language (English when the practice has no French yet).
    private(set) var explanations: [String: SignalExplanation] = [:]

    @ObservationIgnored private let backend: any FunctionAlpsBackend
    @ObservationIgnored private let locale: @Sendable () -> String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var lastFailure: Date?

    /// After a failed read, a re-appearing screen tries again only once this long has passed.
    static let retryAfter: TimeInterval = 120

    init(backend: any FunctionAlpsBackend, locale: @escaping @Sendable () -> String = { TodayFocus.locale() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.locale = locale
        self.now = now
    }

    /// The content for one page, or nil — the caller hides what it feeds.
    func content(for key: String) -> SignalExplanation.Content? { explanations[key]?.content }

    /// Reads once per launch. A failed read is retried by the next screen that asks, not sooner than `retryAfter`.
    func loadIfNeeded() async {
        switch phase {
        case .loaded, .loading: return
        case .failed:
            if let lastFailure, now().timeIntervalSince(lastFailure) < Self.retryAfter { return }
        case .idle: break
        }
        await load()
    }

    /// The error state's "Try again".
    func reload() async { await load() }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        phase = .loading
        do {
            let wanted = locale()
            var rows = try await backend.signalExplanations(locale: wanted)
            // The practice may have English only for a signal: the member then reads that, never an empty page.
            if wanted != "en" {
                let have = Set(rows.map(\.signal))
                let english = try await backend.signalExplanations(locale: "en").filter { !have.contains($0.signal) }
                rows += english
            }
            explanations = SignalExplanation.newestPerSignal(rows.filter(\.content.isUsable))
            lastFailure = nil
            phase = .loaded
        } catch {
            Log.data.error("signals.load: \(String(describing: error), privacy: .public)")
            lastFailure = now()
            phase = .failed((error as? AppError)?.userMessage ?? AppError.unknown(detail: String(describing: error)).userMessage)
        }
    }
}
