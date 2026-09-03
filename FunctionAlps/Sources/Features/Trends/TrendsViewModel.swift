import Foundation
import Observation

@MainActor
@Observable
final class TrendsViewModel {
    var state: Loadable<MemberScores> = .loading
    var openPillar: MemberScores.Pillar?
    private(set) var isRefreshing = false

    private let backend: any FunctionAlpsBackend
    private let auth: AuthService
    private let calendar: Calendar

    init(backend: any FunctionAlpsBackend, auth: AuthService, calendar: Calendar = .current) {
        self.backend = backend
        self.auth = auth
        self.calendar = calendar
    }

    func load(refresh: Bool = false) async {
        if refresh { isRefreshing = true } else if state.value == nil { state = .loading }
        defer { isRefreshing = false }
        do {
            let offset = calendar.timeZone.secondsFromGMT(for: Date()) / 60
            state = .loaded(try await backend.memberScores(tzOffsetMinutes: offset))
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "trends.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            Log.data.error("trends.load: \(String(describing: error), privacy: .public)")
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    func toggle(_ pillar: MemberScores.Pillar) {
        openPillar = openPillar == pillar ? nil : pillar
    }
}
