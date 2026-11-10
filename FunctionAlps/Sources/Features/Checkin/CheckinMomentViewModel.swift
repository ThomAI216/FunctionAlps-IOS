import Foundation
import Observation

@MainActor
@Observable
final class CheckinMomentViewModel {
    let slot: MomentSlot
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

    private let checkins: CheckinService
    private let members: MemberService
    private let auth: AuthService
    private let wearables: WearableService?

    init(slot: MomentSlot, checkins: CheckinService, members: MemberService, auth: AuthService, gut: GutService? = nil, wearables: WearableService? = nil) {
        self.slot = slot
        self.checkins = checkins
        self.members = members
        self.auth = auth
        self.wearables = wearables
        self.gut = (slot == .evening) ? gut.map { GutCheckinViewModel(gut: $0, members: members, auth: auth) } : nil
    }

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
    var asksSleep: Bool { sections.contains(.sleep) }

    /// Re-opening a saved moment EDITS it (same row, upsert on the slot).
    func prefill() async {
        let gutPrefill = Task { await self.prefillGut() }   // the evening's digestion loads alongside the moment
        do {
            let member = try await members.currentMember()
            let moments = try await checkins.todayMoments(patientId: member.patientId)
            if let existing = CheckinEngine.moment(for: slot, in: moments) {
                answers = CheckinEngine.answersFromMoment(existing)
                catalogPills = CheckinEngine.catalogPills(from: existing)
                isEditing = true
                #if DEBUG
                // The showcase's "check-in in progress" screenshot: answers on screen, but a first check-in.
                if Showcase.isCheckinInProgress { isEditing = false }
                #endif
            } else if slot == .evening, let morning = CheckinEngine.moment(for: .morning, in: moments), morning.hasSleep {
                // The night was already told this morning: the daily check-in starts from those answers.
                answers[.sleep] = CheckinEngine.answersFromMoment(morning)[.sleep] ?? .empty
            }
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

    /// True when saved. False leaves the answers in place with an error — or, when nothing was answered at all,
    /// with `nothingAnswered` set and nothing sent (it used to return true there and close as if saved).
    /// The evening saves twice — the moment, then the day's digestion. The moment write is an upsert on
    /// the slot, so a retry after a failed gut write costs nothing and duplicates nothing.
    func save() async -> Bool {
        saveError = nil
        nothingAnswered = false
        let gutHasContent = gut.map { GutEngine.hasAnyAnswer($0.answers) || $0.redFlags.any } ?? false
        guard CheckinEngine.answersHaveContent(slot: slot, answers: answers, catalogPills: catalogPills, note: note) || gutHasContent else {
            nothingAnswered = true
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let member = try await members.currentMember()
            _ = try await checkins.save(slot: slot, answers: answers, catalogPills: catalogPills, note: note, patientId: member.patientId)
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
        return true
    }

    /// The evening's one note: it rides with the moment AND with the digestion detail, so the practitioner
    /// reads the member's words wherever they look.
    private var note: String? {
        guard let text = gut?.notes.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Sections (moment-sections.ts)

    enum Section: Hashable { case sleep, intent, priority, feeling, markers, digestion, context }

    /// Morning = the night behind you, the day ahead, and how you feel walking into it — the mood card with its
    /// "how did it show up?" (motivated, anxious…) and "what shaped it?" (owner, 2026-10-12: back as before
    /// 2026-09-17). Evening = the DAILY functional check-in: last night first (owner, 2026-11-10), then the day,
    /// digestion included. The day row still takes its sleep from the morning when a morning was saved
    /// (`member_submit_checkin`), so a member who answers both is never counted twice.
    /// Midday is never offered any more; a legacy row opened from a deep link still renders what it holds.
    var sections: [Section] { Self.sections(for: slot) }

    static func sections(for slot: MomentSlot) -> [Section] {
        switch slot {
        case .morning: [.sleep, .intent, .priority, .feeling]
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
        slot == .evening
            ? String(localized: "checkin.markers.daily", defaultValue: "How is your day?")
            : String(localized: "checkin.markers.later", defaultValue: "How are you feeling right now?")
    }
}
