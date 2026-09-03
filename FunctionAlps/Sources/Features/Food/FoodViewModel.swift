import Foundation
import Observation

/// One capture, presented full-screen until the meal is read (or handed to the server).
struct CaptureRequest: Identifiable, Sendable {
    let id = UUID()
    let input: MealCaptureInput
}

@MainActor
@Observable
final class FoodViewModel {
    struct Content: Sendable, Equatable {
        let member: Member
        let meals: [MealLog]
    }

    struct DaySection: Identifiable, Equatable {
        let id: String
        let title: String
        let meals: [MealLog]
    }

    var state: Loadable<Content> = .loading
    var description = ""
    private(set) var isRefreshing = false

    private let members: MemberService
    private let meals: MealService
    private let auth: AuthService
    private let calendar: Calendar

    init(members: MemberService, meals: MealService, auth: AuthService, calendar: Calendar = .current) {
        self.members = members
        self.meals = meals
        self.auth = auth
        self.calendar = calendar
    }

    func load(refresh: Bool = false) async {
        if refresh { isRefreshing = true } else if state.value == nil { state = .loading }
        defer { isRefreshing = false }
        do {
            let member = try await members.currentMember()
            let recent = try await meals.recentMeals(patientId: member.patientId)
            state = .loaded(Content(member: member, meals: recent))
        } catch MemberService.MemberError.notRegistered {
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "food.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            Log.data.error("food.load: \(String(describing: error), privacy: .public)")
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    // MARK: Capture entry points

    var canDescribe: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Hands the typed meal to the capture flow and clears the field.
    func takeTextCapture() -> MealCaptureInput? {
        guard canDescribe else { return nil }
        let input = MealCaptureInput(description: description, source: .text)
        description = ""
        return input
    }

    func captureFinished() {
        Task { await load(refresh: true) }
    }

    // MARK: Derived

    func todayMeals(_ content: Content) -> [MealLog] {
        content.meals.filter { calendar.isDateInToday($0.loggedAt) }
    }

    func sections(_ content: Content) -> [DaySection] {
        var order: [String] = []
        var buckets: [String: [MealLog]] = [:]
        for meal in content.meals.sorted(by: { $0.loggedAt > $1.loggedAt }) {
            let day = ISO8601.dayString(meal.loggedAt, calendar: calendar)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(meal)
        }
        return order.map { day in
            DaySection(id: day, title: title(forDay: day, sample: buckets[day]?.first?.loggedAt), meals: buckets[day] ?? [])
        }
    }

    private func title(forDay day: String, sample: Date?) -> String {
        guard let sample else { return day }
        if calendar.isDateInToday(sample) { return String(localized: "day.today", defaultValue: "Today") }
        if calendar.isDateInYesterday(sample) { return String(localized: "day.yesterday", defaultValue: "Yesterday") }
        return sample.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
