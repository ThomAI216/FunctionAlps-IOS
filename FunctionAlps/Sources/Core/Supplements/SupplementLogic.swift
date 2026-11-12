import Foundation

/// The supplements' rules, pure and tested: which moment is "now", the rows Home shows, the written adherence,
/// the strip's marks. Every number is the server's (`member_supplements`); this only formats (rule 9).
enum SupplementLogic {
    // MARK: The current moment

    /// Home highlights one moment: the morning until 11:00, midday until 15:00, the evening until 21:00, then the night.
    static let middayStart = 11, eveningStart = 15, nightStart = 21

    static func currentMoment(hour: Int) -> SupplementMoment {
        if hour < middayStart { return .morning }
        if hour < eveningStart { return .noon }
        if hour < nightStart { return .evening }
        return .bedtime
    }

    static func currentMoment(at date: Date, calendar: Calendar = .current) -> SupplementMoment {
        currentMoment(hour: calendar.component(.hour, from: date))
    }

    // MARK: Dose

    /// "2 capsules" — the practice's own words when it wrote them, else the units and unit.
    static func doseText(_ s: Supplement) -> String? {
        if let text = s.doseText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        guard let units = s.unitsPerMoment, units > 0 else { return nil }
        let number = units == units.rounded() ? String(Int(units)) : String(units)
        let unit = s.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    /// "2 capsules · Night" — dose and moments, for the page's header.
    static func doseLine(_ s: Supplement) -> String {
        let moments = s.slots.map(\.displayName).joined(separator: ", ")
        guard let dose = doseText(s) else { return moments }
        return "\(dose) · \(moments)"
    }

    /// "Every other day" / "Only on set days"; nil when it is daily (nothing to say).
    static func rhythmText(_ s: Supplement) -> String? {
        switch s.rule {
        case .daily: nil
        case .alternate: String(localized: "supp.rhythm.alternate", defaultValue: "Every other day")
        case .weekdays: String(localized: "supp.rhythm.weekdays", defaultValue: "Only on set days")
        }
    }

    // MARK: Home rows

    /// One tick on Home: a supplement at one of its moments, today.
    struct Row: Sendable, Equatable, Identifiable {
        let supplementId: String
        let name: String
        let dose: String?
        let moment: SupplementMoment
        let taken: Bool
        /// The moment the clock is in — its rows are highlighted.
        let isCurrent: Bool
        var id: String { supplementId + "." + moment.rawValue }
    }

    /// Today's ticks: active supplements that are due today (the others stay hidden), one row per moment, in day order.
    static func rows(_ supplements: [Supplement], now: Date, calendar: Calendar = .current) -> [Row] {
        let current = currentMoment(at: now, calendar: calendar)
        var out: [Row] = []
        for s in supplements where s.isActive && s.dueToday {
            let dose = doseText(s)
            for moment in s.slots {
                out.append(Row(supplementId: s.id, name: s.name, dose: dose, moment: moment, taken: s.isTaken(moment), isCurrent: moment == current))
            }
        }
        return out.sorted { a, b in
            a.moment.rank != b.moment.rank ? a.moment.rank < b.moment.rank : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// "1 of 4 taken".
    static func progressText(_ rows: [Row]) -> String {
        let taken = rows.filter(\.taken).count
        return String(localized: "supp.home.progress", defaultValue: "\(taken) of \(rows.count) taken")
    }

    // MARK: Adherence

    /// The written adherence — always words, the colour is only an accent: "11 of 14 days" for a daily supplement,
    /// "4 of 7 due" for the others. Nil while nothing has been due yet.
    static func adherenceText(_ o: Supplement.Observance, rule: SupplementDaysRule) -> String? {
        if rule == .daily {
            guard o.days > 0 else { return nil }
            return String(localized: "supp.adherence.daily", defaultValue: "\(o.taken) of \(o.days) days")
        }
        guard o.due > 0 else { return nil }
        return String(localized: "supp.adherence.due", defaultValue: "\(o.taken) of \(o.due) due")
    }

    /// "79%" — the server's 0…1 as a whole percent; nil when it sent none.
    static func percentText(_ o: Supplement.Observance) -> String? {
        guard let pct = o.pct else { return nil }
        return "\(Int((min(max(pct, 0), 1) * 100).rounded()))%"
    }

    /// The same, spoken: "11 of 14 days, 79 percent".
    static func adherenceSpoken(_ o: Supplement.Observance, rule: SupplementDaysRule) -> String {
        let words = adherenceText(o, rule: rule) ?? String(localized: "supp.adherence.none", defaultValue: "Just getting started")
        guard let pct = o.pct else { return words }
        return words + ", " + String(localized: "supp.adherence.spoken", defaultValue: "\(Int((min(max(pct, 0), 1) * 100).rounded())) percent")
    }

    enum Band: String, Sendable { case red, orange, blue, green }

    static func band(_ o: Supplement.Observance) -> Band? { o.band.flatMap(Band.init(rawValue:)) }

    // MARK: The strip

    /// One day of the strip, by what happened. The shape (never only the colour) tells them apart.
    enum DayMark: Sendable, Equatable {
        /// Nothing due that day.
        case notDue
        /// Everything due was taken.
        case taken
        /// Some of the day's moments were taken.
        case partial
        /// Due and not taken.
        case missed
        /// Today, with something still to take.
        case pending
    }

    static func mark(_ day: Supplement.StripDay) -> DayMark {
        guard day.due else { return .notDue }
        let taken = day.moments.filter(\.taken).count
        if !day.moments.isEmpty, taken == day.moments.count { return .taken }
        if taken > 0 { return .partial }
        return day.today ? .pending : .missed
    }

    static func markWord(_ mark: DayMark) -> String {
        switch mark {
        case .notDue: String(localized: "supp.mark.notDue", defaultValue: "not due")
        case .taken: String(localized: "supp.mark.taken", defaultValue: "taken")
        case .partial: String(localized: "supp.mark.partial", defaultValue: "partly taken")
        case .missed: String(localized: "supp.mark.missed", defaultValue: "missed")
        case .pending: String(localized: "supp.mark.pending", defaultValue: "still to take")
        }
    }

    // MARK: Reminders line

    /// "Reminder at 22:00" · "Reminders at 08:00, 19:00" · "Reminders are off"; nil for an "any time" supplement
    /// (it has no moment to remind at) or a paused one.
    static func reminderLine(_ s: Supplement, prefs: NotificationPrefs) -> String? {
        let timed = s.slots.filter { SupplementMoment.timed.contains($0) }
        guard s.isActive, !timed.isEmpty else { return nil }
        guard prefs.supplementRemindersEnabled else { return String(localized: "supp.reminder.off", defaultValue: "Reminders are off") }
        let times = timed.map { prefs.supplementTimes.time(for: $0) }.joined(separator: ", ")
        return timed.count == 1
            ? String(localized: "supp.reminder.one", defaultValue: "Reminder at \(times)")
            : String(localized: "supp.reminder.many", defaultValue: "Reminders at \(times)")
    }

    // MARK: Lists

    /// The plan's list: active first (by their first moment, then name), paused last.
    static func planOrder(_ supplements: [Supplement]) -> [Supplement] {
        supplements.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            let ra = a.slots.first?.rank ?? 9, rb = b.slots.first?.rank ?? 9
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

/// The phone's supplement reminders as a pure plan: one grouped notification per moment that has something to
/// take — "Evening: Iberogast, Magnesium" — only on days something is due, never inside quiet hours, never for
/// a moment already ticked. The scheduler (`LocalNotifications`) turns this into requests.
///
/// What the phone can know: TODAY exactly (`due_today` and the ticks); the days after only for a daily
/// supplement. Alternate-day and set-day supplements join the plan on the day they are due (every launch and
/// every foreground re-plans). "Any time" supplements have no moment, so no reminder.
enum SupplementReminders {
    static let horizonDays = 3
    static let route = "functionalps://supplements"
    static let threadId = "supplements"

    /// What a grouped notification carries, so its "Taken" button can log each one without opening the app.
    struct Group: Sendable, Equatable {
        let moment: SupplementMoment
        let day: String
        let supplementIds: [String]
    }

    static func plan(supplements: [Supplement], prefs: NotificationPrefs, now: Date, calendar: Calendar = .current) -> [NotificationPlanner.Planned] {
        guard prefs.supplementRemindersEnabled else { return [] }
        let active = supplements.filter(\.isActive)
        guard !active.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var out: [NotificationPlanner.Planned] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = ISO8601.dayString(day, calendar: calendar)
            for moment in SupplementMoment.timed {
                let due = active.filter { s in
                    guard s.slots.contains(moment) else { return false }
                    return offset == 0 ? (s.dueToday && !s.isTaken(moment)) : s.rule == .daily
                }
                guard !due.isEmpty,
                      let minute = TrackLogic.minutes(prefs.supplementTimes.time(for: moment)) else { continue }
                let adjusted = TrackLogic.quietAdjusted(minute, moment: (moment == .evening || moment == .bedtime) ? .evening : .morning, prefs: prefs)
                guard let fireAt = calendar.date(byAdding: .minute, value: adjusted, to: day), fireAt > now else { continue }
                let ids = due.map(\.id)
                out.append(NotificationPlanner.Planned(
                    id: "supp.\(moment.rawValue).\(dayKey).\(TrackLogic.hhmm(adjusted).replacingOccurrences(of: ":", with: "")).\(checksum(ids))",
                    kind: .supplements, fireAt: fireAt,
                    title: title(moment: moment, supplements: due), body: body(due),
                    route: route, threadId: threadId,
                    extra: ["moment": moment.rawValue, "day": dayKey, "ids": ids.joined(separator: ",")]))
            }
        }
        return out.sorted { $0.fireAt < $1.fireAt }
    }

    /// "Evening: Iberogast, Magnesium".
    static func title(moment: SupplementMoment, supplements: [Supplement]) -> String {
        "\(moment.displayName): " + supplements.map(\.name).joined(separator: ", ")
    }

    /// One supplement → its dose ("20 drops before dinner"); several → how many.
    static func body(_ supplements: [Supplement]) -> String {
        if supplements.count == 1, let dose = SupplementLogic.doseText(supplements[0]) { return dose }
        if supplements.count == 1 { return String(localized: "supp.notif.body.one", defaultValue: "Time for your supplement.") }
        return String(localized: "supp.notif.body.many", defaultValue: "\(supplements.count) supplements to take.")
    }

    /// What a tapped "Taken" needs, read back from the notification's payload (`Planned.extra`); nil when it is not
    /// a supplement one.
    static func group(moment rawMoment: String?, day: String?, ids: String?) -> Group? {
        guard let rawMoment, let moment = SupplementMoment(rawValue: rawMoment), let day, let ids else { return nil }
        let list = ids.split(separator: ",").map(String.init)
        return list.isEmpty ? nil : Group(moment: moment, day: day, supplementIds: list)
    }

    /// FNV-1a over the ids, 8 hex digits: a changed set of supplements is a new request id, so the phone replaces
    /// the pending one instead of keeping its old text.
    static func checksum(_ ids: [String]) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in ids.joined(separator: ",").utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }
}
