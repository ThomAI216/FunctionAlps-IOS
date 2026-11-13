import Foundation
import Observation

/// The MORNING check-in (owner-validated 2026-11-12): last night, "Feeling for the day", and the rest of the day on request.
///
/// Three kinds of data, three homes — none of them copied:
/// - last night: ONE answer, kept on the MORNING slot's moment (`CheckinMomentViewModel.saveSleep`);
/// - "Feeling for the day": `patient_day_feelings`, never a check-in moment, so it can't enter the day's mood / energy medians;
/// - the daily cards revealed here (energy & focus, mood, stress, digestion, what fuelled / drained): the DAILY (evening)
///   slot, exactly as the daily check-in would save them.
/// "Yesterday" catches a missed daily check-in up on the same screen (p_day = yesterday).
@MainActor
@Observable
final class MorningCheckinViewModel {
    enum YesterdayState: Equatable { case unknown, done, missing }

    // MARK: Feeling for the day

    var mood: Double?
    var energy: Double?
    var motivation: Double?
    var feelingPills: [String: [String]] = [:]

    // MARK: The parts

    /// Last night (the morning slot).
    let sleep: CheckinMomentViewModel
    /// The rest of today, the daily slot, behind "Reveal the rest of the day".
    let reveal: CheckinMomentViewModel
    var revealOpen = false
    /// Yesterday's daily cards, once the member says "Yes, do it now".
    private(set) var yesterdayModel: CheckinMomentViewModel?
    private(set) var yesterdayState: YesterdayState = .unknown
    private(set) var yesterdaySleepUnanswered = false
    var yesterdayOpen = false

    /// The morning part (sleep + feeling) is read-only once saved.
    var lock = CheckinLock()

    var isSaving = false
    var saveError: String?

    let today: String
    let yesterday: String

    private let checkins: CheckinService
    private let members: MemberService
    private let auth: AuthService
    private let gutService: GutService?
    private var savedFeeling: DayFeeling?

    init(checkins: CheckinService, members: MemberService, auth: AuthService, gut: GutService?, wearables: WearableService?) {
        self.checkins = checkins
        self.members = members
        self.auth = auth
        self.gutService = gut
        today = checkins.today
        yesterday = checkins.yesterday
        sleep = CheckinMomentViewModel(slot: .morning, checkins: checkins, members: members, auth: auth, wearables: wearables, sections: [.sleep])
        reveal = CheckinMomentViewModel(slot: .evening, checkins: checkins, members: members, auth: auth, gut: gut, sections: [.markers, .digestion, .context])
    }

    // MARK: Opening

