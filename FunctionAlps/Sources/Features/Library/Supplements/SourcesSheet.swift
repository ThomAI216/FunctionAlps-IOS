import SwiftUI

/// The numbered sources of a page or a use. Opened from a source badge (that one is marked) or from the sources
/// card. "Open" follows the page, the DOI or PubMed; a practice rule has nothing to open and says so by its kind.
struct SourcesSheet: View {
    let sources: [SourceRef]
    var highlighted: SourceKey?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sources) { source in
                        row(source)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .faWall()
            .navigationTitle(String(localized: "supplement.sources.title", defaultValue: "Sources"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.done", defaultValue: "Done")) { dismiss() }
                }
            }
        }
    }

    private func row(_ source: SourceRef) -> some View {
        let marked = source.n == highlighted
        return FACard {
            HStack(alignment: .top, spacing: 10) {
                Text(source.n.raw)
                    .font(FATypography.sans(11, .bold, relativeTo: .caption)).monospacedDigit()
                    .foregroundStyle(marked ? FAColor.cream : FAColor.forest)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(marked ? FAColor.forest : FAColor.forestSoft.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.label).font(FATypography.sans(13.5, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    if let kind = source.kind, !kind.isEmpty {
                        Text(kind).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                    if let link = source.link {
                        Button {
                            openURL(link)
                        } label: {
                            Label(String(localized: "supplement.sources.open", defaultValue: "Open"), systemImage: "arrow.up.right.square")
                                .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "supplement.sources.a11y", defaultValue: "Source \(source.n.raw): \(source.label)"))
        }
    }
}

/// A source number inside running text: an SF Symbol badge when one exists for it (digits 1–50, one letter), else
/// the number in brackets. It is text, so it wraps with the line and scales with Dynamic Type.
enum SourceBadge {
    static func text(_ key: SourceKey, tint: Color = FAColor.forestSoft) -> Text {
        if let name = symbolName(key.raw) {
            return Text(Image(systemName: name)).foregroundColor(tint)
        }
        return Text("[\(key.raw)]").font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundColor(tint)
    }

    static func symbolName(_ raw: String) -> String? {
        if let n = Int(raw), (1...50).contains(n) { return "\(n).circle.fill" }
        let letters = raw.lowercased()
        if letters.count == 1, let c = letters.unicodeScalars.first, ("a"..."z").contains(String(c)) { return "\(letters).circle.fill" }
        return nil
    }

    /// The badges of an item, space-separated, ready to append to its text.
    static func trail(_ keys: [SourceKey]) -> Text {
        keys.reduce(Text("")) { acc, key in acc + Text(" ") + text(key) }
    }
}
