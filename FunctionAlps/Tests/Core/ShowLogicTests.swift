import Foundation
import Testing
@testable import FunctionAlps

@Suite("The show: schedule, experiment and display rules (one rulebook with the members web)")
struct ShowLogicTests {
    private func utc(_ iso: String) -> Date { ISO8601.parse(iso)! }

    // MARK: Days and the Zurich clock

    @Test func dayArithmetic() {
        #expect(ShowLogic.isoWeekday("2026-10-05") == 1)
        #expect(ShowLogic.isoWeekday("2026-10-10") == 6)
        #expect(ShowLogic.isoWeekday("2026-10-11") == 7)
        #expect(ShowLogic.addDays("2026-10-31", 1) == "2026-11-01")
        #expect(ShowLogic.addDays("2026-10-05", -1) == "2026-10-04")
        #expect(ShowLogic.monday(of: "2026-10-09") == "2026-10-05")
        #expect(ShowLogic.monday(of: "2026-10-11") == "2026-10-05")
        #expect(ShowLogic.monday(of: "2026-10-12") == "2026-10-12")
    }

    @Test func wallClockIsZurichWithDST() {
        // 12:30 in Zurich is 10:30Z in summer time and 11:30Z in winter time.
        #expect(ShowLogic.zonedDate(day: "2026-07-01", time: "12:30") == utc("2026-07-01T10:30:00Z"))
        #expect(ShowLogic.zonedDate(day: "2026-12-01", time: "12:30") == utc("2026-12-01T11:30:00Z"))
        // 22:30Z on 7 Oct is already 8 Oct in Zurich.
        #expect(ShowLogic.zonedDay(utc("2026-10-07T22:30:00Z")) == "2026-10-08")
        #expect(ShowLogic.zonedDay(utc("2026-10-07T21:30:00Z")) == "2026-10-07")
    }

    @Test func nextLiveBeforeTheLaunchIsTheLaunchMonday() throws {
        let occ = try #require(ShowLogic.nextLive(clock: .standard, now: utc("2026-10-03T08:00:00Z")))
        #expect(occ.day == "2026-10-05")
        #expect(occ.start == utc("2026-10-05T10:30:00Z"))
        #expect(occ.end == utc("2026-10-05T11:15:00Z"))
        #expect(occ.slot.kind == .live)
    }

    @Test func nextLiveAcrossTheAutumnDSTSwitch() throws {
        // Friday 23 Oct (summer time) → Saturday 24 Oct 12:30 CEST = 10:30Z.
        let before = try #require(ShowLogic.nextLive(clock: .standard, now: utc("2026-10-23T12:00:00Z")))
        #expect(before.start == utc("2026-10-24T10:30:00Z"))
        // Sunday 25 Oct, after the switch → Monday 26 Oct 12:30 CET = 11:30Z.
        let after = try #require(ShowLogic.nextLive(clock: .standard, now: utc("2026-10-25T10:00:00Z")))
        #expect(after.day == "2026-10-26")
        #expect(after.start == utc("2026-10-26T11:30:00Z"))
    }

    @Test func nextLiveAcrossTheSpringDSTSwitch() throws {
        // Saturday 27 Mar 2027, after its live (CET) → Monday 29 Mar 12:30 CEST = 10:30Z.
        let occ = try #require(ShowLogic.nextLive(clock: .standard, now: utc("2027-03-27T13:00:00Z")))
        #expect(occ.day == "2027-03-29")
        #expect(occ.start == utc("2027-03-29T10:30:00Z"))
    }

    @Test func aRunningLiveIsStillTheNextOne() throws {
        let running = try #require(ShowLogic.nextLive(clock: .standard, now: utc("2026-10-10T10:45:00Z")))
        #expect(running.day == "2026-10-10")
        let ended = try #require(ShowLogic.nextLive(clock: .standard, now: utc("2026-10-10T11:16:00Z")))
        #expect(ended.day == "2026-10-12")
    }

    @Test func theWeekBeforeTheLaunchIsTheLaunchWeek() {
        let week = ShowLogic.week(clock: .standard, now: utc("2026-10-03T08:00:00Z"))
        #expect(week.preLaunch)
        #expect(week.monday == "2026-10-05")
        #expect(week.days.count == 6)
        #expect(week.days.first?.slot.kind == .live)
        #expect(week.days.map(\.slot.track) == [.cross, .movement, .nutrition, .sleep, .mental, .cross])
        let later = ShowLogic.week(clock: .standard, now: utc("2026-10-14T08:00:00Z"))
        #expect(!later.preLaunch)
        #expect(later.monday == "2026-10-12")
    }

    // MARK: The snapshot the Library renders

