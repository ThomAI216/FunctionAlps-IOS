import Foundation
import Observation
import UserNotifications

/// One Foundation Track questionnaire, walked page by page. The questions are DATA (`track_question`): this model
/// only knows the kinds and the rules (`TrackLogic`) — which pages show, what is prefilled, which prompt variant
/// reads, when Continue is allowed. Answers are saved on every page change (in progress) and sent on the done page.
@MainActor
@Observable
final class TrackQuestionnaireModel {
    enum Step: Equatable {
        case intro
        /// A page, by its `screen` number.
        case page(Int)
        case done
    }

    enum Sending: Equatable {
        case idle, sending, sent
        case failed(String)
    }

    let questionnaire: TrackQuestionnaire
    let locale: String
    private(set) var step: Step = .intro
    private(set) var answers: [String: JSONValue]
    private(set) var sending: Sending = .idle
    /// The last page save failed; the answers stay here and go with the next save.
    private(set) var saveFailed = false
    private(set) var profile: MemberProfile?
    private(set) var healthBedtime: String?
    private(set) var healthConnected: Bool
    private(set) var healthFailed = false

    private let earlier: [TrackResponse]
    private let optionIndex: [String: [TrackOption]]
    private let actionOptions: [TrackOption]
    private let track: TrackService
    private let members: MemberService
    private let wearables: WearableService
    private let notifications: NotificationService
    private var prefilledScreens: Set<Int> = []

    init(questionnaire: TrackQuestionnaire, track: TrackService, members: MemberService, wearables: WearableService, notifications: NotificationService) {
        self.questionnaire = questionnaire
        self.track = track
        self.members = members
        self.wearables = wearables
        self.notifications = notifications
        locale = track.locale
        let existing = track.response(for: questionnaire.id)
        answers = existing?.answers ?? [:]
        earlier = track.responses.filter { $0.questionnaireId != questionnaire.id }
        optionIndex = TrackLogic.optionIndex(track.questionnaires)
        actionOptions = TrackLogic.trackActionOptions(days: track.days, through: track.status?.day ?? 14, cards: track.cards, locale: track.locale)
        healthConnected = wearables.isConnected
        if existing?.submitted == true {
            step = .done
            sending = .sent
        }
    }

    // MARK: - Where we are

    var context: TrackAnswerContext { TrackAnswerContext(current: answers, earlier: earlier, healthConnected: healthConnected) }
    var pages: [TrackPage] { TrackLogic.visiblePages(questionnaire.questions, in: context) }

    /// The page on screen (if an answer just hid it, the next one that shows).
    var page: TrackPage? {
        guard case .page(let screen) = step else { return nil }
        return pages.first { $0.screen >= screen } ?? pages.last
    }

    /// 0-based position of the page among the pages that show; nil on the intro.
    var pageIndex: Int? {
        switch step {
        case .intro: nil
        case .done: pages.count
        case .page: page.flatMap { p in pages.firstIndex { $0.screen == p.screen } }
        }
    }

    var isLastPage: Bool { page.map { p in !pages.contains { $0.screen > p.screen } } ?? false }
    var canContinue: Bool { page.map { TrackLogic.canContinue($0, answers: answers) } ?? true }

    // MARK: - Reads the flow needs

    /// The profile only for a baseline line, the bedtime only for a question that asks Apple Health.
    func prepare() async {
        var wantsProfile = false, wantsHealth = false
        for question in questionnaire.questions {
            switch question.prefill {
            case .profile?: wantsProfile = true
            case .health?: wantsHealth = true
            default: break
            }
        }
        if wantsProfile { await reloadProfile() }
        if wantsHealth { healthBedtime = await wearables.typicalBedtime() }
    }

    func reloadProfile() async {
        if let member = try? await members.currentMember() { profile = member.profile }
    }

    // MARK: - Navigation

    func begin() async {
        if let first = pages.first { enter(first) } else { await finish() }
    }

    func next() async {
        guard let current = page else { return }
        if let following = pages.first(where: { $0.screen > current.screen }) {
            await save()
            enter(following)
        } else {
            await finish()
        }
    }

    func back() {
        guard let current = page else { return }
        if let previous = pages.last(where: { $0.screen < current.screen }) { enter(previous) } else { step = .intro }
    }

    /// Leaving mid-way keeps what was answered (in progress); the card offers it again.
    func close() async {
        guard sending != .sent, !answers.isEmpty else { return }
        await save()
    }

    func retrySend() async { await send() }

