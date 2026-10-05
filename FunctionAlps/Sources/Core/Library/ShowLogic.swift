import Foundation

/// The show's rules — pure, no IO, tested. The members web's `src/lib/show/{schedule,experiment,view,format}.ts`
/// (branch claude/library-show) line for line in spirit, so the phone and the dashboard agree on the next live,
/// the week, and which experiment day may be marked.
///
/// All wall-clock maths happen in the series' time zone (Europe/Zurich) through a Calendar set to that zone, never
/// in the phone's: "12:30" is 10:30Z in summer and 11:30Z in winter, whatever zone the member travels in.
enum ShowLogic {
    // MARK: The default week (owner, 2026-10-03)

    /// Live Monday and Saturday (45 min), one pillar a day Tuesday to Friday (30 min).
    static let defaultSchedule: [ShowSlot] = [
        ShowSlot(weekday: 1, kind: .live, track: .cross, minutes: 45),
        ShowSlot(weekday: 2, kind: .episode, track: .movement, minutes: 30),
        ShowSlot(weekday: 3, kind: .episode, track: .nutrition, minutes: 30),
        ShowSlot(weekday: 4, kind: .episode, track: .sleep, minutes: 30),
        ShowSlot(weekday: 5, kind: .episode, track: .mental, minutes: 30),
        ShowSlot(weekday: 6, kind: .live, track: .cross, minutes: 45),
    ]
    static let defaultTime = "12:30"
    static let defaultTimeZone = "Europe/Zurich"
    /// The first day of the show (Monday 5 October 2026). Nothing is scheduled before it.
    static let launchDay = "2026-10-05"
    /// The website has no page per event: its agenda lists them and holds the registration.
    static let eventsURL = URL(string: "https://functionalps.ch/events")!

    // MARK: Validation

    private static let lowercase: ClosedRange<Unicode.Scalar> = "a"..."z"
    private static let digits: ClosedRange<Unicode.Scalar> = "0"..."9"

    /// Event slugs are kebab-case (`^[a-z0-9][a-z0-9-]{0,159}$`); anything else never reaches a URL.
    static func isSlug(_ s: String) -> Bool {
        let scalars = s.unicodeScalars
        guard (1...160).contains(scalars.count), let first = scalars.first,
              lowercase.contains(first) || digits.contains(first) else { return false }
        return scalars.allSatisfy { lowercase.contains($0) || digits.contains($0) || $0 == "-" }
    }