    @Test func emptyStateBeforeTheLaunch() throws {
        let lib = ShowLibrary(series: nil, episodes: [], upcoming: [])
        let snap = ShowSnapshot.build(lib, marks: [:], now: utc("2026-10-03T08:00:00Z"))
        #expect(snap.preLaunch)
        #expect(snap.thisWeek.isEmpty)
        #expect(snap.days.count == 6)
        #expect(snap.lives.count == 4)
        let live = try #require(snap.nextLive)
        #expect(live.start == utc("2026-10-05T10:30:00Z"))
        #expect(live.slug == nil)
        #expect(live.when == .later)
        // The day before, it reads "tomorrow".
        let eve = ShowSnapshot.build(lib, marks: [:], now: utc("2026-10-04T10:00:00Z"))
        #expect(eve.nextLive?.when == .tomorrow)
    }

    @Test func aWeekWithReplaysAndAPublishedLive() throws {
        let episodes = (6...9).map { d in
            ShowEpisodeCard(slug: "ep-\(d)", number: d - 5, title: ShowText(en: "Ep \(d)"), track: .movement,
                            startsAt: ShowLogic.zonedDate(day: "2026-10-0\(d)", time: "12:30")!, durationSeconds: 1800, audioURL: nil, has: ShowEpisodeHas())
        }
        let live = ShowUpcoming(slug: "live-10", kind: .live, number: nil, title: ShowText(en: "Review"), track: .cross,
                                startsAt: utc("2026-10-10T10:30:00Z"), endsAt: utc("2026-10-10T11:15:00Z"))
        let lib = ShowLibrary(series: nil, episodes: episodes, upcoming: [live])
        let marks = ["ep-6": [ShowLogic.ExperimentMark(day: 1, zurichDay: "2026-10-07")]]
        let snap = ShowSnapshot.build(lib, marks: marks, now: utc("2026-10-09T07:41:00Z"))
        #expect(!snap.preLaunch)
        #expect(snap.today == "2026-10-09")
        #expect(snap.thisWeek.map(\.slug) == ["ep-9", "ep-8", "ep-7", "ep-6"])
        #expect(snap.nextLive?.slug == "live-10")
        #expect(snap.nextLive?.when == .tomorrow)
        #expect(snap.days.first { $0.day == "2026-10-09" }?.isToday == true)
        #expect(snap.days.first { $0.day == "2026-10-06" }?.episode?.slug == "ep-6")
        #expect(snap.experiments.map(\.slug) == ["ep-6"])
    }

    // MARK: Experiment progress

    @Test func experimentKeys() throws {
        #expect(ShowLogic.experimentKey(slug: "movement-1", day: 3) == "show:movement-1:day:3")
        let parsed = try #require(ShowLogic.parseExperimentKey("show:movement-1:day:3"))
        #expect(parsed.slug == "movement-1")
        #expect(parsed.day == 3)
        #expect(ShowLogic.parseExperimentKey("show:movement-1:day:0") == nil)
        #expect(ShowLogic.parseExperimentKey("show:movement-1:day:32") == nil)
        #expect(ShowLogic.parseExperimentKey("show:Movement:day:1") == nil)
        #expect(ShowLogic.parseExperimentKey("show:a:b:day:1") == nil)
        #expect(ShowLogic.parseExperimentKey("gut-feedback") == nil)
    }

    @Test func marksAreGroupedInZurichDays() {
        let rows = [
            ShowProgressRow(contentSlug: "show:ep-a:day:1", completedAt: utc("2026-10-07T22:30:00Z")),
            ShowProgressRow(contentSlug: "show:ep-a:day:2", completedAt: nil),
            ShowProgressRow(contentSlug: "show:ep-b:day:1", completedAt: utc("2026-10-08T08:00:00Z")),
            ShowProgressRow(contentSlug: "gut-feedback", completedAt: utc("2026-10-08T08:00:00Z")),
        ]
        let marks = ShowLogic.marks(from: rows)
        #expect(marks.count == 2)
        #expect(marks["ep-a"] == [ShowLogic.ExperimentMark(day: 1, zurichDay: "2026-10-08"), ShowLogic.ExperimentMark(day: 2, zurichDay: "")])
        #expect(marks["ep-b"]?.count == 1)
    }

    @Test func daysGoInOrderOnePerCalendarDay() {
        let days = Array(1...7)
        let marks = [ShowLogic.ExperimentMark(day: 1, zurichDay: "2026-10-07"), ShowLogic.ExperimentMark(day: 2, zurichDay: "2026-10-08")]
        let state = ShowLogic.experimentState(marks, dayNumbers: days, today: "2026-10-09")
        #expect(state.done == [1, 2])
        #expect(state.nextDay == 3)
        #expect(!state.doneToday)
        #expect(ShowLogic.canMark(state, day: 3))
        #expect(!ShowLogic.canMark(state, day: 4))

        let sameDay = ShowLogic.experimentState(marks, dayNumbers: days, today: "2026-10-08")
        #expect(sameDay.doneToday)
        #expect(!ShowLogic.canMark(sameDay, day: 3))

        let all = ShowLogic.experimentState(days.map { ShowLogic.ExperimentMark(day: $0, zurichDay: "2026-10-0\($0)") }, dayNumbers: days, today: "2026-10-20")
        #expect(all.nextDay == nil)
        // A gap stays the next day (days are done in order).
        let gap = ShowLogic.experimentState([ShowLogic.ExperimentMark(day: 2, zurichDay: "x")], dayNumbers: days, today: "y")
        #expect(gap.nextDay == 1)
    }

