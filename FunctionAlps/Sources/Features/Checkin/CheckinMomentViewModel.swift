import Foundation
import Observation

@MainActor
@Observable
final class CheckinMomentViewModel {
    let slot: MomentSlot
    /// Nil = today. A missed day being caught up (the morning screen's "Yesterday") names it; the RPC takes today or yesterday.
    let day: String?
    /// What this screen asks, in order.
    let sectionList: [Section]
    var answers: FunctionalAnswers = .blank
    var catalogPills: [String: [String]] = [:]
    var isSaving = false
    var saveError: String?
    /// Save was tapped with nothing answered: nothing was sent, and the screen says so and stays open.
    private(set) var nothingAnswered = false
    var isEditing = false

    /// The evening moment owns the day's digestion — the gut check-in is part of the reflection, not a
    /// second errand on Home. Nil for every other slot; the standalone gut screen still uses its own.
    let gut: GutCheckinViewModel?

    /// Last night as a wearable or Apple Health recorded it, when one did. The sleep card then shows the night
    /// as recorded (bed → wake, in bed, asleep) instead of the dial; the member can still adjust it.
    private(set) var recordedNight: WearableNight?

    /// Read-only once saved; the member unlocks it with "Change" (`CheckinLock`).
    var lock = CheckinLock()

    /// The MORNING slot's moment as loaded: last night's ONE source of truth. A sleep save starts from it, so nothing else
    /// on that row is wiped (`CheckinService.saveSleep`).
    private(set) var morningMoment: CheckinMoment?
    /// Sleep as it was when the screen opened (or last saved) — a sleep save is only sent when the member changed it.
    private var sleepBaseline: DimAnswers = .empty

    private let checkins: CheckinService
    private let members: MemberService
    private let auth: AuthService
    private let wearables: WearableService?

    init(slot: MomentSlot, checkins: CheckinService, members: MemberService, auth: AuthService, gut: GutService? = nil, wearables: WearableService? = nil,
         day: String? = nil, sections: [Section]? = nil) {
        self.slot = slot
        self.day = day
        let list = sections ?? Self.sections(for: slot)
        self.sectionList = list
        self.checkins = checkins
        self.members = members
        self.auth = auth
        self.wearables = wearables
        // The daily check-in owns the day's digestion; a caught-up day has none (the gut write is today's).
        self.gut = (slot == .evening && list.contains(.digestion)) ? gut.map { GutCheckinViewModel(gut: $0, members: members, auth: auth) } : nil
    }

    /// The day this screen reads and writes.
    private var targetDay: String { day ?? checkins.today }

    /// The sleep inputs from whichever wearable recorded the night: bed → wake as the clock, the window
    /// as the duration, the wake-ups and how long falling asleep took, in the same bands the member would
    /// pick. Only fields the source actually carries are filled — the rest stay for the member. All editable.
    func applyWearableNight(_ night: WearableNight) {
        var sleep = answers[.sleep] ?? .empty
        if let bed = night.bedTime { sleep.specials.bedTime = bed }
        if let wake = night.wakeTime { sleep.specials.wakeTime = wake }
        if let duration = night.durationMin { sleep.specials.durationMin = duration }
        if let latency = night.latency { sleep.specials.latency = latency }
        if let wakeCount = night.wakeCount { sleep.specials.wakeCount = wakeCount }
        answers[.sleep] = sleep
        recordedNight = night
    }

    /// True while a wearable sync runs for last night: the sleep card says it is looking.
    private(set) var syncingNight = false

    private func useRecordedNight(_ night: WearableNight) {
        if CheckinEngine.sleepIsUnanswered(answers[.sleep]) { applyWearableNight(night) } else { recordedNight = night }
    }

    /// Nothing recorded yet: the night may be on the ring but not synced. Sync the vendor accounts in the
    /// background while the dial is on screen; when the night arrives it takes the card, unless the member has
    /// started answering the night by hand in the meantime — then it only sits beside their answer.
    private func syncNight(patientId: String, wearables: WearableService) {
        Task {
            guard await wearables.mayHaveNight(patientId: patientId) else { return }
            syncingNight = true
            defer { syncingNight = false }
            if let night = await wearables.lastNightAfterSync(patientId: patientId) { useRecordedNight(night) }
        }
    }

    /// The moments that ask about last night: the morning, and the daily functional check-in (owner,
    /// 2026-11-10: "at the top we are lacking the sleep").
    var asksSleep: Bool { sectionList.contains(.sleep) }

