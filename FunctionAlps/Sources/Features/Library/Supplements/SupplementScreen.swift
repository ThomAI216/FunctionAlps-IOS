import SwiftUI

/// `Route.supplement` / `Route.supplementUse`: load the row, then the page or the use. A row that is not a
/// structured supplement (older payload, no payload) falls back to the reader on `body_md`; the `demo-` sample
/// answers offline. States: loading · failed (retry) · unavailable · locked · veiled · loaded.
struct SupplementScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let slug: String
    @State private var result: LibraryOpen?
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                FALoadingState().faWall()
            } else {
                switch result {
                case .supplement(let entry):
                    SupplementEntryView(entry: entry)
                case .reader(.some):
                    ReaderView(slug: slug)
                case .reader(.none), .none:
                    VStack {
                        FAErrorState(title: String(localized: "supplement.unavailable", defaultValue: "This page isn't available"), message: "",
                                     retryTitle: String(localized: "library.back", defaultValue: "Back to the library")) { dismiss() }
                    }
                    .faWall()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: slug) { await load() }
    }

    private func load() async {
        defer { loaded = true }
        if slug.hasPrefix("demo-") { result = LibraryDemo.open(slug: slug); return }
        guard let member = try? await dependencies.members.currentMember() else { result = LibraryDemo.open(slug: slug); return }
        result = await dependencies.library.open(slug: slug, patientId: member.patientId)
        if case .supplement(let entry) = result, !entry.locked {
            await dependencies.library.recordResourceOpen(patientId: member.patientId, slug: slug)
        }
    }
}

/// A loaded entry: the lock note, the section veil, else the page or the use.
struct SupplementEntryView: View {
    let entry: SupplementEntry
    @State private var sourceSheet: SourceKey?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if entry.slug.hasPrefix("demo-") {
                    Text(String(localized: "library.samplePreview", defaultValue: "Sample preview"))
                        .font(FATypography.sans(10.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                }
                if entry.locked {
                    header
                    SupplementLockNote(reason: entry.lockReason).padding(.top, 8)
                } else {
                    Veiled(open: !entry.veiled) {
                        switch entry.content {
                        case .page(let page):
                            SupplementPageView(page: page, entry: entry) { sourceSheet = $0 }
                        case .use(let use):
                            SupplementUseView(use: use, entry: entry) { sourceSheet = $0 }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $sourceSheet) { key in
            SourcesSheet(sources: sources, highlighted: key)
        }
    }

    private var sources: [SourceRef] {
        switch entry.content {
        case .page(let page): page.sources
        case .use(let use): use.sources
        }
    }

    /// The title alone, for the locked state.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "library.section.supplements", defaultValue: "Supplements").uppercased())
                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FAColor.forestSoft)
            Text(entry.title).font(FATypography.display(25, relativeTo: .title)).foregroundStyle(FAColor.ink)
        }
    }
}
