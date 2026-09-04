import SwiftUI

/// The reader — the one screen in the app that goes QUIET. The wall steps back to warm paper
/// (reading deserves stillness), serif headings carry the article, and the floating navbar is
/// replaced by the mark-done bar. Body is `body_md` from `member_library_get`.
struct ReaderView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let slug: String
    @State private var item: ReaderResult?
    @State private var loaded = false
    @State private var isDemo = false
    @State private var marking = false
    @State private var done = false
    @State private var patientId: String?

    private static let ink = Color(hex: 0x33332C)

    var body: some View {
        VStack(spacing: 0) {
            contextBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !loaded {
                        FALoadingState().padding(.top, 60)
                    } else if let item {
                        article(item)
                    } else {
                        FAErrorState(title: String(localized: "library.read.unavailable", defaultValue: "This article isn't available"), message: "", retryTitle: String(localized: "library.back", defaultValue: "Back to the library")) { dismiss() }
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, isLesson ? 110 : 40)
            }
        }
        .background(FAColor.warm.ignoresSafeArea())
        .overlay(alignment: .bottom) { if isLesson, let item, !item.locked { markDoneBar(item) } }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task(id: slug) { await load() }
    }

    private var isLesson: Bool { item?.track != nil }

    private func load() async {
        defer { loaded = true }
        if slug.hasPrefix("demo-") { item = LibraryDemo.reader(slug: slug); isDemo = true; return }
        guard let member = try? await dependencies.members.currentMember() else {
            item = LibraryDemo.reader(slug: slug); isDemo = true; return
        }
        patientId = member.patientId
        item = await dependencies.library.reader(slug: slug, patientId: member.patientId)
        if let item, item.kind == .resource, !item.locked {
            await dependencies.library.recordResourceOpen(patientId: member.patientId, slug: slug)
        }
    }

    private func markDone() async {
        guard let item, let track = item.track, let patientId, !isDemo, !marking else { done = true; return }
        marking = true
        defer { marking = false }
        // `notCurrent` = an earlier lesson is still open — the honest sequence rule. The button stays.
        if await dependencies.library.completeLesson(patientId: patientId, trackSlug: track.slug, contentSlug: slug) == .ok { done = true }
    }

    // MARK: Context bar (track name + position + honest progress line)

    private var contextBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.charcoal)
                        .frame(width: 26, height: 26).background(Color(hex: 0x1A1A16, opacity: 0.05), in: Circle())
                }
                .buttonStyle(.plain)
                Text(contextLine).font(FATypography.sans(10.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.stone).lineLimit(1)
                Spacer()
            }
            if let track = item?.track {
                let pct = Double(track.index + (done ? 1 : 0)) / Double(max(1, track.total))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.08))
                        Capsule().fill(FALibraryColor.gold).frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 4)
                .animation(.easeInOut, value: done)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 9)
        .background(FAColor.warm)
        .overlay(alignment: .bottom) { Divider().overlay(Color(hex: 0x1A1A16, opacity: 0.07)) }
    }

    private var contextLine: String {
        if let track = item?.track { return String(localized: "library.read.position", defaultValue: "\(track.title) · lesson \(track.index + 1) of \(track.total)") }
        if item?.kind == .resource { return item?.supplement == true ? String(localized: "library.section.supplements", defaultValue: "Supplements") : String(localized: "library.badge.resource", defaultValue: "Resource") }
        return String(localized: "library.title", defaultValue: "Library")
    }

    // MARK: Article

    @ViewBuilder
    private func article(_ item: ReaderResult) -> some View {
        if isDemo {
            Text(String(localized: "library.samplePreview", defaultValue: "Sample preview")).font(FATypography.sans(10.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.stone).padding(.bottom, 8)
        }
        Text(item.pillar.uppercased()).font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(FALibraryColor.gold).padding(.bottom, 6)
        Text(item.title).font(FATypography.display(24, relativeTo: .title)).foregroundStyle(FAColor.charcoal).padding(.bottom, 10)

        if item.locked || item.bodyMd == nil {
            VStack(spacing: 8) {
                Image(systemName: "lock").font(.system(size: 16, weight: .medium)).foregroundStyle(FALibraryColor.gold)
                Text(lockCopy(item)).font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.stone).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous).strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
            .padding(.top, 8)
        } else if let md = item.bodyMd {
            ForEach(Array(LibraryMarkdown.parse(md).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }

        if let pair = item.pair {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "library.pair.title", defaultValue: "Connected to this")).font(FATypography.display(15, relativeTo: .headline)).foregroundStyle(FAColor.charcoal)
                Button { router.libraryPath.append(.read(pair.slug)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "library.pair.kicker", defaultValue: "Go deeper").uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(pair.title).font(FATypography.display(13.5, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color(hex: 0x1A1A16, opacity: 0.07), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 22)
        }
    }

    private func lockCopy(_ item: ReaderResult) -> String {
        if !item.locked { return String(localized: "library.read.writing", defaultValue: "This article is being written · check back soon.") }
        return item.lockReason == .membership
            ? String(localized: "library.read.lock.membership", defaultValue: "This one comes with an active membership. The lessons you already have in this track stay open to you.")
            : String(localized: "library.read.lock.programme", defaultValue: "This one opens as part of your program · your practitioner unlocks it.")
    }

    // MARK: Mark-done bar (lessons only)

    private func markDoneBar(_ item: ReaderResult) -> some View {
        HStack(spacing: 10) {
            Text(done ? String(localized: "library.done.saved", defaultValue: "Nice · progress saved") : String(localized: "library.read.lesson", defaultValue: "Lesson \((item.track?.index ?? 0) + 1) of \(item.track?.total ?? 0)"))
                .font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone).lineLimit(1)
            Spacer()
            Button { Task { await markDone() } } label: {
                HStack(spacing: 6) {
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                    Text(done ? String(localized: "library.lesson.done", defaultValue: "Done") : marking ? String(localized: "state.saving", defaultValue: "Saving…") : String(localized: "library.markDone", defaultValue: "Mark as done"))
                        .font(FATypography.sans(11.5, .bold, relativeTo: .caption))
                }
                .foregroundStyle(FAColor.cream)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(done ? FAColor.forestSoft : FAColor.forest, in: Capsule())
                .opacity(marking ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(marking || done)
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(Color.white.opacity(0.9), in: Capsule())
        .overlay { Capsule().strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
        .padding(.horizontal, 14).padding(.bottom, 14)
    }
}

// MARK: - Markdown blocks, in the reader's type scale

struct MarkdownBlockView: View {
    let block: LibraryMarkdown.Block
    private static let ink = Color(hex: 0x33332C)

    var body: some View {
        switch block {
        case .image(let src, let alt):
            ArticleFigure(src: src, alt: alt)
        case .heading(let level, let runs):
            let size: CGFloat = level == 1 ? 20 : level == 2 ? 17 : 14.5
            runsText(runs, size: size, color: FAColor.charcoal, serif: true)
                .lineSpacing(size * 0.25)
                .padding(.top, 18).padding(.bottom, 7)
        case .paragraph(let runs):
            runsText(runs, size: 13.5, color: Self.ink).lineSpacing(6).padding(.bottom, 12)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, runs in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(FAColor.forestSoft).frame(width: 5, height: 5).padding(.top, 8)
                        runsText(runs, size: 13, color: Self.ink).lineSpacing(5)
                    }
                }
            }
            .padding(.bottom, 12)
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, runs in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(i + 1).").font(FATypography.sans(12.5, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.forestSoft).frame(minWidth: 16, alignment: .leading)
                        runsText(runs, size: 13, color: Self.ink).lineSpacing(5)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Inside a serif heading the runs stay serif; in prose, bold runs go charcoal.
    private func runsText(_ runs: [LibraryMarkdown.Run], size: CGFloat, color: Color, serif: Bool = false) -> Text {
        runs.reduce(Text("")) { acc, run in
            var t = Text(run.text)
            if serif {
                t = t.font(FATypography.display(size, relativeTo: .body)).foregroundColor(color)
            } else {
                t = t.font(FATypography.sans(size, run.bold ? .bold : .regular, relativeTo: .body)).foregroundColor(run.bold ? FAColor.charcoal : color)
            }
            if run.italic { t = t.italic() }
            return acc + t
        }
    }
}

/// A block-level article image (the infographics), full width, with its alt as a caption. Tap it
/// to open the full-size original in the zoomable viewer — the inline copy is a CDN-resized
/// version, so the page stays light and the detail is one tap away.
struct ArticleFigure: View {
    let src: String
    let alt: String
    @State private var inline: UIImage?
    @State private var failed = false
    @State private var expanded = false

    private var url: URL? { URL(string: src) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let inline {
                Button { expanded = true } label: {
                    Image(uiImage: inline)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.45), in: Circle())
                                .padding(8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(alt.isEmpty ? String(localized: "reader.figure.expand", defaultValue: "Expand image") : alt)
                .accessibilityHint(String(localized: "reader.figure.hint", defaultValue: "Opens the image full screen; pinch to zoom"))
            } else if !failed {
                Rectangle().fill(Color(hex: 0x1A1A16, opacity: 0.05)).frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { ProgressView().tint(FAColor.forestSoft) }
            }
            if !alt.isEmpty, inline != nil || !failed {
                Text(alt).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            }
        }
        .padding(.vertical, 8)
        .task(id: src) {
            // Inline: a 1600 px render (the originals are ~2 MB); the viewer fetches the original.
            guard let url else { failed = true; return }
            let thumb = LibraryLogic.storageThumbnail(url, width: 1600, height: 1600) ?? url
            if let image = await RemoteImageCache.shared.image(for: thumb) { inline = image } else { failed = true }
        }
        .fullScreenCover(isPresented: $expanded) {
            FullImageLoader(url: url, fallback: inline, caption: alt)
        }
    }
}

/// The viewer with the ORIGINAL asset: shows the inline copy at once, swaps in the full-resolution
/// original when it arrives, so zooming never waits on the network.
private struct FullImageLoader: View {
    let url: URL?
    let fallback: UIImage?
    let caption: String
    @State private var full: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let image = full ?? fallback {
                ImageViewer(image: image, caption: caption)
            } else {
                ZStack { Color.black.ignoresSafeArea(); ProgressView().tint(.white) }
                    .onTapGesture { dismiss() }
            }
        }
        .task {
            guard let url else { return }
            full = await RemoteImageCache.shared.image(for: url)
        }
    }
}
