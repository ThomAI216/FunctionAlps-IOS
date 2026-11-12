import Foundation
import Testing
@testable import FunctionAlps

@Suite("Morning check-in — rules, slot by hour, shared sleep, lock")
struct MorningCheckinTests {
    // MARK: Rules (morning-rules.json, owner-validated 2026-11-12)

    @Test("Bands on 0–10: low < 4, mid 4–6, high >= 7; a skipped slider has none")
    func bands() {
        #expect(MorningBand.of(39) == .low)
        #expect(MorningBand.of(40) == .mid)
        #expect(MorningBand.of(69) == .mid)
        #expect(MorningBand.of(70) == .high)
        #expect(MorningBand.of(100) == .high)
        #expect(MorningBand.of(0) == .low)
        #expect(MorningBand.of(nil) == nil)
    }

    @Test("The first matching rule wins, from the most specific to the least")
    func firstMatchWins() {
        #expect(MorningRules.rule(mood: 10, energy: 10, motivation: 10).id == "all_low")
        #expect(MorningRules.rule(mood: 10, energy: 10, motivation: 80).id == "mood_energy_low")
        #expect(MorningRules.rule(mood: 10, energy: 80, motivation: 10).id == "mood_motivation_low")
        #expect(MorningRules.rule(mood: 80, energy: 10, motivation: 10).id == "energy_motivation_low")
        #expect(MorningRules.rule(mood: 82, energy: 28, motivation: 76).id == "energy_low_rest_good")
        #expect(MorningRules.rule(mood: 50, energy: 10, motivation: 50).id == "energy_low")
        #expect(MorningRules.rule(mood: 10, energy: 80, motivation: 80).id == "mood_low")
        #expect(MorningRules.rule(mood: 80, energy: 80, motivation: 10).id == "motivation_low")
        #expect(MorningRules.rule(mood: 82, energy: 74, motivation: 76).id == "all_high")
        #expect(MorningRules.rule(mood: 80, energy: 50, motivation: 80).id == "energy_mid")
        #expect(MorningRules.rule(mood: 50, energy: 80, motivation: 50).id == "mood_motivation_mid")
    }

    @Test("Nothing matches more specifically: the last rule is the default")
    func defaultRule() {
        // Mood and energy high, motivation mid: no specific rule asks for that.
        let rule = MorningRules.rule(mood: 80, energy: 80, motivation: 50)
        #expect(rule.id == MorningRules.defaultId)
        #expect(MorningRules.all.last?.id == MorningRules.defaultId)
        #expect(MorningRules.all.last?.matches(mood: nil, energy: nil, motivation: nil) == true)
    }

    @Test("A skipped slider is 'any': it never satisfies a rule that asks for a band")
    func skippedIsAny() {
        #expect(MorningRules.rule(mood: nil, energy: nil, motivation: nil).id == MorningRules.defaultId)
        // Energy answered low, the rest skipped: only the rules that do not ask about mood or motivation can match.
        #expect(MorningRules.rule(mood: nil, energy: 10, motivation: nil).id == "energy_low")
        #expect(MorningRules.rule(mood: nil, energy: nil, motivation: 10).id == "motivation_low")
        #expect(MorningRules.rule(mood: 10, energy: nil, motivation: nil).id == "mood_low")
    }

    @Test("The table has the twelve rules, an action list of at most two buttons, and unique ids")
    func table() {
        #expect(MorningRules.all.count == 12)
        #expect(Set(MorningRules.all.map(\.id)).count == 12)
        #expect(MorningRules.all.allSatisfy { $0.offered.count <= MorningRules.maxActions })
        #expect(MorningRules.rule(mood: 10, energy: 10, motivation: 10).offered == [.walk10, .friend])
        #expect(MorningRules.rule(mood: 82, energy: 74, motivation: 76).offered.isEmpty)   // all good: no buttons
    }

    // MARK: Slot by hour

