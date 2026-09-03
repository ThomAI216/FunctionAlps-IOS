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
    /// The morning's opt-in tier. A saved moment carrying "more" answers opens expanded.
    var showMore = false

    private let checkins: CheckinService
    private let members: MemberService
    private let auth: AuthService

    init(slot: MomentSlot, checkins: CheckinService, members: MemberService, auth: AuthService) {
        self.slot = slot
        self.checkins = checkins
        self.members = members
        self.auth = auth
    }

    /// Re-opening a saved moment EDITS it (same row, upsert on the slot).
    func prefill() async {
        do {
            let member = try await members.currentMember()
            let moments = try await checkins.todayMoments(patientId: member.patientId)
            guard let existing = CheckinEngine.moment(for: slot, in: moments) else { return }
            answers = CheckinEngine.answersFromMoment(existing)
            catalogPills = CheckinEngine.catalogPills(from: existing)
            isEditing = true
            if CheckinEngine.hasMoreTierAnswers(existing) { showMore = true }
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "checkin.prefill")
            if case .unauthorized = error { await auth.handleUnauthorized() }
        } catch {
            Log.data.error("checkin.prefill: \(String(describing: error), privacy: .public)")
        }
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
    func save() async -> Bool {
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let member = try await members.currentMember()
            _ = try await checkins.save(slot: slot, answers: answers, catalogPills: catalogPills, patientId: member.patientId)
            return true
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "checkin.save")
            if case .unauthorized = error { await auth.handleUnauthorized(); return false }
            saveError = error.userMessage
        } catch {
            saveError = String(describing: error)
        }
        return false
    }

    // MARK: Voice + sections (moment-sections.ts)

    enum Section: Hashable { case sleep, intent, markers, context }

    var coreSections: [Section] { slot == .morning ? [.sleep, .intent] : [.markers, .context] }
    var moreSections: [Section] { slot == .morning ? [.markers, .context] : [] }

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
        case .morning: return String(localized: "checkin.morning.intro", defaultValue: "A few quick reads to open the day. Answer what you feel like · anything you skip is fine.")
        case .midday: return String(localized: "checkin.midday.intro", defaultValue: "A short pause in the middle of the day. Only what you feel like sharing.")
        case .evening: return String(localized: "checkin.evening.intro", defaultValue: "A moment to close the day. Nothing here is required.")
        }
    }

    var markersTitle: String {
        slot == .morning
            ? String(localized: "checkin.markers.morning", defaultValue: "How are you feeling?")
            : String(localized: "checkin.markers.later", defaultValue: "How are you feeling right now?")
    }
}
