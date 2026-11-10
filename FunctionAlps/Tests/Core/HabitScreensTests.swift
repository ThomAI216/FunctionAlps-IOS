import Foundation
import Testing
@testable import FunctionAlps

@Suite("Habit screens — moments, the pack of three, streaks, the 14 dots, resources")
struct HabitScreensTests {
    // MARK: Fixtures

    private func action(_ key: String, _ moment: String, new: Bool = false, legacy: TrackMoment? = nil, reads: [String] = [], card: String? = nil) -> TrackAction {
        var a = TrackAction(key: key, moment: legacy ?? .day)
        a.momentV2 = moment
        a.isNew = new
        a.reads = reads
        a.habitBankId = card
        return a
    }

    private func raw(_ json: String) throws -> [ActionCardRow.RawLink] {
        try JSONDecoder().decode([ActionCardRow.RawLink].self, from: Data(json.utf8))
    }

    // MARK: Moment by the clock

    @Test("The moment follows the phone's hour: morning < 10:00, midday 10:00–14:00, afternoon to 18:00, evening after")
    func momentBoundaries() {
        #expect(DayMoment.current(hour: 0) == .morning)
        #expect(DayMoment.current(hour: 5) == .morning)
        #expect(DayMoment.current(hour: 9) == .morning)
        #expect(DayMoment.current(hour: 10) == .midday)
        #expect(DayMoment.current(hour: 13) == .midday)
        #expect(DayMoment.current(hour: 14) == .afternoon)
        #expect(DayMoment.current(hour: 17) == .afternoon)
        #expect(DayMoment.current(hour: 18) == .evening)
        #expect(DayMoment.current(hour: 23) == .evening)
    }

