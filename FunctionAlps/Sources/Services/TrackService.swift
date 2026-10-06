import Foundation
import Observation

/// The Foundation Track as one shared, observable value: the server's status, the 14 days, the questionnaires,
/// the member's answers and what they ticked off. Started and read once per foreground (`foreground()`, called by
/// the tabs once the member gate is through); Home's card, the questionnaire flow and the reminder plan all read
/// this one copy.
///
/// Fail-soft by design: a member who is not on the track must never see an error about it, so a failed first
/// read only hides the card (and is logged). Once the status says "active", a failed content read shows on the
/// card with a retry. Ticks are optimistic and written behind; a refused write puts the tick back.
@MainActor
@Observable
final class TrackService {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The server's answer; nil = not enrolled (or not read yet).
    private(set) var status: TrackStatus?
    private(set) var days: [TrackDay] = []
    private(set) var questionnaires: [TrackQuestionnaire] = []
    private(set) var responses: [TrackResponse] = []
    /// Actions ticked, videos played (any day).
    private(set) var activity: Set<TrackActivityItem> = []
    /// The `habit_bank` cards the track's actions point at, by id.
    private(set) var cards: [String: ActionCardRow] = [:]
    /// The track's content could not be read while the member IS on it — the card says so, with a retry.
    private(set) var contentError: String?

    private let backend: any FunctionAlpsBackend
    private let auth: AuthService
    private let now: @Sendable () -> Date
    private var patientId: String?
    private var running: Task<Void, Never>?
    private var lastForeground: Date?

    init(backend: any FunctionAlpsBackend, auth: AuthService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.auth = auth
        self.now = now
    }

    var locale: String { TodayFocus.locale() }
    var submitted: Set<String> { Set(responses.filter(\.submitted).map(\.questionnaireId)) }
    var mode: TrackLogic.CardMode { TrackLogic.cardMode(status: status, questionnaires: questionnaires, submitted: submitted) }
    var today: TrackDay? { status.flatMap { s in days.first { $0.day == s.day } } }
    /// What the reminder planner schedules from (nil off the track).
    var reminders: TrackReminderPlan? { TrackLogic.reminderPlan(status: status, days: days, responses: responses, locale: locale) }

    func questionnaire(_ id: String) -> TrackQuestionnaire? { questionnaires.first { $0.id == id } }
    func response(for questionnaireId: String) -> TrackResponse? { responses.first { $0.questionnaireId == questionnaireId } }
    func isDone(_ action: TrackAction) -> Bool {
        guard let day = status?.day else { return false }
        return activity.contains(TrackActivityItem(day: day, kind: .action, itemKey: action.key))
    }

    // MARK: - Reads

    /// Once per foreground: start the clock (idempotent server-side), then read everything. Overlapping calls
    /// share one run; a second foreground within a few seconds (launch fires both `onAppear` and `.active`) is skipped.
    func foreground() async {
        if let running { await running.value; return }
        if let last = lastForeground, now().timeIntervalSince(last) < 5 { return }
        lastForeground = now()
        let task = Task { await self.run() }
        running = task
        await task.value
        running = nil
    }

    private func run() async {
        do {
            try await backend.startTrack(code: TrackLogic.trackCode)
        } catch {
            report(error, context: "track.start")   // the read below still says where the member stands
        }
        await load()
    }

    func load() async {
        if status == nil { phase = .loading }
        do {
            guard let pid = try await backend.currentPatientId() else { clear(); phase = .loaded; return }
            if let known = patientId, known != pid { clear() }
            patientId = pid
            let fresh = try await backend.trackStatus(code: TrackLogic.trackCode)
            status = fresh
            if fresh?.state == .active { await loadContent(patientId: pid) } else { contentError = nil }
            phase = .loaded
        } catch {
            report(error, context: "track.load")
            // Keep what is on screen; with nothing known yet the card simply stays away.
            if status == nil { phase = .failed((error as? AppError)?.userMessage ?? String(describing: error)) }
        }
    }

    func retry() async { await load() }

