import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    enum Section: String, CaseIterable, Identifiable {
        case priority, tracks, foundations, supplements
        var id: String { rawValue }
        var title: String {
            switch self {
            case .priority: String(localized: "library.section.priority", defaultValue: "Priority")
            case .tracks: String(localized: "library.section.tracks", defaultValue: "Tracks")
            case .foundations: String(localized: "library.section.foundations", defaultValue: "Foundations")
            case .supplements: String(localized: "library.section.supplements", defaultValue: "Supplements")
            }
        }
    }

    private(set) var bundle: LibraryBundle = LibraryDemo.bundle
    private(set) var loaded = false
    var active: Section = .priority
    var expanded: Set<Section> = []
    private(set) var patientId: String?

    private let library: LibraryService
    private let members: MemberService

    init(library: LibraryService, members: MemberService) {
        self.library = library
        self.members = members
    }

    func load() async {
        defer { loaded = true }
        guard let member = try? await members.currentMember() else { bundle = LibraryDemo.bundle; return }
        patientId = member.patientId
        bundle = await library.bundle(patientId: member.patientId) ?? LibraryDemo.bundle
    }

    func toggle(_ section: Section) {
        if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
    }

    var priority: [TrackWithProgress] { bundle.prioritySlugs.compactMap { s in bundle.tracks.first { $0.slug == s } } }
    var inProgress: [TrackWithProgress] { bundle.tracks.filter { $0.state == .inProgress } }
    var foundations: [LibResource] { bundle.resources.filter { !$0.supplement } }
    var supplements: [LibResource] { bundle.resources.filter(\.supplement) }
    var doneTotal: Int { bundle.tracks.reduce(0) { $0 + $1.done } }
    var lessonTotal: Int { bundle.tracks.reduce(0) { $0 + $1.total } }
    var pct: Double { lessonTotal == 0 ? 0 : Double(doneTotal) / Double(lessonTotal) }
    var week: Int? { library.weekNumber(startDate: bundle.plan?.startDate) }

    func count(_ section: Section) -> Int? {
        switch section {
        case .tracks: bundle.tracks.count
        case .foundations: foundations.count
        case .supplements: supplements.count
        case .priority: nil
        }
    }
}
