import Foundation
import os

/// One meal of the member's day, as the schedule and the reminders know it (`member_meal_schedule.slot`).
/// Raw values ARE the database CHECK — change one only with a migration.
enum MealSlot: String, CaseIterable, Sendable, Identifiable {
    case breakfast
    case morningSnack = "morning_snack"
    case lunch
    case afternoonSnack = "afternoon_snack"
    case dinner

    var id: String { rawValue }
    var isSnack: Bool { self == .morningSnack || self == .afternoonSnack }

    /// The `nb_meal_logs.meal_type` a meal in this slot carries.
    var mealType: MealLog.MealType {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .morningSnack, .afternoonSnack: .snack
        }
    }

    /// The defaults Thomas set (spec §3.1). Mirrors `member_meal_schedule_seed()` — the server seeds, this is
    /// only what the phone shows before the first read lands.
    var defaultTime: String {
        switch self {
        case .breakfast: "08:00"
        case .morningSnack: "10:00"
        case .lunch: "12:00"
        case .afternoonSnack: "16:00"
        case .dinner: "20:00"
        }
    }

    var defaultEnabled: Bool { !isSnack }

    var localizedName: String {
        switch self {
        case .breakfast: String(localized: "meal.type.breakfast", defaultValue: "Breakfast")
        case .morningSnack: String(localized: "mealtimes.slot.morningSnack", defaultValue: "Morning snack")
        case .lunch: String(localized: "meal.type.lunch", defaultValue: "Lunch")
        case .afternoonSnack: String(localized: "mealtimes.slot.afternoonSnack", defaultValue: "Afternoon snack")
        case .dinner: String(localized: "meal.type.dinner", defaultValue: "Dinner")
        }
    }
}

/// One `member_meal_schedule` row: a slot on one ISO weekday (1 = Monday … 7 = Sunday).
struct MealScheduleEntry: Sendable, Equatable, Identifiable {
    /// Where the time came from — the practitioner reads this, and a later questionnaire may only overwrite
    /// the rows nobody chose (`default` / `intake` / `profile`, spec §3.3).
    enum Source: String, Sendable {
        case `default`, intake, profile, setup, questionnaire, member, learned
        case pillarObservation = "pillar_observation"

        /// Nothing the member picked on purpose.
        var isUnchosen: Bool { self == .default || self == .intake || self == .profile }
    }

    let slot: MealSlot
    let weekday: Int
    var enabled: Bool
    /// `HH:mm`, the member's wall clock. Kept while the slot is off, so switching it back restores it.
    var remindAt: String
    var source: Source
    var learningEnabled = true

    var id: String { "\(slot.rawValue).\(weekday)" }
}

/// The member's meal-reminder schedule: always all five slots on all seven days.
/// Pure — the planner schedules from it, the capture screen labels a meal from it, the editor edits it.
struct MealSchedule: Sendable, Equatable {
    private(set) var entries: [MealScheduleEntry]

    /// Any slot/day missing from `entries` is filled from the defaults, so a partial read never loses a day.
    init(entries: [MealScheduleEntry]) {
        var byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var all: [MealScheduleEntry] = []
        for weekday in 1...7 {
            for slot in MealSlot.allCases {
                let id = "\(slot.rawValue).\(weekday)"
                all.append(byId.removeValue(forKey: id)
                           ?? MealScheduleEntry(slot: slot, weekday: weekday, enabled: slot.defaultEnabled, remindAt: slot.defaultTime, source: .default))
            }
        }
        self.entries = all
    }

    static let defaults = MealSchedule(entries: [])