    private func service(hour: Int, minute: Int) -> CheckinService {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = utc.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute)) ?? Date()
        return CheckinService(backend: RecordingBackend(), calendar: utc, now: { date })
    }

    @Test("Before 14:00 the check-in is the morning's, from 14:00 the daily one")
    func slotByHour() {
        #expect(service(hour: 13, minute: 59).currentSlot == .morning)
        #expect(service(hour: 14, minute: 0).currentSlot == .evening)
        #expect(MomentSlot.current(hour: 0) == .morning)
        #expect(MomentSlot.current(hour: 13) == .morning)
        #expect(MomentSlot.current(hour: 14) == .evening)
        #expect(MomentSlot.current(hour: 23) == .evening)
    }

    @Test("Yesterday is the day before today")
    func yesterday() {
        #expect(service(hour: 9, minute: 0).today == "2026-11-12")
        #expect(service(hour: 9, minute: 0).yesterday == "2026-11-11")
    }

    // MARK: Sleep is one answer

    private var night: DimAnswers {
        var sleep = DimAnswers.empty
        sleep.sliders["refreshed"] = 48
        sleep.specials = SleepSpecials(bedTime: "23:20", wakeTime: "06:45", durationMin: 445, latency: "30_60", wakeCount: "1_2")
        sleep.pills["kept_up"] = ["mind_racing"]
        return sleep
    }

    @Test("The daily payload never carries its own copy of sleep")
    func eveningPayloadHasNoSleep() async throws {
        var answers = FunctionalAnswers.blank
        answers[.sleep] = night
        answers[.stress]?.sliders = ["calm": 58]
        let backend = RecordingBackend()
        let noon = Date(timeIntervalSince1970: 1_788_350_400)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let checkins = CheckinService(backend: backend, calendar: utc, now: { noon })
        let dailyAnswers = CheckinService.withoutSleep(answers)
        _ = try await checkins.save(slot: .evening, answers: dailyAnswers, catalogPills: [:], patientId: "p1")
        let sent = try #require(backend.lastSubmission)
        let json = CheckinEngine.answersJSON(sent.answers)
        #expect(json == .object(["stress": .object(["calm": .number(58)])]))   // no `sleep` key at all
        #expect(sent.pills["kept_up"] == nil)                                      // the night's follow-up pills travel with the night
        #expect(answers[.sleep] == night)                                          // the screen's own answers are untouched
    }

    @Test("A sleep-only morning submission starts from what the morning row holds, so nothing else is wiped")
    func sleepSaveKeepsTheMorningRow() {
        // A morning saved by an earlier version of the app: mood, day_intent / day_priority pills, a note.
        let existing = CheckinMoment(slot: .morning, submittedAt: Date(timeIntervalSince1970: 0), moodScore: 70, sleepRefreshed: 20,
                                     pills: ["day_intent": ["intent_calm"], "day_priority": ["prio_rest"]], note: "slow start")
        let merged = CheckinService.sleepSubmission(sleep: night, existingMorning: existing)
        #expect(merged.answers[.mood]?.sliders["mood"] == 70)
        #expect(merged.catalogPills["day_intent"] == ["intent_calm"] && merged.catalogPills["day_priority"] == ["prio_rest"])
        #expect(merged.note == "slow start")
        // …and the night is the one just edited, not the old one.
        #expect(merged.answers[.sleep] == night)
        #expect(merged.answers[.sleep]?.sliders["refreshed"] == 48)
    }

    @Test("With no morning row yet the sleep-only submission holds the night and nothing else")
    func sleepSaveFromNothing() async throws {
        let merged = CheckinService.sleepSubmission(sleep: night, existingMorning: nil)
        #expect(merged.catalogPills.isEmpty && merged.note == nil)
        let json = CheckinEngine.answersJSON(merged.answers)
        guard case .object(let top) = json else { Issue.record("answers are an object"); return }
        #expect(Set(top.keys) == ["sleep"])
        // The moment guard sees content, so the RPC is called.
        #expect(CheckinEngine.answersHaveContent(slot: .morning, answers: merged.answers, catalogPills: [:], note: nil))
        let backend = RecordingBackend()
        let noon = Date(timeIntervalSince1970: 1_788_350_400)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let checkins = CheckinService(backend: backend, calendar: utc, now: { noon })
        _ = try await checkins.saveSleep(night, existingMorning: nil, patientId: "p1", day: "2026-09-01")
        #expect(backend.calls == ["submit:morning:2026-09-01"])   // the MORNING slot, on the day asked
    }

    // MARK: Lock after save

    @Test("A saved check-in is read-only until the member says Change; saving locks it again")
    func lockLogic() {
        var lock = CheckinLock()
        #expect(!lock.isLocked && !lock.tapNeedsConfirmation)       // nothing saved: nothing is locked
        lock.unlock()
        #expect(!lock.isLocked)                                     // unlocking a day with no check-in does nothing
        lock.loaded(saved: true)
        #expect(lock.isLocked && lock.tapNeedsConfirmation)         // opened on a saved day
        lock.unlock()
        #expect(!lock.isLocked && !lock.tapNeedsConfirmation)       // "Change"
        lock.didSave()
        #expect(lock.isLocked)                                      // saved again: locked again
        lock.loaded(saved: false)
        #expect(!lock.isLocked)
    }

    @Test("The question names the day; the day before a date is computed in the member's calendar")
    func dayLabels() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let en = CheckinDayLabel.text(forDay: "2026-11-12", locale: Locale(identifier: "en_GB"), calendar: utc)
        #expect(en?.contains("Thursday") == true && en?.contains("12") == true && en?.contains("Nov") == true)
        let fr = CheckinDayLabel.text(forDay: "2026-11-12", locale: Locale(identifier: "fr_CH"), calendar: utc)
        #expect(fr?.lowercased().contains("jeudi") == true)
        #expect(CheckinDayLabel.text(forDay: "nonsense") == nil)
        #expect(CheckinDayLabel.previousDay(of: "2026-11-01", calendar: utc) == "2026-10-31")
        #expect(CheckinDayLabel.previousDay(of: "2027-01-01", calendar: utc) == "2026-12-31")
    }

    // MARK: Feeling for the day

    @Test("Low asks why, good asks what helped, the middle asks nothing")
    func feelingAsks() {
        #expect(DayFeelingSchema.ask(for: 39) == .why)
        #expect(DayFeelingSchema.ask(for: 40) == nil)
        #expect(DayFeelingSchema.ask(for: 59) == nil)
        #expect(DayFeelingSchema.ask(for: 60) == .helped)
        #expect(DayFeelingSchema.ask(for: nil) == nil)
        #expect(DayFeelingSchema.groupKey(.energy, .why) == "energy_why")
        #expect(DayFeelingSchema.options(.motivation, .why).count == 5)
        #expect(DayFeelingSchema.options(.mood, .helped).count == 9)
    }

    @Test("Only the pills a slider's current value asks are saved")
    func feelingPillsAreCleaned() {
        let picked: [String: [String]] = [
            "mood_why": ["sad"],                 // mood is now good: its "why" is stale
            "mood_helped": ["got_daylight", "not_an_option"],
            "energy_why": ["poor_sleep"],
            "motivation_helped": ["exercise"],   // motivation was skipped
        ]
        let cleaned = DayFeelingSchema.cleanedPills(picked, mood: 82, energy: 28, motivation: nil)
        #expect(cleaned == ["mood_helped": ["got_daylight"], "energy_why": ["poor_sleep"]])
    }

    @Test("A feeling with nothing in it is not an answer")
    func feelingHasAnswer() {
        #expect(!DayFeeling(day: "2026-11-12").hasAnswer)
        #expect(DayFeeling(day: "2026-11-12", energy: 20).hasAnswer)
        #expect(DayFeeling(day: "2026-11-12", pills: ["mood_helped": ["got_daylight"]]).hasAnswer)
    }

    @Test("The morning asks last night and the feeling; the daily check-in still asks last night first")
    @MainActor
    func sections() {
        #expect(CheckinMomentViewModel.sections(for: .morning) == [.sleep, .dayFeeling])
        #expect(CheckinMomentViewModel.sections(for: .evening).first == .sleep)
    }
}