    private func loadContent(patientId: String) async {
        do {
            days = try await backend.trackDays(code: TrackLogic.trackCode)
            questionnaires = try await backend.trackQuestionnaires(code: TrackLogic.trackCode)
            responses = try await backend.trackResponses(patientId: patientId)
            contentError = nil
        } catch {
            report(error, context: "track.content")
            if days.isEmpty { contentError = (error as? AppError)?.userMessage ?? String(describing: error) }
        }
        // Extras, each soft: the ticks (a failed read shows nothing ticked) and the action cards (titles fall back).
        do {
            activity = Set(try await backend.trackActivity(patientId: patientId, code: TrackLogic.trackCode))
        } catch {
            report(error, context: "track.activity")
        }
        let ids = Set(days.flatMap(\.actions).compactMap(\.habitBankId)).subtracting(cards.keys).sorted()
        if !ids.isEmpty, let rows = try? await backend.actionCards(ids: ids) {
            for row in rows { cards[row.id] = row }
        }
    }

    /// The status alone (after a submit: the modules and the review rule moved).
    func refreshStatus() async {
        do {
            status = try await backend.trackStatus(code: TrackLogic.trackCode)
        } catch {
            report(error, context: "track.status")
        }
    }

    private func clear() {
        status = nil
        days = []
        questionnaires = []
        responses = []
        activity = []
        contentError = nil
    }

    // MARK: - Ticks

    /// Tick or untick one of today's actions. Shown at once; a refused write puts it back. A table the server does
    /// not have (yet) is not a refusal: the tick stays on this phone for the session.
    func toggle(_ action: TrackAction) async {
        guard let day = status?.day, let patientId else { return }
        let item = TrackActivityItem(day: day, kind: .action, itemKey: action.key)
        if activity.contains(item) {
            activity.remove(item)
            do {
                try await backend.removeTrackActivity(patientId: patientId, code: TrackLogic.trackCode, item: item)
            } catch {
                if !Self.isMissingTable(error) { activity.insert(item) }
                report(error, context: "track.untick")
            }
        } else {
            activity.insert(item)
            do {
                try await backend.addTrackActivity(patientId: patientId, code: TrackLogic.trackCode, item: item)
            } catch {
                if !Self.isMissingTable(error) { activity.remove(item) }
                report(error, context: "track.tick")
            }
        }
    }

    /// The day's video was played: recorded once, best effort.
    func videoPlayed(day: Int) async {
        let item = TrackActivityItem(day: day, kind: .video, itemKey: "day")
        guard !activity.contains(item), let patientId else { return }
        activity.insert(item)
        do {
            try await backend.addTrackActivity(patientId: patientId, code: TrackLogic.trackCode, item: item)
        } catch {
            report(error, context: "track.video")
        }
    }

    /// The day's short read was opened: recorded once, best effort.
    func readOpened(day: Int) async {
        let item = TrackActivityItem(day: day, kind: .read, itemKey: "day")
        guard !activity.contains(item), let patientId else { return }
        activity.insert(item)
        do {
            try await backend.addTrackActivity(patientId: patientId, code: TrackLogic.trackCode, item: item)
        } catch {
            report(error, context: "track.read")
        }
    }

    // MARK: - Answers

    /// Saves one questionnaire's answers (in progress), or submits them. The local copy follows the stored row;
    /// a submit re-reads the status (the modules and the review rule may have moved).
    func save(_ questionnaire: TrackQuestionnaire, answers: [String: JSONValue], submit: Bool) async throws {
        let pid: String
        if let patientId { pid = patientId } else if let resolved = try await backend.currentPatientId() { pid = resolved; patientId = resolved } else {
            throw AppError.unauthorized
        }
        let stored = try await backend.saveTrackResponse(TrackResponseWrite(
            patientId: pid, questionnaireId: questionnaire.id, version: questionnaire.version, answers: answers, submit: submit, at: now()
        ))
        if let i = responses.firstIndex(where: { $0.questionnaireId == questionnaire.id }) { responses[i] = stored } else { responses.insert(stored, at: 0) }
        if submit { await refreshStatus() }
    }

    // MARK: - Errors

    /// PostgREST answers 404 for a table it does not know.
    private static func isMissingTable(_ error: any Error) -> Bool { (error as? AppError) == .notFound }

    private func report(_ error: any Error, context: StaticString) {
        guard let appError = error as? AppError else {
            Log.data.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        Log.error(appError, in: Log.data, context: context)
        if case .unauthorized = appError { Task { await auth.handleUnauthorized() } }
    }
}
