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
    var isEditing = false

    /// The evening moment owns the day's digestion — the gut check-in is part of the reflection, not a
    /// second errand on Home. Nil for every other slot; the standalone gut screen still uses its own.
    let gut: GutCheckinViewModel?

    /// Last night as Apple Health recorded it, when it prefilled the sleep inputs (morning, first save only).
    private(set) var sleepFromHealth: SleepNight?

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

    /// The sleep inputs from Apple Health: bed → wake as the clock, the window as the duration, the Watch's
    /// wake-ups and how long falling asleep took, mapped to the same bands the member would pick. All editable.
    func applyHealthNight(_ night: SleepNight) {
        var sleep = answers[.sleep] ?? .empty
        let bed = HealthFormat.clock(night.start), wake = HealthFormat.clock(night.end)
        sleep.specials.bedTime = bed
        sleep.specials.wakeTime = wake
        sleep.specials.durationMin = SleepInputsView.windowMinutes(bed: bed, wake: wake)
        sleep.specials.wakeCount = night.interruptions == 0 ? "0" : (night.interruptions <= 2 ? "1_2" : "3plus")
        let latencyMin = night.latencySeconds / 60
        sleep.specials.latency = latencyMin < 15 ? "lt_15" : (latencyMin < 30 ? "15_30" : (latencyMin < 60 ? "30_60" : "gt_60"))
        answers[.sleep] = sleep
        sleepFromHealth = night
    }

    var sleepFromHealthNote: String? {
        guard let night = sleepFromHealth else { return nil }
        return String(localized: "checkin.sleep.fromHealth", defaultValue: "From Apple Health · in bed \(HealthFormat.clock(night.start)) → \(HealthFormat.clock(night.end)) · adjust anything that's off")
    }

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
            } else if slot == .morning, let wearables, let night = await wearables.lastNight() {
                // A first morning save: last night from Apple Health, when the phone is connected.
                applyHealthNight(night)
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

    /// True when saved (or there was nothing to save). False leaves the answers in place with an error.
    /// The evening saves twice — the moment, then the day's digestion. The moment write is an upsert on
    /// the slot, so a retry after a failed gut write costs nothing and duplicates nothing.
    func save() async -> Bool {
        saveError = nil
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

    enum Section: Hashable { case sleep, intent, priority, markers, digestion, context }

    /// Morning = the night behind you and the day ahead. Evening = the day you lived, digestion included.
    /// Midday is never offered any more; a legacy row opened from a deep link still renders what it holds.
    var sections: [Section] {
        switch slot {
        case .morning: [.sleep, .intent, .priority]
        case .midday: [.markers, .context]
        case .evening: [.markers, .digestion, .context]
        }
    }

    var greeting: String {
        switch slot {
        case .morning: String(localized: "checkin.morning.greeting", defaultValue: "Good morning")
        case .midday: String(localized: "checkin.midday.greeting", defaultValue: "This afternoon")
        case .evening: String(localized: "checkin.evening.greeting", defaultValue: "This evening")
        }
    }

    var intro: String {
        if isEditing { return String(localized: "checkin.editing", defaultValue: "You already checked in for this moment · tweak anything and save again.") }
        switch slot {
        case .morning: return String(localized: "checkin.morning.intro", defaultValue: "Last night, and what today is for. Answer what you feel like · anything you skip is fine.")
        case .midday: return String(localized: "checkin.midday.intro", defaultValue: "A short pause in the middle of the day. Only what you feel like sharing.")
        case .evening: return String(localized: "checkin.evening.intro", defaultValue: "A moment to look back on the day. Nothing here is required.")
        }
    }

    var markersTitle: String {
        slot == .evening
            ? String(localized: "checkin.markers.evening", defaultValue: "How was your day?")
            : String(localized: "checkin.markers.later", defaultValue: "How are you feeling right now?")
    }
}