    private func enter(_ page: TrackPage) {
        // First visit of a page: what was already said is shown, not re-asked; a time wheel starts on a value.
        if prefilledScreens.insert(page.screen).inserted {
            for q in page.questions where answers[q.key].map(TrackLogic.isAnswered) != true {
                if let value = TrackLogic.prefillValue(q, context: context, healthBedtime: healthBedtime) {
                    answers[q.key] = value
                } else if q.kind == .time {
                    answers[q.key] = .string(TrackLogic.defaultTime(for: q.key))
                }
            }
        }
        step = .page(page.screen)
    }

    private func finish() async {
        step = .done
        await send()
    }

    // MARK: - Answers

    func value(_ key: String) -> JSONValue? { answers[key] }

    func set(_ key: String, _ value: JSONValue?) { answers[key] = value }

    /// Single choice: tapping the chosen option again clears it.
    func select(_ option: String, in question: TrackQuestion) {
        answers[question.key] = answers[question.key]?.scalarText == option ? nil : .string(option)
    }

    /// Multiple choice, never more than `max_select`.
    func toggle(_ option: String, in question: TrackQuestion) {
        var chosen = answers[question.key]?.scalarTexts ?? []
        if let i = chosen.firstIndex(of: option) {
            chosen.remove(at: i)
        } else {
            if let max = question.maxSelect, max > 0, chosen.count >= max { return }
            chosen.append(option)
        }
        answers[question.key] = chosen.isEmpty ? nil : .array(chosen.map(JSONValue.string))
    }

    func isChosen(_ option: String, in question: TrackQuestion) -> Bool {
        answers[question.key]?.scalarTexts.contains(option) ?? false
    }

    func options(_ question: TrackQuestion) -> [TrackOption] {
        switch question.options {
        case .list(let options)?: options
        case .trackActions?: actionOptions
        case nil: []
        }
    }

    func label(_ option: TrackOption) -> String { TrackLogic.label(option, locale: locale) }

    // MARK: - Words

    /// The prompt: the matching variant, its `{placeholders}` filled from the baseline and the earlier answers.
    func prompt(_ question: TrackQuestion) -> String {
        let raw = TrackLogic.rawPrompt(question, context: context, locale: locale)
        return TrackLogic.fill(raw) { name in
            if name == "baseline" { return self.baselineLine(question) }
            return TrackLogic.answerText(name, context: self.context, options: self.optionIndex, locale: self.locale)
        }
    }

    func help(_ question: TrackQuestion) -> String? { TrackLogic.text(question.helpEn, question.helpFr, locale: locale) }

    func baselineLine(_ question: TrackQuestion) -> String? {
        guard case .profile(let fields)? = question.prefill else { return nil }
        return TrackLogic.baselineLine(profile, fields: fields)
    }

    func chip(_ question: TrackQuestion) -> TrackLogic.PrefillSource? {
        TrackLogic.prefillChip(question, context: context, healthBedtime: healthBedtime)
    }

    var weekOneRecap: [String] { TrackLogic.weekOneRecap(context: context, options: optionIndex, locale: locale) }

    var title: String { TrackLogic.text(questionnaire.titleEn, questionnaire.titleFr, locale: locale) ?? questionnaire.titleEn }
    var intro: String? { TrackLogic.text(questionnaire.introEn, questionnaire.introFr, locale: locale) }
    var doneText: String? { TrackLogic.text(questionnaire.doneEn, questionnaire.doneFr, locale: locale) }

    // MARK: - Apple Health and reminders (both skippable)

    func connectHealth(_ question: TrackQuestion) async {
        healthFailed = false
        do {
            try await wearables.connect()
            healthConnected = true
            answers[question.key] = .string("connected")
        } catch {
            healthFailed = true
        }
    }

    var remindersStatus: UNAuthorizationStatus { notifications.authorization }

    func enableReminders(_ question: TrackQuestion) async {
        await notifications.askIfNeeded()
        let on = notifications.authorization == .authorized || notifications.authorization == .provisional
        answers[question.key] = .string(on ? "enabled" : "declined")
    }

    // MARK: - Saving

    /// What goes to the server: hidden questions' answers dropped, an "other" text whose option is no longer
    /// chosen dropped, empty values dropped.
    private func cleaned() -> [String: JSONValue] {
        var out = TrackLogic.pruned(answers, questions: questionnaire.questions, context: context)
        for q in questionnaire.questions {
            guard case .list(let options)? = q.options, let free = options.first(where: \.freeText) else { continue }
            if !(out[q.key]?.scalarTexts.contains(free.value) ?? false) { out[q.key + "_other"] = nil }
        }
        return out.filter { TrackLogic.isAnswered($0.value) }
    }

    private func save() async {
        do {
            try await track.save(questionnaire, answers: cleaned(), submit: false)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func send() async {
        sending = .sending
        do {
            try await track.save(questionnaire, answers: cleaned(), submit: true)
            sending = .sent
        } catch {
            sending = .failed((error as? AppError)?.userMessage ?? String(describing: error))
        }
    }
}
