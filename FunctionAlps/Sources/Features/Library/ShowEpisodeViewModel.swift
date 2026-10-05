import Foundation
import Observation
import UserNotifications

/// One episode of the show: the replay, the documents, and this member's one-week experiment (marks in
/// `member_lesson_progress`, synced with the members web) with its optional daily local reminder.
@MainActor
@Observable
final class ShowEpisodeViewModel {
    enum Phase: Equatable {
        case loading
        case loaded(ShowEpisode)
        case notFound
        case unavailable
    }

    let slug: String
    let lang = ShowFormat.lang
    let player = ShowPlayer()
    private(set) var phase: Phase = .loading
    private(set) var covers: [String: URL] = [:]
    private(set) var marks: [ShowLogic.ExperimentMark] = []
    /// False when there is no member (or the marks could not be read): the experiment is a read-only list.
    private(set) var canTrack = false
    private(set) var marking = false
    private(set) var reminderOn = false
    private(set) var reminderDenied = false
    private var patientId: String?

    private let shows: ShowService
    private let members: MemberService
    private let library: LibraryService
    private let notifications: NotificationService
    private let reminders = ShowReminders()

    init(slug: String, shows: ShowService, members: MemberService, library: LibraryService, notifications: NotificationService) {
        self.slug = slug
        self.shows = shows
        self.members = members
        self.library = library
        self.notifications = notifications
    }

    var episode: ShowEpisode? {
        if case .loaded(let episode) = phase { return episode }
        return nil
    }

    var guide: ShowGuide? { episode?.guide?.pick(lang) }
    var days: [ShowGuide.Day] { guide?.experiment.days ?? [] }

    /// Nil when the experiment cannot be tracked (no days, no member, marks unread).
    var state: ShowLogic.ExperimentState? {
        guard canTrack, !days.isEmpty else { return nil }
        return ShowLogic.experimentState(marks, dayNumbers: days.map(\.day), today: shows.today)
    }

    func load() async {
        let shows = self.shows, slug = self.slug
        async let result = shows.episode(slug: slug)
        if let member = try? await members.currentMember() {
            patientId = member.patientId
            marks = (await shows.marks(patientId: member.patientId))[slug] ?? []
            canTrack = true
        }
        covers = await library.topicCovers()
        switch await result {
        case .ok(let episode):
            phase = .loaded(episode)
            player.configure(video: episode.videoURL, audio: episode.card.audioURL, durationSeconds: episode.card.durationSeconds)
            reminderOn = await reminders.isOn(slug: slug)
        case .notFound:
            phase = .notFound
        case .error:
            phase = .unavailable
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// "Mark today done": the next day, once per Zurich day (the service re-checks against fresh marks).
    func markToday() async {
        guard let patientId, let state, let day = state.nextDay, ShowLogic.canMark(state, day: day), !marking else { return }
        marking = true
        defer { marking = false }
        let outcome = await shows.markDay(patientId: patientId, slug: slug, day: day, dayNumbers: days.map(\.day))
        var fresh = (await shows.marks(patientId: patientId))[slug] ?? marks
        // The re-read can lag the write by a beat; a confirmed mark must show at once.
        if outcome == .ok, !fresh.contains(where: { $0.day == day }) {
            fresh.append(ShowLogic.ExperimentMark(day: day, zurichDay: shows.today))
        }
        marks = fresh
        if reminderOn { await scheduleReminders() }
    }

    /// "Remind me every day": asks for notifications once (the app's own permission flow), then plans one reminder
    /// per remaining day at 09:00 on the phone's clock. Off removes them.
    func setReminder(_ on: Bool) async {
        guard on else {
            await reminders.disable(slug: slug)
            reminderOn = false
            return
        }
        await notifications.askIfNeeded()
        await notifications.refreshAuthorization()
        guard notifications.authorization == .authorized || notifications.authorization == .provisional else {
            reminderDenied = true
            reminderOn = false
            return
        }
        reminderDenied = false
        await scheduleReminders()
        reminderOn = await reminders.isOn(slug: slug)
    }

    private func scheduleReminders() async {
        guard let state else { return }
        let title = guide?.experiment.title.nonBlankOr(String(localized: "show.experimentTitle", defaultValue: "Your one-week experiment"))
            ?? String(localized: "show.experimentTitle", defaultValue: "Your one-week experiment")
        let actions = Dictionary(days.map { ($0.day, $0.action) }, uniquingKeysWith: { first, _ in first })
        let items = ShowLogic.reminderPlan(days: days.map(\.day), state: state, now: shows.now, calendar: .current).map { (plan) -> ShowReminders.Item in
            let label = String(localized: "show.dayN", defaultValue: "Day \(plan.day)")
            return ShowReminders.Item(day: plan.day, fireAt: plan.fireAt, title: title, body: "\(label) · \(actions[plan.day] ?? "")")
        }
        await reminders.apply(slug: slug, items: items)
    }

    func stopPlayback() { player.stop() }
}

private extension String {
    func nonBlankOr(_ fallback: String) -> String { showIsBlank ? fallback : self }
}
