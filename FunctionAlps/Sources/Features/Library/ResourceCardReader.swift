import SwiftUI

/// The full-page reader for a resource card. ONE renderer for every format — the owner will rework
/// the look later, so format differences stay inside this view (`formatLabel`), never copy-pasted
/// layouts. All card text (title, summary, body, sources, safety note) comes from the backend.
struct ResourceCardReader: View {
    let title: String
    let bodyMd: String
    let card: ReaderCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kicker = kickerText {
                Text(kicker.uppercased())
                    .font(FATypography.sans(9, .bold, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(FAColor.forestSoft)
                    .padding(.bottom, 6)
            }
            Text(title)
                .font(FATypography.display(26, relativeTo: .title))
                .foregroundStyle(FAColor.charcoal)
                .padding(.bottom, 10)
            if let summary = card.summary, !summary.isEmpty {
                Text(summary)
                    .font(FATypography.sans(14.5, .bold, relativeTo: .body))
                    .foregroundStyle(FAColor.charcoal)
                    .lineSpacing(4)
                    .padding(.bottom, 14)
            }
            if let asset = card.assets.first, let raw = asset.url, let url = URL(string: raw) {
                figure(url: url, alt: asset.altText ?? "")
            }
            ForEach(Array(LibraryMarkdown.parse(bodyMd).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
            if !card.sources.isEmpty { sourcesBlock }
            if let safety = card.safety, !safety.isEmpty { safetyBlock(safety) }
        }
    }

    // MARK: Pieces

    private func figure(url: URL, alt: String) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                    .accessibilityLabel(alt)
            }
        }
        .padding(.bottom, 14)
    }

    private var sourcesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "library.card.sources", defaultValue: "Sources"))
                .font(FATypography.display(15, relativeTo: .headline))
                .foregroundStyle(FAColor.charcoal)
            ForEach(Array(card.sources.enumerated()), id: \.offset) { _, source in
                if let raw = source.url, let url = Self.webURL(raw) {
                    Link(destination: url) {
                        Text(source.title)
                            .font(FATypography.sans(12, relativeTo: .footnote))
                            .foregroundStyle(FAColor.forestSoft)
                            .underline()
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(source.title)
                        .font(FATypography.sans(12, relativeTo: .footnote))
                        .foregroundStyle(FAColor.stone)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }

    private func safetyBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "library.card.safety", defaultValue: "Safety note").uppercased())
                .font(FATypography.sans(8.5, .bold, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(FAColor.stone)
            Text(text)
                .font(FATypography.sans(12, relativeTo: .footnote))
                .foregroundStyle(FAColor.charcoal)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FAColor.cream2, in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
        .padding(.top, 18)
    }

    // MARK: Labels

    /// "<Format label> · <Pillar>". Falls back to the backend's own kicker when the format is unknown.
    private var kickerText: String? {
        let format = card.format.flatMap(Self.formatLabel)
        let pillar = card.pillars.first.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        switch (format, pillar) {
        case let (f?, p?): return "\(f) · \(p)"
        case let (f?, nil): return f
        case let (nil, p?): return card.kicker ?? p
        case (nil, nil): return card.kicker
        }
    }

    private static func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    static func formatLabel(_ format: String) -> String? {
        switch format {
        case "short_answer": return String(localized: "library.card.format.short_answer", defaultValue: "Quick answer")
        case "action_card": return String(localized: "library.card.format.action_card", defaultValue: "Action")
        case "practical_guide": return String(localized: "library.card.format.practical_guide", defaultValue: "Guide")
        case "tracker": return String(localized: "library.card.format.tracker", defaultValue: "Tracker")
        case "experiment": return String(localized: "library.card.format.experiment", defaultValue: "Experiment")
        case "recipe": return String(localized: "library.card.format.recipe", defaultValue: "Recipe")
        case "food_list": return String(localized: "library.card.format.food_list", defaultValue: "Food list")
        case "visual": return String(localized: "library.card.format.visual", defaultValue: "Visual")
        default: return nil
        }
    }
}