    @Test func reminderPlan() {
        let cal = ShowLogic.calendar("Europe/Zurich")
        let days = Array(1...7)
        let twoDone = ShowLogic.ExperimentState(done: [1, 2], nextDay: 3, doneToday: false)
        let morning = ShowLogic.zonedDate(day: "2026-10-09", time: "08:00")!
        let early = ShowLogic.reminderPlan(days: days, state: twoDone, now: morning, calendar: cal)
        #expect(early.count == 5)
        #expect(early.first?.day == 3)
        #expect(early.first?.fireAt == ShowLogic.zonedDate(day: "2026-10-09", time: "09:00"))

        let late = ShowLogic.reminderPlan(days: days, state: twoDone, now: ShowLogic.zonedDate(day: "2026-10-09", time: "10:00")!, calendar: cal)
        #expect(late.count == 4)
        #expect(late.first?.day == 4)
        #expect(late.first?.fireAt == ShowLogic.zonedDate(day: "2026-10-10", time: "09:00"))

        let doneToday = ShowLogic.ExperimentState(done: [1, 2, 3], nextDay: 4, doneToday: true)
        let after = ShowLogic.reminderPlan(days: days, state: doneToday, now: morning, calendar: cal)
        #expect(after.map { $0.day } == [4, 5, 6, 7])
        #expect(after.first?.fireAt == ShowLogic.zonedDate(day: "2026-10-10", time: "09:00"))

        let finished = ShowLogic.ExperimentState(done: days, nextDay: nil, doneToday: false)
        #expect(ShowLogic.reminderPlan(days: days, state: finished, now: morning, calendar: cal).isEmpty)
    }

    // MARK: Display helpers

    @Test func chapters() {
        #expect(ShowLogic.chapterSeconds("00:00:00") == 0)
        #expect(ShowLogic.chapterSeconds("00:03:40") == 220)
        #expect(ShowLogic.chapterSeconds("03:40") == 220)
        #expect(ShowLogic.chapterSeconds("1:02:03") == 3723)
        #expect(ShowLogic.chapterSeconds("00:61:00") == nil)
        #expect(ShowLogic.chapterSeconds("00:03:4a") == nil)
        #expect(ShowLogic.chapterSeconds("1:2:3:4") == nil)
        #expect(ShowLogic.chapterSeconds("") == nil)
        #expect(ShowLogic.chapterSeconds("145") == nil)
        #expect(ShowLogic.chapterLabel("00:03:40") == "03:40")
        #expect(ShowLogic.chapterLabel("01:02:03") == "1:02:03")
    }

    @Test func validationAndFormatting() {
        #expect(ShowLogic.isSlug("movement-as-a-foundation-1"))
        #expect(!ShowLogic.isSlug("-starts-with-dash"))
        #expect(!ShowLogic.isSlug("Upper"))
        #expect(!ShowLogic.isSlug(""))
        #expect(!ShowLogic.isSlug("../etc"))
        #expect(!ShowLogic.isSlug(String(repeating: "a", count: 161)))
        #expect(ShowLogic.safeTime("09:05") == "09:05")
        #expect(ShowLogic.safeTime("24:00") == "12:30")
        #expect(ShowLogic.safeTime("9:05") == "12:30")
        #expect(ShowLogic.safeTime(nil) == "12:30")
        #expect(ShowLogic.safeTimeZone("Europe/Paris") == "Europe/Paris")
        #expect(ShowLogic.safeTimeZone("Mars/Base") == "Europe/Zurich")
        #expect(ShowLogic.httpURL("https://cdn.example.com/a.mp3") != nil)
        #expect(ShowLogic.httpURL("javascript:alert(1)") == nil)
        #expect(ShowLogic.httpURL("/relative.mp3") == nil)
        #expect(ShowLogic.pubmedURL("12345678")?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/12345678/")
        #expect(ShowLogic.pubmedURL("12a") == nil)
        #expect(ShowLogic.durationMinutes(1860) == 31)
        #expect(ShowLogic.durationMinutes(20) == 1)
        #expect(ShowLogic.durationMinutes(nil) == nil)
        #expect(ShowLogic.pieces(ShowEpisodeHas(research: true, article: true, guide: true, faq: true), hasAudio: true).count == 5)
        #expect(ShowLogic.pieces(ShowEpisodeHas(), hasAudio: false).isEmpty)
        #expect(ShowLogic.trackTopic(.mental) == "stress")
        #expect(ShowLogic.trackTopic(nil) == "foundations")
    }
}
