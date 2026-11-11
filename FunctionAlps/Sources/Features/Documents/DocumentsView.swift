import SwiftUI
import SafariServices

/// "Documents": everything the care team released to the member, newest first, filtered by kind. Each card has a
/// left block in the kind's colour with its icon; the kind's NAME and a "New" label carry the meaning too, never
/// the colour alone (rule 10). A file opens as a signed URL, a link on the members site, the plan on its own page,
/// all in the in-app browser; the first open is recorded.
struct DocumentsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model: DocumentsViewModel?

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "documents.title", defaultValue: "Documents"), hairline: true)
            if let model {
                content(model)
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil { model = DocumentsViewModel(service: dependencies.documents) }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: DocumentsViewModel) -> some View {
        @Bindable var model = model
        Group {
            switch model.state {
            case .loading:
                FALoadingState(message: String(localized: "documents.loading", defaultValue: "Loading your documents…"))
            case .failed(let error):
                ScrollView {
                    FACard {
                        FAErrorState(title: String(localized: "documents.error.title", defaultValue: "Couldn't load your documents"), message: error.userMessage) {
                            Task { await model.load(force: true) }
                        }
                    }
                    .padding(16)
                }
            case .empty:
                ScrollView(showsIndicators: false) {
                    FAEmptyState(
                        title: String(localized: "documents.empty.title", defaultValue: "No documents yet"),
                        message: String(localized: "documents.empty.message", defaultValue: "Reports, lab reports, resources and invoices from your care team will appear here."),
                        systemImage: "doc.text"
                    )
                    .padding(16).padding(.bottom, FASpacing.navBarClearance)
                }
                .refreshable { await model.load(force: true) }
            case .loaded:
                list(model)
            }
        }
        .sheet(item: $model.page) { page in
            DocumentSafariView(url: page.url).ignoresSafeArea()
        }
        .onChange(of: model.showPlan) { _, show in
            if show { model.showPlan = false; router.push(.carePlan) }
        }
        .alert(
            String(localized: "documents.open.error.title", defaultValue: "Couldn't open this document"),
            isPresented: Binding(get: { model.openError != nil }, set: { if !$0 { model.dismissError() } })
        ) {
            Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(model.openError?.userMessage ?? "")
        }
    }

    private func list(_ model: DocumentsViewModel) -> some View {
        VStack(spacing: 0) {
            DocumentFilterBar(selection: Binding(get: { model.filter }, set: { model.filter = $0 }), count: model.count(for:))
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    let docs = model.visible
                    if docs.isEmpty {
                        FAEmptyState(
                            title: String(localized: "documents.filter.empty.title", defaultValue: "Nothing here"),
                            message: String(localized: "documents.filter.empty.message", defaultValue: "No documents of this kind yet."),
                            systemImage: "tray"
                        )
                        .padding(.top, 24)
                    }
                    ForEach(docs) { doc in
                        DocumentCard(doc: doc, isOpening: model.openingId == doc.id) { Task { await model.open(doc) } }
                    }
                }
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(force: true) }
        }
    }
}

/// The segmented filter: a horizontally scrolling strip, the selected chip filled.
private struct DocumentFilterBar: View {
    @Binding var selection: DocumentFilter
    let count: (DocumentFilter) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DocumentFilter.allCases) { filter in
                    let selected = selection == filter
                    Button { selection = filter } label: {
                        Text(filter == .all ? filter.title : "\(filter.title) \(count(filter))")
                            .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(selected ? Color.white : FAColor.ink)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .background(selected ? FAColor.forest : Color.white.opacity(0.7), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// One document: the kind-coloured block on the left, the words in the middle, "New" on the right.
private struct DocumentCard: View {
    let doc: MemberDocument
    let isOpening: Bool
    let action: () -> Void

    var body: some View {
        let tint = Color(hex: doc.kind.tintHex)
        Button(action: action) {
            HStack(alignment: .stretch, spacing: 0) {
                ZStack {
                    tint
                    if isOpening {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: doc.kind.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 60)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.title)
                        .font(FATypography.sans(15, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading).lineLimit(3)
                    let subtitle = DocumentsLogic.subtitle(doc)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    }
                    Text(doc.kind.label).font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(tint)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                if doc.isNew {
                    Text(String(localized: "documents.new", defaultValue: "New"))
                        .font(FATypography.sans(11, .bold, relativeTo: .caption2)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: 0xC48B35), in: Capsule())
                        .padding(.trailing, 12).frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: 76)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(hex: 0x1A1A16, opacity: 0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibility: String {
        var parts = [doc.kind.label, doc.title, DocumentsLogic.subtitle(doc)]
        if doc.isNew { parts.append(String(localized: "documents.new", defaultValue: "New")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// `SFSafariViewController` (a system view, no package): renders a signed PDF inline and shares no cookies with
/// the app. Presented in a sheet.
struct DocumentSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