    func prefill() async {
        let restLoaded = Task { await self.reveal.prefill() }
        await sleep.prefill()
        await restLoaded.value
        do {
            let member = try await members.currentMember()
            // A missing table (the migration not applied yet) reads as "no feeling saved", never as a broken screen.
            let feeling = try? await checkins.dayFeeling(patientId: member.patientId, day: today)
            if let feeling {
                apply(feeling)
                savedFeeling = feeling
            }
            lock.loaded(saved: (feeling?.hasAnswer ?? false) || sleep.lock.saved)
            await loadYesterday(patientId: member.patientId, startedAt: member.profile?.createdAt)
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "morning.prefill")
            if case .unauthorized = error { await auth.handleUnauthorized() }
        } catch {
            Log.data.error("morning.prefill: \(String(describing: error), privacy: .public)")
        }
        #if DEBUG
        await applyShowcase()
        #endif
    }

    private func apply(_ feeling: DayFeeling) {
        mood = feeling.mood.map(Double.init)
        energy = feeling.energy.map(Double.init)
        motivation = feeling.motivation.map(Double.init)
        feelingPills = feeling.pills
    }

    /// Yesterday's daily check-in missing → the prompt. Its night is asked again only when nothing answered it.
    private func loadYesterday(patientId: String, startedAt: Date?) async {
        // A member who started today has no yesterday to miss.
        guard Self.yesterdayApplies(startedAt: startedAt, today: today) else {
            yesterdayState = .unknown
            return
        }
        do {
            let moments = try await checkins.moments(patientId: patientId, day: yesterday)
            let dailyDone = CheckinEngine.slotIsDone(moments, .evening)
            let nightAnswered = moments.contains { $0.hasSleep }
            let row = try? await checkins.dailyCheckin(patientId: patientId, day: yesterday)
            let rowHasNight = row?.sleep != nil
            yesterdaySleepUnanswered = !(nightAnswered || rowHasNight)
            yesterdayState = dailyDone ? .done : .missing
        } catch {
            // Not knowing is not a reason to nag: no prompt.
            yesterdayState = .unknown
            Log.data.error("morning.yesterday: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Feeling for the day

    func value(_ metric: DayFeelingSchema.Metric) -> Double? {
        switch metric {
        case .mood: mood
        case .energy: energy
        case .motivation: motivation
        }
    }

    func set(_ metric: DayFeelingSchema.Metric, _ value: Double?) {
        switch metric {
        case .mood: mood = value
        case .energy: energy = value
        case .motivation: motivation = value
        }
    }

    func isPillOn(_ metric: DayFeelingSchema.Metric, _ ask: DayFeelingSchema.Ask, _ key: String) -> Bool {
        (feelingPills[DayFeelingSchema.groupKey(metric, ask)] ?? []).contains(key)
    }

    func togglePill(_ metric: DayFeelingSchema.Metric, _ ask: DayFeelingSchema.Ask, _ key: String) {
        let group = DayFeelingSchema.groupKey(metric, ask)
        var picked = feelingPills[group] ?? []
        if let i = picked.firstIndex(of: key) { picked.remove(at: i) } else { picked.append(key) }
        feelingPills[group] = picked
    }

    /// What would be saved right now: the pills of the group each slider's value asks, nothing stale.
    func currentFeeling(endRule: String?) -> DayFeeling {
        DayFeeling(
            day: today,
            mood: mood.map { Int($0.rounded()) },
            energy: energy.map { Int($0.rounded()) },
            motivation: motivation.map { Int($0.rounded()) },
            pills: DayFeelingSchema.cleanedPills(feelingPills, mood: mood, energy: energy, motivation: motivation),
            endRule: endRule
        )
    }

    /// The rule the end screen would show for the sliders as they are.
    var currentRule: MorningRule { MorningRules.rule(mood: mood, energy: energy, motivation: motivation) }

    // MARK: Done

    /// Revealed digestion has not loaded yet: saving now could put a blank read on top of today's.
    var canFinish: Bool { !revealOpen || (reveal.gut.map(\.loaded) ?? true) }

    /// "Morning check-in done": saves what changed — last night, the feeling, the revealed daily cards — then the caller opens Today's focus. Nothing is required: it works with whatever was answered. Parts that are locked are not saved again.
    /// True when the focus page may open; false leaves everything in place with `saveError`.
    func done() async -> Bool {
        saveError = nil
        isSaving = true
        defer { isSaving = false }

        guard await sleep.saveSleep() else {
            saveError = sleep.saveError
            return false
        }

        let rule = currentRule
        if !lock.isLocked {
            let feeling = currentFeeling(endRule: rule.id)
            if feeling.hasAnswer, feeling != savedFeeling {
                do {
                    let member = try await members.currentMember()
                    try await checkins.saveDayFeeling(feeling, patientId: member.patientId)
                    savedFeeling = feeling
                } catch let error as AppError {
                    Log.error(error, in: Log.data, context: "morning.saveFeeling")
                    if case .unauthorized = error { await auth.handleUnauthorized(); return false }
                    saveError = error.userMessage
                    return false
                } catch {
                    saveError = String(describing: error)
                    return false
                }
            }
        }

        if revealOpen, !reveal.lock.isLocked, reveal.hasAnythingToSave {
            guard await reveal.save() else {
                saveError = reveal.saveError
                return false
            }
        }

        let nightAnswered = !CheckinEngine.sleepIsUnanswered(sleep.answers[.sleep])
        if currentFeeling(endRule: nil).hasAnswer || sleep.lock.saved || nightAnswered {
            lock.didSave()
        }
        return true
    }

    // MARK: Yesterday

    /// The cards of the caught-up day: its night only when nothing answered it, then the day's markers, its digestion
    /// (saved to yesterday's row — the table accepts it, the app used to send today's) and what fuelled / drained.
    static func yesterdaySections(sleepUnanswered: Bool) -> [CheckinMomentViewModel.Section] {
        sleepUnanswered ? [.sleep, .markers, .digestion, .context] : [.markers, .digestion, .context]
    }

    /// False for a member whose profile started today (local day) or later: there is no yesterday to catch up on.
    /// Unknown start (no profile row / no date) keeps the prompt, as before.
    static func yesterdayApplies(startedAt: Date?, today: String, calendar: Calendar = .current) -> Bool {
        guard let startedAt else { return true }
        return ISO8601.dayString(startedAt, calendar: calendar) < today
    }

    var offersYesterday: Bool { yesterdayState == .missing && !yesterdayOpen }

    func openYesterday() async {
        guard yesterdayModel == nil else { yesterdayOpen = true; return }
        let sections = Self.yesterdaySections(sleepUnanswered: yesterdaySleepUnanswered)
        let model = CheckinMomentViewModel(slot: .evening, checkins: checkins, members: members, auth: auth, gut: gutService, day: yesterday, sections: sections)
        yesterdayModel = model
        yesterdayOpen = true
        await model.prefill()
    }

    /// "Save yesterday": p_day = yesterday. The "Feeling for the day" card is not part of it — that one is this morning's.
    func saveYesterday() async -> Bool {
        guard let model = yesterdayModel else { return false }
        let ok = await model.save()
        if ok { yesterdayState = .done }
        return ok
    }

    #if DEBUG
    /// The showcase's morning screens: a night on the dial and a feeling filled in, as the mockup shows it.
    private func applyShowcase() async {
        guard Showcase.isMorningShot else { return }
        let night = CheckinEngine.answersFromMoment(ShowcaseData.eveningMoment())[.sleep] ?? .empty
        sleep.answers[.sleep] = night
        lock.loaded(saved: false)
        mood = 82
        energy = 28
        motivation = 76
        feelingPills = [
            DayFeelingSchema.groupKey(.mood, .helped): ["got_daylight"],
            DayFeelingSchema.groupKey(.energy, .why): ["poor_sleep", "woke_tired"],
            DayFeelingSchema.groupKey(.motivation, .helped): ["walk_before"],
        ]
        if Showcase.screen == .morningYesterday { await openYesterday() }
    }
    #endif
}
