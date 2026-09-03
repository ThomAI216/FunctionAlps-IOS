import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    struct Content: Sendable, Equatable {
        let member: Member
        let today: TodaySnapshot
    }

    enum Blocker: Equatable { case notRegistered }

    var state: Loadable<Content> = .loading
    var blocker: Blocker?
    private(set) var isRefreshing = false

    private let members: MemberService
    private let dashboard: DashboardService
    private let auth: AuthService

    init(members: MemberService, dashboard: DashboardService, auth: AuthService) {
        self.members = members
        self.dashboard = dashboard
        self.auth = auth
    }

    func load(refresh: Bool = false) async {
        if refresh { isRefreshing = true } else if state.value == nil { state = .loading }
        defer { isRefreshing = false }
        do {
            let member = try await members.currentMember()
            let today = try await dashboard.today(patientId: member.patientId)
            blocker = nil
            state = .loaded(Content(member: member, today: today))
        } catch MemberService.MemberError.notRegistered {
            blocker = .notRegistered
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "home.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            Log.data.error("home.load: \(String(describing: error), privacy: .public)")
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "home.greeting.morning", defaultValue: "Good morning")
        case 12..<18: return String(localized: "home.greeting.afternoon", defaultValue: "Good afternoon")
        default: return String(localized: "home.greeting.evening", defaultValue: "Good evening")
        }
    }
}