    /// Re-opening a saved moment EDITS it (same row, upsert on the slot). Last night always shows the latest saved sleep: the
    /// morning moment's, whichever check-in this is.
    func prefill() async {
        let gutPrefill = Task { await self.prefillGut() }   // the evening's digestion loads alongside the moment
        do {
            let member = try await members.currentMember()
            let moments = try await checkins.moments(patientId: member.patientId, day: targetDay)
            let morning = CheckinEngine.moment(for: .morning, in: moments)
            morningMoment = morning
            if let existing = CheckinEngine.moment(for: slot, in: moments) {
                answers = CheckinEngine.answersFromMoment(existing)
                catalogPills = CheckinEngine.catalogPills(from: existing)
                isEditing = true
                lock.loaded(saved: true)
                #if DEBUG
                // The showcase's "check-in in progress" screenshot: answers on screen, but a first check-in.
                if Showcase.isCheckinInProgress { isEditing = false; lock.loaded(saved: false) }
                #endif
            }
            if asksSleep, slot != .morning, let morning, morning.hasSleep {
                // The night was already told: the daily check-in shows the morning's answers, not a copy of its own.
                answers[.sleep] = CheckinEngine.answersFromMoment(morning)[.sleep] ?? .empty
            }
            // A night only this slot's own (older) row holds is not "already saved" where it now belongs: the first save moves it
            // to the morning slot, so replacing that row without sleep can never lose it.
            let nightLivesOnTheMorning = morning?.hasSleep ?? false
            sleepBaseline = (asksSleep && slot != .morning && !nightLivesOnTheMorning) ? .empty : (answers[.sleep] ?? .empty)
            if asksSleep, let wearables {
                // Last night from Apple Health on this phone, else from a wearable that synced server-side.
                // It fills only a night nobody has answered yet; an answered one keeps the member's times.
                // Neither source → the member slides the dial themselves.
                if let night = await wearables.lastNightAnySource(patientId: member.patientId) {
                    useRecordedNight(night)
                } else {
                    syncNight(patientId: member.patientId, wearables: wearables)
                }
                // Apple Health on this phone: push the night to CM OS now too, so the practice sees it this morning.
                if wearables.isConnected { Task { await wearables.sync() } }
            }
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "checkin.prefill")
            if case .unauthorized = error { await auth.handleUnauthorized() }
        } catch {
            Log.data.error("checkin.prefill: \(String(describing: error), privacy: .public)")
        }
        await gutPrefill.value
    }

    private func prefillGut() async {
        guard let gut else { return }
        await gut.prefill()
    }

    func toggleCatalog(_ group: PillGroup, _ key: String) {
        var current = catalogPills[group.rawValue] ?? []
        if let i = current.firstIndex(of: key) { current.remove(at: i) } else { current.append(key) }
        catalogPills[group.rawValue] = current
    }

    func isCatalogOn(_ group: PillGroup, _ key: String) -> Bool {
        (catalogPills[group.rawValue] ?? []).contains(key)
    }

    /// Sleep is one shared answer: saved to the MORNING slot, from either check-in, and only when the member changed it.
    var sleepNeedsSave: Bool {
        guard asksSleep else { return false }
        let sleep = answers[.sleep] ?? .empty
        guard sleep != sleepBaseline else { return false }
        var onlySleep = FunctionalAnswers.blank
        onlySleep[.sleep] = sleep
        return CheckinEngine.answersHaveContent(slot: .morning, answers: onlySleep, catalogPills: [:], note: nil)
    }

    private func storeSleep(patientId: String) async throws {
        let sleep = answers[.sleep] ?? .empty
        _ = try await checkins.saveSleep(sleep, existingMorning: morningMoment, patientId: patientId, day: day)
        sleepBaseline = sleep
    }

    /// The morning screen's sleep part: last night alone, to the morning slot. True when nothing failed (nothing to save is fine).
    func saveSleep() async -> Bool {
        saveError = nil
        guard sleepNeedsSave else { return true }
        isSaving = true
        defer { isSaving = false }
        do {
            let member = try await members.currentMember()
            try await storeSleep(patientId: member.patientId)
            lock.didSave()
            return true
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "checkin.saveSleep")
            if case .unauthorized = error { await auth.handleUnauthorized(); return false }
            saveError = error.userMessage
            return false
        } catch {
            saveError = String(describing: error)
            return false
        }
    }

    /// True when saved. False leaves the answers in place with an error — or, when nothing was answered at all,
    /// with `nothingAnswered` set and nothing sent (it used to return true there and close as if saved).
    /// Last night goes to the MORNING slot (see `saveSleep`); the moment saved here — the daily one — never carries its own copy.
    /// The evening saves twice — the moment, then the day's digestion. The moment write is an upsert on
    /// the slot, so a retry after a failed gut write costs nothing and duplicates nothing.
    func save() async -> Bool {
        saveError = nil
        nothingAnswered = false
        let dailyAnswers = CheckinService.withoutSleep(answers)
        let gutHasContent = gut.map { GutEngine.hasAnyAnswer($0.answers) || $0.redFlags.any } ?? false
        let dailyHasContent = CheckinEngine.answersHaveContent(slot: slot, answers: dailyAnswers, catalogPills: catalogPills, note: note)
        let savesSleep = sleepNeedsSave
        guard dailyHasContent || gutHasContent || savesSleep else {
            nothingAnswered = true
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let member = try await members.currentMember()
            if savesSleep { try await storeSleep(patientId: member.patientId) }
            if dailyHasContent {
                _ = try await checkins.save(slot: slot, answers: dailyAnswers, catalogPills: catalogPills, note: note, patientId: member.patientId, day: day)
            }
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "checkin.save")
            if case .unauthorized = error { await auth.handleUnauthorized(); return false }
            saveError = error.userMessage
            return false
        } catch {
            saveError = String(describing: error)
            return false
        }
        if let gut, !(await gut.save()) {
            saveError = gut.saveError
            return false
        }
        lock.didSave()
        return true
    }

    /// Something to save on this screen: a moment's answers, the digestion, or a changed night.
    var hasAnythingToSave: Bool {
        let gutHasContent = gut.map { GutEngine.hasAnyAnswer($0.answers) || $0.redFlags.any } ?? false
        return CheckinEngine.answersHaveContent(slot: slot, answers: CheckinService.withoutSleep(answers), catalogPills: catalogPills, note: note) || gutHasContent || sleepNeedsSave
    }

    /// The evening's one note: it rides with the moment AND with the digestion detail, so the practitioner
    /// reads the member's words wherever they look.
    private var note: String? {
        guard let text = gut?.notes.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Sections (moment-sections.ts)

    enum Section: Hashable { case sleep, dayFeeling, markers, digestion, context }

    /// Morning = last night, then "Feeling for the day" (the morning screen draws that card itself; the old intent / priority /
    /// mood sections are retired, owner-validated 2026-11-12). Evening = the DAILY functional check-in: last night first
    /// (owner, 2026-11-10), then the day, digestion included. Last night is ONE answer, kept on the morning slot: the daily
    /// screen shows it and saves a change there, and its own submission carries no sleep.
    /// Midday is never offered any more; a legacy row opened from a deep link still renders what it holds.
    var sections: [Section] { sectionList }

    static func sections(for slot: MomentSlot) -> [Section] {
        switch slot {
        case .morning: [.sleep, .dayFeeling]
        case .midday: [.markers, .context]
        case .evening: [.sleep, .markers, .digestion, .context]
        }
    }

    var greeting: String {
        switch slot {
        case .morning: String(localized: "checkin.morning.greeting", defaultValue: "Good morning")
        case .midday: String(localized: "checkin.midday.greeting", defaultValue: "This afternoon")
        case .evening: String(localized: "checkin.daily.greeting", defaultValue: "Daily functional check-in")
        }
    }

    var intro: String {
        if isEditing { return String(localized: "checkin.editing", defaultValue: "You already checked in for this moment · tweak anything and save again.") }
        switch slot {
        case .morning: return String(localized: "checkin.morning.intro", defaultValue: "A few quick reads to open the day. Answer what you feel like · anything you skip is fine.")
        case .midday: return String(localized: "checkin.midday.intro", defaultValue: "A short pause in the middle of the day. Only what you feel like sharing.")
        case .evening: return String(localized: "checkin.daily.intro", defaultValue: "Last night, your day and your digestion. Answer what you feel like · anything you skip is fine.")
        }
    }

    var markersTitle: String {
        // A caught-up day (`day` set) is over: "How was your day?".
        slot == .evening && day != nil
            ? String(localized: "checkin.markers.yesterday", defaultValue: "How was your day?")
            : slot == .evening
            ? String(localized: "checkin.markers.daily", defaultValue: "How is your day?")
            : String(localized: "checkin.markers.later", defaultValue: "How are you feeling right now?")
    }
}