    @Test("The clock reads the phone's own calendar and zone")
    func momentFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let nine = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9, minute: 59))!
        let ten = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 0))!
        #expect(DayMoment.current(at: nine, calendar: calendar) == .morning)
        #expect(DayMoment.current(at: ten, calendar: calendar) == .midday)
    }

    @Test("moment_v2 wins; the legacy moment is the fallback, and 'day' sits with midday")
    func momentOfAnAction() {
        var a = TrackAction(key: "caffeine", moment: .day)
        a.momentV2 = "afternoon"
        #expect(a.dayMoment == .afternoon)
        a.momentV2 = nil
        #expect(a.dayMoment == .midday)
        let evening = TrackAction(key: "x", moment: .evening)
        #expect(evening.dayMoment == .evening)
        var unknown = TrackAction(key: "y", moment: .morning)
        unknown.momentV2 = "teatime"
        #expect(unknown.dayMoment == .morning)
    }

    @Test("A track_day action decodes moment_v2, and a row with only moment_v2 still decodes")
    func decodesMomentV2() throws {
        let json = """
        [{"day":8,"title_en":"Build your plate","actions":[
          {"key":"caffeine","moment":"day","moment_v2":"afternoon","title_en":"No caffeine after 16:00","new":false,"face":"standard"},
          {"key":"stretch","moment_v2":"evening","title_en":"Stretch"},
          {"key":"broken","moment":"never"}]}]
        """
        let days = try TrackJSON.decode([TrackDayWire].self, from: Data(json.utf8)).map(\.day)
        let actions = days[0].actions
        #expect(actions.map(\.key) == ["caffeine", "stretch"])
        #expect(actions[0].dayMoment == .afternoon)
        #expect(actions[0].moment == .day)
        #expect(actions[1].dayMoment == .evening)
        #expect(actions[1].moment == .evening)
    }

    // MARK: The pack

    private var midday: [TrackAction] {
        [action("a", "midday"), action("b", "midday"), action("c", "midday"), action("d", "midday"), action("e", "midday"), action("f", "midday", new: true)]
    }

    @Test("New habits lead their moment, the rest keep the practice's order")
    func newFirst() {
        let list = HabitPack.actions(midday + [action("m", "morning")], in: .midday)
        #expect(list.map(\.key) == ["f", "a", "b", "c", "d", "e"])
    }

    @Test("At most three at a time; the next three appear once those are done")
    func packProgression() {
        let ordered = HabitPack.actions(midday, in: .midday)   // f a b | c d e
        var done: Set<String> = []
        func visible() -> (shown: [String], more: Int) { let v = HabitPack.visible(ordered) { done.contains($0.key) }; return (v.shown.map(\.key), v.more) }
        #expect(visible() == (["f", "a", "b"], 3))
        done = ["f"]
        #expect(visible() == (["f", "a", "b"], 3))            // a ticked one stays until its run is done
        done = ["f", "a", "b"]
        #expect(visible() == (["c", "d", "e"], 0))            // the next run replaces it
        done = ["f", "a", "b", "c", "d"]
        #expect(visible() == (["c", "d", "e"], 0))
        done = Set(ordered.map(\.key))
        #expect(visible() == (["c", "d", "e"], 0))            // all done: the last run, all ticked
    }

    @Test("A run left half-done by skipping ahead keeps showing until everything in it is ticked")
    func packWithGaps() {
        let ordered = HabitPack.actions(midday, in: .midday)
        let v = HabitPack.visible(ordered) { ["a", "c"].contains($0.key) }
        #expect(v.shown.map(\.key) == ["f", "a", "b"])
        #expect(v.more == 3)
    }

    @Test("An empty moment shows nothing")
    func packEmpty() {
        let v = HabitPack.visible([]) { _ in false }
        #expect(v.shown.isEmpty)
        #expect(v.more == 0)
    }

    @Test("The card opens on the clock's moment; done (or empty), it moves on to the next later one; nothing later, it stays")
    func selection() {
        let actions = [action("m1", "morning"), action("m2", "morning"), action("e1", "evening"), action("n1", "midday")]
        var done: Set<String> = []
        func pick(_ hour: Int) -> DayMoment { HabitPack.selectedMoment(hour: hour, actions: actions) { done.contains($0.key) } }
        #expect(pick(8) == .morning)
        #expect(pick(11) == .midday)
        #expect(pick(15) == .evening)                 // afternoon has none: on to the evening
        done = ["m1", "m2"]
        #expect(pick(8) == .midday)                   // the morning is done: moves on
        done = ["m1", "m2", "n1"]
        #expect(pick(8) == .evening)
        done = ["m1", "m2", "n1", "e1"]
        #expect(pick(8) == .morning)                  // nothing later is open: it stays, ticked
        #expect(pick(20) == .evening)
        done = ["e1"]
        #expect(pick(20) == .evening)                 // an earlier moment's skipped habit is not carried
    }

    @Test("Segments list the moments that have habits, with their counts")
    func segments() {
        let s = HabitPack.segments(midday + [action("m", "morning"), action("e", "evening"), action("e2", "evening")])
        #expect(s.map(\.moment) == [.morning, .midday, .evening])
        #expect(s.map(\.count) == [1, 6, 2])
    }

    // MARK: Streaks

    @Test("Consecutive days done up to today; a miss breaks it")
    func streakRun() {
        #expect(HabitStreak.current(done: [4, 5, 6, 7], first: 4, last: nil, today: 7) == 4)
        #expect(HabitStreak.current(done: [4, 5, 7], first: 4, last: nil, today: 7) == 1)
        #expect(HabitStreak.current(done: [], first: 4, last: nil, today: 7) == 0)
    }

    @Test("Today not ticked yet does not break the run; yesterday missed does")
    func streakToday() {
        #expect(HabitStreak.current(done: [4, 5, 6], first: 4, last: nil, today: 7) == 3)
        #expect(HabitStreak.current(done: [4, 5], first: 4, last: nil, today: 7) == 0)
        #expect(HabitStreak.current(done: [4, 5, 6, 7], first: 4, last: nil, today: 7) == 4)
    }

    @Test("Days before the habit began never count, and a habit that ended counts up to its last day")
    func streakBounds() {
        #expect(HabitStreak.current(done: [1, 2, 3, 4, 5], first: 4, last: nil, today: 5) == 2)
        #expect(HabitStreak.current(done: [3, 4, 5, 6], first: 3, last: 6, today: 9) == 4)
        #expect(HabitStreak.current(done: [3, 4, 5], first: 3, last: 6, today: 9) == 0)
    }

    @Test("Done days and spans come from the recorded ticks and the days' lists")
    func doneAndSpan() {
        let activity: Set<TrackActivityItem> = [
            TrackActivityItem(day: 4, kind: .action, itemKey: "daylight"), TrackActivityItem(day: 5, kind: .action, itemKey: "daylight"),
            TrackActivityItem(day: 5, kind: .video, itemKey: "daylight"), TrackActivityItem(day: 5, kind: .action, itemKey: "other"),
        ]
        #expect(HabitStreak.doneDays(key: "daylight", activity: activity) == [4, 5])
        var d4 = TrackDay(day: 4, titleEn: "a"); d4.actions = [action("daylight", "morning")]
        var d5 = TrackDay(day: 5, titleEn: "b"); d5.actions = [action("daylight", "morning"), action("other", "evening")]
        var d6 = TrackDay(day: 6, titleEn: "c"); d6.actions = [action("other", "evening")]
        let span = HabitStreak.span(of: "daylight", in: [d4, d5, d6])
        #expect(span?.first == 4)
        #expect(span?.last == 5)
        #expect(HabitStreak.span(of: "nope", in: [d4]) == nil)
    }

    @Test("No streak card on a habit's first day")
    func firstDay() {
        #expect(!HabitStreak.showsStreak(first: 8, today: 8))
        #expect(HabitStreak.showsStreak(first: 8, today: 9))
    }

    // MARK: The 14 dots

    @Test("14 dots: done, missed, not yet, and outside the habit; today is marked")
    func dots() {
        let dots = HabitStreak.dots(done: [4, 5, 7, 8, 9], first: 4, last: nil, today: 10)
        #expect(dots.count == 14)
        #expect(dots.map(\.day) == Array(1...14))
        let states = dots.map(\.state)
        #expect(Array(states[0..<3]) == [.outside, .outside, .outside])      // before the habit
        #expect(states[3] == .done && states[4] == .done)                    // 4, 5
        #expect(states[5] == .missed)                                        // 6
        #expect(states[6] == .done && states[7] == .done && states[8] == .done)
        #expect(states[9] == .notYet)                                        // today, not ticked
        #expect(Array(states[10...]) == [.notYet, .notYet, .notYet, .notYet])
        #expect(dots.filter(\.isToday).map(\.day) == [10])
    }

    @Test("Today ticked reads done; a habit that ended shows its tail as outside")
    func dotsTodayDoneAndEnded() {
        let a = HabitStreak.dots(done: [3, 4, 5], first: 3, last: nil, today: 5)
        #expect(a[4].state == .done && a[4].isToday)
        let b = HabitStreak.dots(done: [3, 4, 5, 6], first: 3, last: 6, today: 8)
        #expect(b[6].state == .outside && b[13].state == .outside)
        #expect(b[6].isToday == false && b[7].isToday)
    }

    @Test("Past day 14 the window is the 14 days ending today")
    func dotsWindowAfterTrack() {
        #expect(HabitStreak.windowDays(today: 10) == 1...14)
        #expect(HabitStreak.windowDays(today: 14) == 1...14)
        #expect(HabitStreak.windowDays(today: 20) == 7...20)
        let dots = HabitStreak.dots(done: [19, 20], first: 1, last: nil, today: 20)
        #expect(dots.first?.day == 7 && dots.last?.day == 20 && dots.last?.state == .done)
    }

    // MARK: Resources

    @Test("resources decode articles, a video, benefits and moves; unknown kinds and malformed entries are ignored")
    func resourcesDecode() throws {
        let json = """
        [{"kind":"video","url":"https://www.youtube.com/watch?v=nzCaZQqAs9I","title":"Guided breathing, with Wim Hof","source":"youtube"},
         {"kind":"article","slug":"breathe-the-time-you-give-yourself","title":"Breathe: the time you give yourself"},
         {"kind":"benefits","items":["A calmer, clearer head","Energy without coffee", 7, ""]},
         {"kind":"moves","items":[{"dir":"down","label":"Stress"},{"dir":"up","label":"Focus"},{"dir":"sideways","label":"Odd"},{"label":"NoDir"}]},
         {"kind":"podcast","url":"https://example.com/p","title":"Ignored"},
         {"kind":"hologram","items":["x"]},
         {"kind":"article"},
         {"kind":"video","url":"http://insecure.example/v.mp4"},
         {"url":42,"kind":"article","slug":"survives-a-bad-field"}]
        """
        let r = HabitResources.decode(try raw(json))
        #expect(r.articles.map(\.slug) == ["breathe-the-time-you-give-yourself", "survives-a-bad-field"])
        #expect(r.articles.first?.title == "Breathe: the time you give yourself")
        #expect(r.video?.url.absoluteString == "https://www.youtube.com/watch?v=nzCaZQqAs9I")
        #expect(r.video?.title == "Guided breathing, with Wim Hof")
        #expect(r.benefits == ["A calmer, clearer head", "Energy without coffee"])
        #expect(r.moves.map(\.label) == ["Stress", "Focus"])
        #expect(r.moves.map(\.direction) == [.down, .up])
        #expect(r.moves.map(\.arrow) == ["↓", "↑"])
    }

    @Test("No resources, or only unknown kinds, is an empty page section, not an error")
    func resourcesEmpty() throws {
        #expect(HabitResources.decode(nil) == HabitResources())
        #expect(HabitResources.decode(try raw("[]")) == HabitResources())
        #expect(HabitResources.decode(try raw(#"[{"kind":"recipe","items":["a"]}]"#)) == HabitResources())
    }

    @Test("A whole habit_bank row still decodes with the new list kinds in resources")
    func cardRowDecodes() throws {
        let json = """
        {"id":"c1","title":"Protein at every meal","description":"A palm of protein at every meal.",
         "how_md":"1. Eggs\\n2. A palm","resources":[{"kind":"benefits","items":["Fuller for longer"]},{"kind":"moves","items":[{"dir":"down","label":"Cravings"}]},{"kind":"article","slug":"s","title":"T"}]}
        """
        let card = try JSON.decoder.decode(ActionCardRow.self, from: Data(json.utf8))
        let r = HabitResources.decode(card.resources)
        #expect(r.benefits == ["Fuller for longer"])
        #expect(r.moves.first?.label == "Cravings")
        // The Library's and the action card's reader still see only the kinds they know.
        #expect(ActionCardLogic.links(card.resources) == [.article(slug: "s", title: "T")])
    }

    // MARK: The page

    private func days() -> [TrackDay] {
        (1...14).map { n in
            var d = TrackDay(day: n, titleEn: "Day \(n)")
            if n >= 4 { var a = action("daylight", "morning", new: n == 4, reads: ["light", "the-3-2-1-rule"], card: "c1"); a.howEn = "Right when you wake up."; d.actions.append(a) }
            if n >= 8 { d.actions.append(action("protein", "midday", new: n == 8)) }
            return d
        }
    }

    private func card() -> ActionCardRow {
        var c = ActionCardRow(id: "c1", title: "Daylight first thing")
        c.description = "Daylight and fresh air, before your phone."
        c.howMd = "1. Right when you wake up\n2. Then 5 minutes outside"
        c.resources = try? raw(#"[{"kind":"article","slug":"light","title":"Light sets your body clock"},{"kind":"benefits","items":["More awake"]},{"kind":"moves","items":[{"dir":"up","label":"Energy"}]},{"kind":"video","url":"https://media.functionalps.ch/v.mp4","title":"Flow"}]"#)
        return c
    }

    private let library = [
        LibraryArticle(slug: "light", title: "Light sets your body clock", tags: ["article", "foundation-track", "day:4"]),
        LibraryArticle(slug: "the-3-2-1-rule", title: "The 3-2-1 rule", tags: ["article", "foundation-track", "day:11"]),
    ]

    @Test("The page assembles the card, the ticks, the reads (soft-locked from a later day) and the streak")
    func pageContent() throws {
        let activity: Set<TrackActivityItem> = [4, 5, 6, 8, 9].reduce(into: []) { $0.insert(TrackActivityItem(day: $1, kind: .action, itemKey: "daylight")) }
        let page = try #require(HabitPageContent.make(key: "daylight", days: days(), cards: ["c1": card()], activity: activity, today: 9, library: library, locale: "en"))
        #expect(page.title == "Daylight first thing")
        #expect(page.summary == "Daylight and fresh air, before your phone.")
        #expect(page.steps == ["Right when you wake up", "Then 5 minutes outside"])
        #expect(page.benefits == ["More awake"])
        #expect(page.moves.map(\.label) == ["Energy"])
        #expect(page.video?.title == "Flow")
        #expect(page.moment == .morning)
        #expect(page.firstDay == 4 && page.lastDay == nil)
        #expect(page.whenText == "Day 4 onwards")
        #expect(page.doneToday && page.canTick)
        #expect(page.streak?.run == 2)                       // 8, 9; day 7 was missed
        #expect(page.reads.map(\.slug) == ["light", "the-3-2-1-rule"])
        #expect(page.reads[0].opensOn == nil)
        #expect(page.reads[1].opensOn == 11)                 // a day still to come: soft-locked, title shown
        #expect(page.reads[1].title == "The 3-2-1 rule")
    }

    @Test("On the habit's first day there is no streak; without a card the page keeps only what the day lists")
    func pageFirstDay() throws {
        let page = try #require(HabitPageContent.make(key: "protein", days: days(), cards: [:], activity: [], today: 8, library: [], locale: "en"))
        #expect(page.streak == nil)
        #expect(!page.doneToday && page.canTick)
        #expect(page.steps.isEmpty && page.benefits.isEmpty && page.moves.isEmpty && page.video == nil)
    }

    @Test("An action the track does not list has no page")
    func pageMissing() {
        #expect(HabitPageContent.make(key: "nope", days: days(), cards: [:], activity: [], today: 8, library: [], locale: "en") == nil)
    }

    @Test("A moment's own words: the four names are never empty")
    func momentNames() {
        #expect(DayMoment.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(DayMoment.order == [.morning, .midday, .afternoon, .evening])
    }
}