    /// 'HH:MM' (00:00–23:59); anything else falls back to 12:30.
    static func safeTime(_ time: String?) -> String {
        guard let time, time.count == 5 else { return defaultTime }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCIIDigit) }),
              let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return defaultTime }
        return time
    }

    /// An IANA zone the system knows; anything else falls back to Zurich.
    static func safeTimeZone(_ tz: String?) -> String {
        guard let tz, !tz.isEmpty, TimeZone(identifier: tz) != nil else { return defaultTimeZone }
        return tz
    }

    /// Only absolute http(s) URLs reach a player or a link.
    static func httpURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    static func pubmedURL(_ pmid: String) -> URL? {
        let p = pmid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...9).contains(p.count), p.allSatisfy(\.isASCIIDigit) else { return nil }
        return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(p)/")
    }

    // MARK: Days ("YYYY-MM-DD", zone-free arithmetic)

    private struct YMD { let y: Int; let m: Int; let d: Int }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }()

    static func calendar(_ timeZone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(identifier: defaultTimeZone) ?? .gmt
        return c
    }

    private static func parts(_ day: String) -> YMD? {
        let p = day.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return YMD(y: y, m: m, d: d)
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    private static func dayString(_ c: DateComponents) -> String {
        "\(pad(c.year ?? 1970, 4))-\(pad(c.month ?? 1, 2))-\(pad(c.day ?? 1, 2))"
    }

    /// "YYYY-MM-DD" of `date` in `timeZone`.
    static func zonedDay(_ date: Date, timeZone: String = defaultTimeZone) -> String {
        dayString(calendar(timeZone).dateComponents([.year, .month, .day], from: date))
    }

    /// The instant at which the wall clock in `timeZone` reads `day` `time` (DST included).
    static func zonedDate(day: String, time: String, timeZone: String = defaultTimeZone) -> Date? {
        guard let p = parts(day) else { return nil }
        let hm = time.split(separator: ":")
        guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
        return calendar(timeZone).date(from: DateComponents(year: p.y, month: p.m, day: p.d, hour: h, minute: m))
    }

    static func addDays(_ day: String, _ n: Int) -> String {
        guard let p = parts(day), let base = utc.date(from: DateComponents(year: p.y, month: p.m, day: p.d)),
              let moved = utc.date(byAdding: .day, value: n, to: base) else { return day }
        return dayString(utc.dateComponents([.year, .month, .day], from: moved))
    }

    /// ISO weekday of a "YYYY-MM-DD" (1 = Monday … 7 = Sunday).
    static func isoWeekday(_ day: String) -> Int {
        guard let p = parts(day), let date = utc.date(from: DateComponents(year: p.y, month: p.m, day: p.d)) else { return 1 }
        let w = utc.component(.weekday, from: date) // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    static func monday(of day: String) -> String { addDays(day, 1 - isoWeekday(day)) }

    /// Noon UTC of a day — a Date that names the same calendar day in every zone (for display only).
    static func noon(_ day: String) -> Date {
        guard let p = parts(day) else { return Date(timeIntervalSince1970: 0) }
        return utc.date(from: DateComponents(year: p.y, month: p.m, day: p.d, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: The weekly clock

    struct Occurrence: Sendable, Equatable {
        let day: String
        let slot: ShowSlot
        let start: Date
        let end: Date
    }

    /// The slot scheduled on `day`, as an instant range; nil on a day off.
    static func occurrence(on day: String, clock: ShowClock) -> Occurrence? {
        guard let slot = clock.schedule.first(where: { $0.weekday == isoWeekday(day) }),
              let start = zonedDate(day: day, time: clock.time, timeZone: clock.timezone) else { return nil }
        return Occurrence(day: day, slot: slot, start: start, end: start.addingTimeInterval(Double(slot.minutes) * 60))
    }

    /// The moment the show begins (launch day, 00:00 in its zone).
    static func launch(_ clock: ShowClock) -> Date {
        zonedDate(day: launchDay, time: "00:00", timeZone: clock.timezone) ?? .distantPast
    }

    /// The next live from the schedule: the one running now, or the soonest to come; never before the launch.
    static func nextLive(clock: ShowClock, now: Date) -> Occurrence? {
        let launch = Self.launch(clock)
        let from = now < launch ? launch : now
        let first = zonedDay(from, timeZone: clock.timezone)
        for i in 0..<15 {
            guard let occ = occurrence(on: addDays(first, i), clock: clock), occ.slot.kind == .live else { continue }
            if occ.end > now && occ.start >= launch { return occ }
        }
        return nil
    }

    /// The show week to present: the current ISO week, or the launch week while the show has not started.
    static func week(clock: ShowClock, now: Date) -> (monday: String, days: [Occurrence], preLaunch: Bool) {
        let preLaunch = now < Self.launch(clock)
        let monday = Self.monday(of: preLaunch ? launchDay : zonedDay(now, timeZone: clock.timezone))
        let days = (0..<7).compactMap { occurrence(on: addDays(monday, $0), clock: clock) }
        return (monday, days, preLaunch)
    }

    static func inWeek(_ date: Date, monday: String, timeZone: String) -> Bool {
        let day = zonedDay(date, timeZone: timeZone)
        return day >= monday && day <= addDays(monday, 6)
    }

    // MARK: Experiment progress (member_lesson_progress, `show:<slug>:day:<n>`, track_id null)

    static let experimentPrefix = "show:"

    struct ExperimentMark: Sendable, Equatable {
        let day: Int
        /// The Zurich calendar day the mark was made ("" when unknown — never "today").
        let zurichDay: String
    }

    struct ExperimentState: Sendable, Equatable {
        /// Days marked done, ascending.
        let done: [Int]
        /// The next day to do; nil when every day is done.
        let nextDay: Int?
        /// A day was already marked today (one day per calendar day).
        let doneToday: Bool
    }

    static func experimentKey(slug: String, day: Int) -> String { "\(experimentPrefix)\(slug):day:\(day)" }

    static func parseExperimentKey(_ contentSlug: String) -> (slug: String, day: Int)? {
        guard contentSlug.hasPrefix(experimentPrefix) else { return nil }
        let rest = contentSlug.dropFirst(experimentPrefix.count)
        guard let r = rest.range(of: ":day:", options: .backwards) else { return nil }
        let slug = String(rest[..<r.lowerBound])
        let number = rest[r.upperBound...]
        guard isSlug(slug), (1...2).contains(number.count), number.allSatisfy(\.isASCIIDigit),
              let day = Int(number), (1...31).contains(day) else { return nil }
        return (slug: slug, day: day)
    }

    /// Every experiment mark, grouped by episode slug (rows that are not experiment keys are ignored).
    static func marks(from rows: [ShowProgressRow], timeZone: String = defaultTimeZone) -> [String: [ExperimentMark]] {
        var out: [String: [ExperimentMark]] = [:]
        for row in rows {
            guard let key = parseExperimentKey(row.contentSlug) else { continue }
            let day = row.completedAt.map { zonedDay($0, timeZone: timeZone) } ?? ""
            out[key.slug, default: []].append(ExperimentMark(day: key.day, zurichDay: day))
        }
        return out
    }

    /// Days are done in order, one per calendar day: the next day is the first one not marked, and it can be
    /// marked only if nothing was marked today.
    static func experimentState(_ marks: [ExperimentMark], dayNumbers: [Int], today: String) -> ExperimentState {
        let done = Set(marks.map(\.day))
        return ExperimentState(
            done: done.sorted(),
            nextDay: dayNumbers.first { !done.contains($0) },
            doneToday: marks.contains { $0.zurichDay == today }
        )
    }

    static func canMark(_ state: ExperimentState, day: Int) -> Bool { state.nextDay == day && !state.doneToday }

    /// "Remind me every day": one local reminder per remaining day at `hour` (the phone's own clock), the first
    /// one today when it is still ahead and today's day is not done yet, otherwise tomorrow.
    static func reminderPlan(days: [Int], state: ExperimentState, now: Date, calendar: Calendar, hour: Int = 9) -> [(day: Int, fireAt: Date)] {
        let remaining = days.filter { !state.done.contains($0) }
        guard !remaining.isEmpty,
              let todayFire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: now)) else { return [] }
        let shift = state.doneToday ? 1 : 0
        var out: [(day: Int, fireAt: Date)] = []
        for (i, day) in remaining.enumerated() {
            guard let fire = calendar.date(byAdding: .day, value: i + shift, to: todayFire), fire > now else { continue }
            out.append((day: day, fireAt: fire))
        }
        return out
    }

    // MARK: Display helpers

    /// "hh:mm:ss" / "mm:ss" → seconds; nil when malformed.
    static func chapterSeconds(_ start: String) -> Int? {
        let parts = start.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count, !values.dropFirst().contains(where: { $0 > 59 }) else { return nil }
        return values.reduce(0) { $0 * 60 + $1 }
    }

    /// "00:03:40" → "03:40", "01:02:03" → "1:02:03".
    static func chapterLabel(_ start: String) -> String {
        guard let s = chapterSeconds(start) else { return start }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h):\(pad(m, 2)):\(pad(sec, 2))" : "\(pad(m, 2)):\(pad(sec, 2))"
    }

    /// Whole minutes, rounded, never 0 for a real duration.
    static func durationMinutes(_ seconds: Int?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    enum Piece: String, Sendable, CaseIterable { case replay, research, article, experiment, faq }

    /// The pieces an episode carries, in the order the card lists them.
    static func pieces(_ has: ShowEpisodeHas, hasAudio: Bool) -> [Piece] {
        var out: [Piece] = []
        if hasAudio || has.video { out.append(.replay) }
        if has.research { out.append(.research) }
        if has.article { out.append(.article) }
        if has.guide { out.append(.experiment) }
        if has.faq { out.append(.faq) }
        return out
    }

    /// The Library topic (`library_topic_covers` key) whose cover illustrates a track. Mental wellbeing borrows the
    /// stress cover; the cross-pillar lives and health intelligence take the calm foundations one.
    static func trackTopic(_ track: ShowTrack?) -> String {
        guard let track else { return "foundations" }
        switch track {
        case .movement: return "mouvement"
        case .nutrition: return "nutrition"
        case .sleep: return "sommeil"
        case .mental: return "stress"
        case .intelligence, .cross: return "foundations"
        }
    }
}
