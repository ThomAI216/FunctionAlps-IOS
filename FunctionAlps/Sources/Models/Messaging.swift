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
            guard let date = MessageDayParser.formatter.date(from: day) else { return day }
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }
}

/// A library item the practice sent WITH a message (`patient_message_resources`, CLINICAL migration 277).
/// The card under the bubble, and the "From your practitioner" row of the Library. The member's RLS reads
/// approved rows only; the practice's Send is the approval of a published library item.
struct MessageResource: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case resource, action }
    let id: String
    let messageId: String
    /// `kb_nodes.slug` — opens in the library reader (`Route.read`).
    let slug: String
    let title: String
    let kind: Kind
    let createdAt: Date
    /// Stamped once by `member_mark_message_resource_opened`.
    let openedAt: Date?
}

/// Raw row of `patient_message_resources` (the member-readable columns).
struct MessageResourceRow: Decodable, Sendable {
    let id: String
    let messageId: String
    let librarySlug: String
    let title: String
    let kind: String?
    let createdAt: Date
    let openedAt: Date?

    var resource: MessageResource {
        MessageResource(id: id, messageId: messageId, slug: librarySlug, title: title,
                        kind: MessageResource.Kind(rawValue: kind ?? "") ?? .resource, createdAt: createdAt, openedAt: openedAt)
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
    /// What the practice sent with this message (empty for the member's own).
    var resources: [MessageResource] = []
    /// The personal mini track the practice sent with this message (`patient_tracks.origin_message_id`).
    var track: PersonalTrackSummary? = nil
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

/// "Your Pathway" — what grounds it (owner, 2026-11-05: "based on the consultation from this moment, and our
/// conversations on X, Y, Z"). Built only from what the member can already read: their own past appointment,
/// the days the practice sent them something, and the clinician's `objective_line`. No wording is invented.
struct PathwayIntro: Sendable, Equatable {
    enum Basis: Sendable, Equatable {
        case consultationAndConversations(consultation: Date, conversations: [Date])
        case conversations([Date])
        case consultation(Date)
        case none
    }
    let basis: Basis
    /// The clinician's own line (`care_plans.objective_line`), shown as "Your focus"; nil when unset.
    let focus: String?
}

enum PathwayLogic {
    /// At most this many conversation days are named; the most recent ones, oldest first.
    static let maxConversationDays = 3

    static func intro(consultation: Date?, sentAt: [Date], objective: String?, calendar: Calendar = .current) -> PathwayIntro {
        var seen = Set<Date>()
        let days = sentAt
            .map { calendar.startOfDay(for: $0) }
            .sorted(by: >)
            .filter { seen.insert($0).inserted }
            .prefix(maxConversationDays)
            .sorted()
        let focus = objective?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basis: PathwayIntro.Basis
        switch (consultation, days.isEmpty) {
        case let (c?, false): basis = .consultationAndConversations(consultation: c, conversations: Array(days))
        case (nil, false): basis = .conversations(Array(days))
        case let (c?, true): basis = .consultation(c)
        case (nil, true): basis = .none
        }
        return PathwayIntro(basis: basis, focus: (focus?.isEmpty ?? true) ? nil : focus)
    }

    /// The sentence under the title, in the member's language.
    static func sentence(_ basis: PathwayIntro.Basis) -> String? {
        func day(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }
        func days(_ ds: [Date]) -> String { ds.map(day).formatted(.list(type: .and)) }
        switch basis {
        case let .consultationAndConversations(c, ds):
            return String(localized: "pathway.basis.both", defaultValue: "Based on your consultation of \(day(c)) and our conversations of \(days(ds)).")
        case let .conversations(ds):
            return String(localized: "pathway.basis.conversations", defaultValue: "Based on our conversations of \(days(ds)).")
        case let .consultation(c):
            return String(localized: "pathway.basis.consultation", defaultValue: "Based on your consultation of \(day(c)).")
        case .none:
            return nil
        }
    }
}

enum MessagingLogic {
    static let maxLength = 5000

    /// Put each resource under its message, in the order they were sent. A resource whose message is not
    /// in the thread (older than the page, or withdrawn) is dropped: a card needs its bubble.
    static func attach(_ resources: [MessageResource], to messages: [PatientMessage]) -> [PatientMessage] {
        let byMessage = Dictionary(grouping: resources, by: \.messageId)
        return messages.map { m in
            var copy = m
            copy.resources = (byMessage[m.id] ?? []).sorted { $0.createdAt < $1.createdAt }
            return copy
        }
    }

    /// Put the track under the message it was sent with, and drop from that message's "Resources attached" the
    /// articles the track already holds (an item is never shown twice). A message with no track is untouched.
    static func attach(tracks: [PersonalTrack], to messages: [PatientMessage]) -> [PatientMessage] {
        let summaries = PersonalTrackLogic.summaries(tracks)
        return messages.map { m in
            guard let summary = summaries[m.id], !m.mine else { return m }
            var copy = m
            copy.track = summary
            copy.resources = PersonalTrackLogic.looseResources(m.resources, tracks: tracks)
            return copy
        }
    }

    /// The Library's "From your practitioner" row: newest first, one card per slug (the latest send wins).
    static func sentForLibrary(_ resources: [MessageResource]) -> [MessageResource] {
        var seen = Set<String>()
        return resources.sorted { $0.createdAt > $1.createdAt }.filter { seen.insert($0.slug).inserted }
    }

    /// The Library tab's badge and the Home nudge: items sent and never opened (one per slug).
    static func unopenedCount(_ resources: [MessageResource]) -> Int {
        sentForLibrary(resources).filter { $0.openedAt == nil }.count
    }

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

/// The fixed `yyyy-MM-dd` parser, built once (immutable after configuration; see `PlanDayParser`).
private enum MessageDayParser {
    nonisolated(unsafe) static let formatter: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser
    }()
}
