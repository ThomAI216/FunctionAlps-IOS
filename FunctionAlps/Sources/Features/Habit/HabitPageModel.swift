import Foundation
import Observation

/// One habit's page: the track's content is the shared `TrackService` copy (Home read it already); this model makes sure
/// it is there (a link can land here cold), reads the library list once for the soft-lock of the reads, and says
/// which of loading / loaded / failed / unauthorized / missing the page is in. Rule 1: the view never reads anything.
@MainActor
@Observable
final class HabitPageModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        case unauthorized
        /// The track does not list this action (an old link, a member off the track).
        case missing
    }

    let key: String
    private(set) var phase: Phase = .loading
    private(set) var articles: [LibraryArticle] = []

    private let track: TrackService
    private let library: LibraryService
    private let members: MemberService

    init(key: String, track: TrackService, library: LibraryService, members: MemberService) {
        self.key = key
        self.track = track
        self.library = library
        self.members = members
    }

    /// The member's track day (1…14); nil off the track.
    var today: Int? { FoundationLibraryLogic.currentDay(track.status) }

    var content: HabitPageContent? {
        guard let today else { return nil }
        return HabitPageContent.make(key: key, days: track.days, cards: track.cards, activity: track.activity, today: today,
                                     library: articles, locale: track.locale)
    }

    func dayTitle(_ day: Int) -> String? {
        track.days.first { $0.day == day }.flatMap { TrackLogic.text($0.titleEn, $0.titleFr, locale: track.locale) }
    }

    func load() async {
        if track.days.isEmpty {
            phase = .loading
            await track.foreground()
        }
        if track.days.isEmpty {
            phase = track.contentError.map(Phase.failed) ?? .missing
            return
        }
        phase = content == nil ? .missing : .loaded
        guard phase == .loaded else { return }
        // The list only decides which reads are soft-locked: a failed read leaves them open (the reader checks again).
        do {
            let member = try await members.currentMember()
            articles = await library.articles(patientId: member.patientId) ?? []
        } catch AppError.unauthorized {
            phase = .unauthorized
        } catch {
            Log.data.error("habit.page.library: \(String(describing: error), privacy: .public)")
        }
    }

    func toggleToday() async {
        guard let today, let content, content.canTick,
              let action = track.days.first(where: { $0.day == today })?.actions.first(where: { $0.key == key }) else { return }
        await track.toggle(action)
    }
}