    /// ISO weekday (1 = Monday … 7 = Sunday) of `date`; `Calendar.weekday` is 1 = Sunday.
    static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        let w = calendar.component(.weekday, from: date)
        return (w + 5) % 7 + 1
    }

    /// The three groups the editor shows by default.
    enum Group: CaseIterable, Sendable {
        case weekdays, saturday, sunday
        var weekdays: [Int] {
            switch self {
            case .weekdays: [1, 2, 3, 4, 5]
            case .saturday: [6]
            case .sunday: [7]
            }
        }
    }

    func entry(_ slot: MealSlot, weekday: Int) -> MealScheduleEntry {
        entries.first { $0.slot == slot && $0.weekday == weekday }
            ?? MealScheduleEntry(slot: slot, weekday: weekday, enabled: slot.defaultEnabled, remindAt: slot.defaultTime, source: .default)
    }

    /// The day's switched-on slots, earliest first.
    func enabledEntries(weekday: Int) -> [MealScheduleEntry] {
        entries.filter { $0.weekday == weekday && $0.enabled }
            .sorted { Self.minutes($0.remindAt) < Self.minutes($1.remindAt) }
    }

    /// Whether every day in `weekdays` holds the same switch and time for `slot` (the editor says "varies" otherwise).
    func isUniform(_ slot: MealSlot, weekdays: [Int]) -> Bool {
        let values = weekdays.map { entry(slot, weekday: $0) }
        guard let first = values.first else { return true }
        return values.allSatisfy { $0.enabled == first.enabled && $0.remindAt == first.remindAt }
    }

    /// One edit applied to every day in `weekdays`, stamped with where it came from.
    mutating func set(_ slot: MealSlot, weekdays: [Int], enabled: Bool? = nil, remindAt: String? = nil, source: MealScheduleEntry.Source = .member) {
        for i in entries.indices where entries[i].slot == slot && weekdays.contains(entries[i].weekday) {
            var e = entries[i]
            if let enabled { e.enabled = enabled }
            if let remindAt, NotificationPrefs.parse(remindAt) != nil { e.remindAt = remindAt }
            guard e != entries[i] else { continue }
            e.source = source
            entries[i] = e
        }
    }

    /// The member looked at every row and said "these are my times" (the setup's Save): all rows become theirs.
    mutating func confirmAll(as source: MealScheduleEntry.Source) {
        for i in entries.indices { entries[i].source = source }
    }

    /// The rows that differ from `old` — exactly what a save writes.
    func changes(since old: MealSchedule) -> [MealScheduleEntry] {
        entries.filter { $0 != old.entry($0.slot, weekday: $0.weekday) }
    }

    /// True while nothing in it was picked by the member: the moment to offer the 20-second setup.
    var awaitsSetup: Bool { entries.allSatisfy { $0.source.isUnchosen } }

    // MARK: Which meal a moment belongs to

    /// The slot a meal at `date` belongs to, in the member's own day.
    ///
    /// The member's word wins: a meal typed breakfast / lunch / dinner IS that slot, whatever the clock says. A
    /// snack is the morning one before lunch and the afternoon one after. An untyped meal is placed by the
    /// member's times: the boundaries of the old fixed clock (breakfast before 11:00, lunch to 15:00, a snack
    /// to 18:00, then dinner) move with their lunch and dinner — lunch − 1 h, lunch + 3 h, dinner − 2 h — so
    /// the defaults reproduce the old clock exactly, and a member whose dinner is at 21:00 gets dinner from 19:00.
    /// A morning snack splits the morning only when it is switched on: a 10:00 default nobody asked for must
    /// not turn every 9:30 breakfast into a snack.
    func slot(forMealAt date: Date, type: MealLog.MealType?, calendar: Calendar) -> MealSlot {
        let weekday = Self.isoWeekday(of: date, calendar: calendar)
        let t = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let b = boundaries(weekday: weekday)
        switch type {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return t < b.lunchStart ? .morningSnack : .afternoonSnack
        case .other, nil:
            if t < b.lunchStart {
                let snack = entry(.morningSnack, weekday: weekday)
                if snack.enabled, t >= (Self.minutes(entry(.breakfast, weekday: weekday).remindAt) + Self.minutes(snack.remindAt)) / 2 { return .morningSnack }
                return .breakfast
            }
            if t < b.snackStart { return .lunch }
            if t < b.dinnerStart { return .afternoonSnack }
            return .dinner
        }
    }

    /// The capture default — the meal type the member most likely means at `date`.
    func mealType(at date: Date, calendar: Calendar) -> MealLog.MealType {
        slot(forMealAt: date, type: nil, calendar: calendar).mealType
    }

    private func boundaries(weekday: Int) -> (lunchStart: Int, snackStart: Int, dinnerStart: Int) {
        let breakfast = Self.minutes(entry(.breakfast, weekday: weekday).remindAt)
        let lunch = Self.minutes(entry(.lunch, weekday: weekday).remindAt)
        let dinner = Self.minutes(entry(.dinner, weekday: weekday).remindAt)
        let lunchStart = max(lunch - 60, (breakfast + lunch) / 2)
        let dinnerStart = max(dinner - 120, (lunch + dinner) / 2)
        let snackStart = min(lunch + 180, dinnerStart)
        return (lunchStart, max(snackStart, lunchStart), dinnerStart)
    }

    /// `HH:mm` → minutes since midnight (junk → 0; entries are validated on the way in).
    static func minutes(_ hhmm: String) -> Int {
        guard let p = NotificationPrefs.parse(hhmm) else { return 0 }
        return p.hour * 60 + p.minute
    }
}

/// The schedule as the rest of the app last saw it, readable from any isolation: `NotificationService` (main
/// actor) writes it, `MealService` (nonisolated) reads it for the capture default.
final class MealScheduleBox: Sendable {
    private let lock = OSAllocatedUnfairLock<MealSchedule?>(initialState: nil)

    var value: MealSchedule? { lock.withLock { $0 } }

    func set(_ schedule: MealSchedule?) { lock.withLock { $0 = schedule } }
}

// MARK: Wire (member_meal_schedule, snake_case via the coders)

/// A row as `member_meal_schedule_seed()` returns it and as the phone upserts it.
struct MealScheduleRow: Codable, Sendable, Equatable {
    var patientId: String?
    var slot: String
    var weekday: Int
    var enabled: Bool
    /// `'HH:MM:SS'` from PostgREST; written as `HH:mm:00`.
    var remindAt: String
    var source: String
    var learningEnabled: Bool?
    var updatedVia: String?

    /// Unknown slot values (a newer server) are skipped, never guessed.
    var entry: MealScheduleEntry? {
        guard let slot = MealSlot(rawValue: slot), (1...7).contains(weekday) else { return nil }
        return MealScheduleEntry(slot: slot, weekday: weekday, enabled: enabled,
                                 remindAt: NotificationPrefs.hhmm(remindAt, fallback: slot.defaultTime),
                                 source: MealScheduleEntry.Source(rawValue: source) ?? .default,
                                 learningEnabled: learningEnabled ?? true)
    }

    static func write(_ e: MealScheduleEntry, patientId: String) -> MealScheduleRow {
        MealScheduleRow(patientId: patientId, slot: e.slot.rawValue, weekday: e.weekday, enabled: e.enabled,
                        remindAt: e.remindAt + ":00", source: e.source.rawValue, learningEnabled: e.learningEnabled, updatedVia: "ios")
    }
}
