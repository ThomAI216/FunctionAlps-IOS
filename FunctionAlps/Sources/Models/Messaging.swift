import Foundation

/// "Ask about this meal / this day" on a message. Exactly one of meal/day is ever set — the
/// DB CHECK constraint says the same (the Expo `lib/messaging/message-context.ts`).
enum MessageContext: Sendable, Equatable {
    case meal(id: String)
    case day(String) // YYYY-MM-DD

    var columns: (kind: String?, mealId: String?, day: String?) {
        switch self {
        case .meal(let id): return ("meal", id, nil)
        case .day(let day): return ("day", nil, day)
        }
    }

    /// A 'meal' row whose meal id is null = the meal was deleted (FK SET NULL) → no context.
    static func from(kind: String?, mealId: String?, day: String?) -> MessageContext? {
        if kind == "meal", let mealId, !mealId.isEmpty { return .meal(id: mealId) }
        if kind == "day", let day, !day.isEmpty { return .day(day) }
        return nil
    }

    func chipLabel(mealName: String?) -> String {
        switch self {
        case .meal:
            let name = mealName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? String(localized: "messages.context.meal", defaultValue: "A meal you logged") : name
        case .day(let day):
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd"
            guard let date = parser.date(from: day) else { return day }
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }
}

/// One `patient_messages` row as the member sees it.
struct PatientMessage: Sendable, Equatable, Identifiable {
    let id: String
    /// true when the member sent it (`sender_type == 'patient'`).
    let mine: Bool
    let text: String
    let createdAt: Date
    /// A clinician message the member has not read yet.
    let unread: Bool
    let context: MessageContext?
}

/// Raw row, the PATIENT-readable columns only (never `*` — the table also carries the clinician's
/// unsent `ai_draft_*` columns and RLS is row-scoped, not column-scoped).
struct PatientMessageRow: Decodable, Sendable {
    let id: String
    let senderType: String?
    let body: String?
    let createdAt: Date
    let readByPatientAt: Date?
    let contextKind: String?
    let contextMealId: String?
    let contextDay: String?

    var message: PatientMessage {
        let sender = senderType ?? ""
        return PatientMessage(
            id: id,
            mine: sender == "patient",
            text: body ?? "",
            createdAt: createdAt,
            unread: sender == "clinician" && readByPatientAt == nil,
            context: MessageContext.from(kind: contextKind, mealId: contextMealId, day: contextDay)
        )
    }
}

enum MessagingLogic {
    static let maxLength = 5000

    static func validate(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    struct DayGroup: Sendable, Equatable, Identifiable {
        let label: String
        let items: [PatientMessage]
        var id: String { label + (items.first?.id ?? "") }
    }

    /// Calendar-day sections, oldest first, items oldest first (the Expo `groupByDay`).
    static func groupByDay(_ messages: [PatientMessage], now: Date = Date(), calendar: Calendar = .current) -> [DayGroup] {
        var order: [Date] = []
        var byDay: [Date: [PatientMessage]] = [:]
        for m in messages {
            let key = calendar.startOfDay(for: m.createdAt)
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(m)
        }
        return order.sorted().map { day in
            let items = (byDay[day] ?? []).sorted { $0.createdAt < $1.createdAt }
            let label: String
            if calendar.isDateInToday(day) { label = String(localized: "messages.day.today", defaultValue: "Today") }
            else if calendar.isDateInYesterday(day) { label = String(localized: "messages.day.yesterday", defaultValue: "Yesterday") }
            else { label = day.formatted(.dateTime.day().month(.abbreviated).year()) }
            return DayGroup(label: label, items: items)
        }
    }
}
