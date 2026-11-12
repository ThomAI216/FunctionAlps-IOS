import SwiftUI

/// One Foundation Track day on its own page: the day's reads with their summaries (a day with several reads; a day
/// with one opens its read directly). Only a day that is open for the member gets here — a day still to come shows
/// its soft-lock sheet on the Library instead — and this page checks it again, so a link cannot skip ahead.
struct LibraryDayView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    let day: Int
    @State private var articles: [LibraryArticle] = []
    @State private var readSlugs: Set<String> = []
    @State private var phase: Phase = .loading

    private enum Phase { case loading, loaded, failed }

    private var today: Int? { FoundationLibraryLogic.currentDay(dependencies.track.status) }
    private var reads: [LibraryArticle] {
        let primary = dependencies.track.days.first { $0.day == day }?.readSlug.map { [day: $0] } ?? [:]
        return FoundationLibraryLogic.dayGroups(articles: articles, today: today, readSlugs: readSlugs, primary: primary).first { $0.day == day }?.reads ?? []
    }
    private var opensOn: Int? { today.flatMap { day > $0 ? day : nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased()).font(FATypography.sans(10, .bold, relativeTo: .caption)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                if let title = dayTitle {
                    Text(title).font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink).accessibilityAddTraits(.isHeader)
                }
                switch phase {
                case .loading:
                    FALoadingState().frame(minHeight: 200)
                case .failed:
                    FACard {
                        FAErrorState(title: String(localized: "library.error.title", defaultValue: "Couldn't load the library"), message: "") { Task { await load() } }
                    }
                case .loaded:
                    if let opensOn {
                        FACard {
                            FAEmptyState(title: LibraryDayCopy.status(.locked(opensOnDay: opensOn)),
                                         message: LibrarySoftLockCopy.body(day: opensOn, today: today), systemImage: "lock")
                        }
                    } else if reads.isEmpty {
                        FACard {
                            FAEmptyState(title: String(localized: "library.empty.title", defaultValue: "Nothing here yet"),
                                         message: String(localized: "library.empty.message", defaultValue: "New reads appear here as they are published."))
                        }
                    } else {
                        ForEach(reads) { read in card(read) }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .navigationTitle(String(localized: "library.title", defaultValue: "Library"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear { Task { await refreshRead() } }
    }

    private var eyebrow: String {
        [String(localized: "library.track.eyebrow", defaultValue: "Foundation Track"), String(localized: "library.day.n", defaultValue: "Day \(day)")].joined(separator: " · ")
    }

    private var dayTitle: String? {
        dependencies.track.days.first { $0.day == day }.flatMap { TrackLogic.text($0.titleEn, $0.titleFr, locale: dependencies.track.locale) }
    }

    private func card(_ read: LibraryArticle) -> some View {
        Button { router.libraryPath.append(.read(read.slug)) } label: {
            FACard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kicker(read).uppercased()).font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.0).foregroundStyle(FALibraryColor.gold)
                    Text(read.title).font(FATypography.display(17, relativeTo: .headline)).foregroundStyle(FAColor.charcoal).multilineTextAlignment(.leading)
                    if !read.summary.isEmpty {
                        Text(read.summary).font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(Color(hex: 0x4A4A42)).multilineTextAlignment(.leading)
                    }
                    if readSlugs.contains(read.slug) {
                        Label(LibraryDayCopy.status(.read), systemImage: "checkmark.circle.fill")
                            .font(FATypography.sans(10.5, .medium, relativeTo: .caption)).foregroundStyle(FAColor.stone).padding(.top, 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([kicker(read), read.title, read.summary, readSlugs.contains(read.slug) ? LibraryDayCopy.status(.read) : nil].compactMap { $0 }.joined(separator: ". "))
    }

    private func kicker(_ read: LibraryArticle) -> String {
        var parts: [String] = []
        if let topic = read.topic { parts.append(topic) }
        if let minutes = read.minutes { parts.append(String(localized: "library.minutes", defaultValue: "\(minutes) min")) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        phase = .loading
        guard let member = try? await dependencies.members.currentMember() else { phase = .failed; return }
        guard let list = await dependencies.library.articles(patientId: member.patientId) else { phase = .failed; return }
        articles = list
        readSlugs = await dependencies.library.readSlugs(patientId: member.patientId) ?? []
        phase = .loaded
    }

    private func refreshRead() async {
        guard phase == .loaded, let member = try? await dependencies.members.currentMember(),
              let slugs = await dependencies.library.readSlugs(patientId: member.patientId) else { return }
        readSlugs = slugs
    }
}
