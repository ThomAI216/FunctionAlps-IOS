import Foundation

/// The four moments of the Foundation Track's habits card (Thomas, 2026-11-07): morning, midday (10:00–14:00),
/// afternoon, evening. The mockup fixes midday; the afternoon/evening boundary is 18:00, the evening the app already
/// uses (`HabitSlot.current`), and the morning runs up to 10:00 (the small hours still belong to the morning to come).
enum DayMoment: String, Sendable, Hashable, CaseIterable {
    case morning, midday, afternoon, evening

    static let order: [DayMoment] = [.morning, .midday, .afternoon, .evening]
    static let middayStart = 10, afternoonStart = 14, eveningStart = 18

    var rank: Int { Self.order.firstIndex(of: self) ?? 0 }

    /// The moment a phone-local hour (0…23) falls in.
    static func current(hour: Int) -> DayMoment {
        if hour < middayStart { return .morning }
        if hour < afternoonStart { return .midday }
        if hour < eveningStart { return .afternoon }
        return .evening
    }

    static func current(at date: Date, calendar: Calendar = .current) -> DayMoment {
        current(hour: calendar.component(.hour, from: date))
    }

    var label: String {
        switch self {
        case .morning: String(localized: "habit.moment.morning", defaultValue: "Morning")
        case .midday: String(localized: "habit.moment.midday", defaultValue: "Midday")
        case .afternoon: String(localized: "habit.moment.afternoon", defaultValue: "Afternoon")
        case .evening: String(localized: "habit.moment.evening", defaultValue: "Evening")
        }
    }
}

extension TrackAction {
    /// The moment the action belongs to: `moment_v2` when the practice wrote it, else the legacy `moment`
    /// (`day` = "during the day", which sits with midday).
    var dayMoment: DayMoment {
        if let v2 = momentV2.flatMap(DayMoment.init(rawValue:)) { return v2 }
        switch moment {
        case .morning: return .morning
        case .midday, .day: return .midday
        case .evening: return .evening
        }
    }
}

/// One tab of the habits card: a moment and how many habits it holds today.
struct HabitSegment: Sendable, Equatable, Identifiable {
    let moment: DayMoment
    let count: Int
    var id: DayMoment { moment }
}

/// The habits card's rules, pure and tested: which moment is on screen, which (at most three) habits it shows.
enum HabitPack {
    static let packSize = 3

    /// The actions of one moment in the order the card shows them: the day's new ones first, then the others as the
    /// practice listed them.
    static func actions(_ actions: [TrackAction], in moment: DayMoment) -> [TrackAction] {
        let inMoment = actions.filter { $0.dayMoment == moment }
        return inMoment.filter(\.isNew) + inMoment.filter { !$0.isNew }
    }

    /// The moments that have at least one action today, with how many.
    static func segments(_ actions: [TrackAction]) -> [HabitSegment] {
        DayMoment.order.compactMap { moment in
            let n = actions.filter { $0.dayMoment == moment }.count
            return n > 0 ? HabitSegment(moment: moment, count: n) : nil
        }
    }

    /// The moment the card opens on: the clock's moment while it still has something to do; once its pack is done (or it
    /// has none) the next later moment with something left; nothing left later: the clock's moment, all ticked.
    /// An earlier moment's skipped action is not carried forward.
    static func selectedMoment(hour: Int, actions: [TrackAction], isDone: (TrackAction) -> Bool) -> DayMoment {
        let now = DayMoment.current(hour: hour)
        func hasOpen(_ moment: DayMoment) -> Bool { actions.contains { $0.dayMoment == moment && !isDone($0) } }
        if hasOpen(now) { return now }
        return DayMoment.order.filter { $0.rank > now.rank }.first(where: hasOpen) ?? now
    }

    /// What the moment shows: the first run of three with something left to do (the ticked ones of that run stay,
    /// ticked); when every habit is done, the last run. `more` = how many wait behind the shown run.
    static func visible(_ ordered: [TrackAction], isDone: (TrackAction) -> Bool) -> (shown: [TrackAction], more: Int) {
        guard !ordered.isEmpty else { return ([], 0) }
        let runs = stride(from: 0, to: ordered.count, by: packSize).map { Array(ordered[$0..<min($0 + packSize, ordered.count)]) }
        let index = runs.firstIndex { run in run.contains { !isDone($0) } } ?? runs.count - 1
        let after = runs[(index + 1)...].reduce(0) { $0 + $1.count }
        return (runs[index], after)
    }
}
