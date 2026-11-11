import SwiftUI

// The pieces of the "About <signal>" page and of the links that lead to it (owner, 2026-11-11). Every word of explanation
// comes from `signal_explanations`; what lives here is chrome (captions, buttons) and styling.

// MARK: The link ("Learn about sleep →")

/// The label of the link from a Trends row, a signal's page and the Functional score card to its "About" page. The caller
/// wraps it in a Button or a NavigationLink.
struct SignalAboutLinkLabel: View {
    let key: SignalAboutKey

    var body: some View {
        HStack(spacing: 4) {
            Text(key.linkTitle)
                .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(FAColor.forest)
                .multilineTextAlignment(.leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FAColor.forest)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Header

/// Back chevron, then the signal's colour dot beside the page title.
struct SignalAboutHeader: View {
    let title: String
    let tint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { dismiss() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    Text(String(localized: "trends.title", defaultValue: "Trends")).font(FATypography.sans(15, .semibold, relativeTo: .subheadline))
                }
                .foregroundStyle(FAColor.forest)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(tint).frame(width: 13, height: 13).accessibilityHidden(true)
                Text(title)
                    .font(FATypography.display(30, relativeTo: .largeTitle))
                    .foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Evidence

/// Strong = a filled green badge, moderate = blue, emerging = purple. The word is always there.
struct SignalEvidenceBadge: View {
    let evidence: SignalEvidence

    var body: some View {
        let style = evidence.badge
        Text(evidence.word)
            .font(FATypography.sans(10.5, .bold, relativeTo: .caption2))
            .foregroundStyle(Color(hex: style.foregroundHex))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: style.backgroundHex, opacity: style.backgroundOpacity), in: Capsule())
            .accessibilityLabel(String(localized: "signal.evidence.a11y", defaultValue: "Evidence: \(evidence.word)"))
    }
}

// MARK: What it feels like

/// One end of "What it feels like": a word chip (green for the good end, red-orange for the other) and the sentence.
struct SignalFeelsLine: View {
    let word: String
    let text: String
    let tintHex: UInt32
    let textHex: UInt32

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(word)
                .font(FATypography.sans(11, .bold, relativeTo: .caption))
                .foregroundStyle(Color(hex: textHex))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color(hex: tintHex, opacity: 0.16), in: Capsule())
                .overlay { Capsule().strokeBorder(Color(hex: tintHex, opacity: 0.35), lineWidth: 1) }
                .fixedSize()
            Text(text)
                .font(FATypography.sans(13.5, relativeTo: .callout))
                .foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: What influences it

/// The glyph for an influence's `icon` name. An unknown name shows a neutral dot — the content, not the app, decides.
enum SignalGlyph {
    static func symbol(_ name: String) -> String {
        switch name {
        case "sleep": "moon.zzz.fill"
        case "move": "figure.walk"
        case "food": "fork.knife"
        case "water": "drop.fill"
        case "stress": "bolt.fill"
        case "mind": "brain.head.profile"
        case "caffeine": "cup.and.saucer.fill"
        case "light": "sun.max.fill"
        case "alcohol": "wineglass.fill"
        case "social": "person.2.fill"
        case "screen": "iphone"
        case "breath": "wind"
        case "time": "clock.fill"
        default: "circle.fill"
        }
    }

    /// The four plate cards.
    static func plate(_ key: String) -> String {
        switch key {
        case "carbs": "circle.hexagongrid.fill"
        case "protein": "dumbbell.fill"
        case "fat": "drop.fill"
        case "fibre": "leaf.fill"
        default: "fork.knife"
        }
    }
}

/// One influence: its glyph, the line, the evidence badge, and a tap-to-open "Why".
struct SignalInfluenceRow: View {
    let influence: SignalExplanation.Influence
    let tint: Color
    let isOpen: Bool
    let onToggle: () -> Void

    var body: some View {
        if influence.why.isEmpty {
            rowBody
        } else {
            Button(action: onToggle) { rowBody }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen
                    ? String(localized: "signal.about.why.hint.close", defaultValue: "Hides the reason")
                    : String(localized: "signal.about.why.hint.open", defaultValue: "Shows the reason"))
        }
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.13))
                Image(systemName: SignalGlyph.symbol(influence.icon)).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(influence.line)
                    .font(FATypography.sans(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SignalEvidenceBadge(evidence: SignalEvidence(raw: influence.evidence))
                    Spacer(minLength: 0)
                    if !influence.why.isEmpty {
                        HStack(spacing: 3) {
                            Text(String(localized: "signal.about.why", defaultValue: "Why"))
                                .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isOpen ? 180 : 0))
                        }
                        .foregroundStyle(FAColor.forest)
                    }
                }
                if isOpen, !influence.why.isEmpty {
                    Text(influence.why)
                        .font(FATypography.sans(13, relativeTo: .footnote))
                        .foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityValue(influence.why.isEmpty ? "" : (isOpen
            ? String(localized: "signal.about.why.open", defaultValue: "Expanded")
            : String(localized: "signal.about.why.closed", defaultValue: "Collapsed")))
    }
}

// MARK: How it connects — the mini map

/// This signal in the centre, an arrow to or from each signal it links to, a short word on each arrow. Drawn with a
/// `Canvas` from `SignalMapLayout`'s numbers; line style = how strong the evidence is; the arrow's colour = the signal it
/// leaves. VoiceOver gets the connections as a sentence per arrow instead of the picture.
struct SignalConnectionMap: View {
    let centre: String
    let connections: [SignalExplanation.Connection]

    var body: some View {
        let layout = SignalMapLayout.make(centre: centre, connections: connections)
        VStack(alignment: .leading, spacing: 10) {
            Canvas { context, size in
                MapPainter.draw(layout, in: &context, size: size)
            }
            .aspectRatio(layout.size.width / layout.size.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MapPainter.summary(layout))
            legend
        }
        // Diagram text is drawn at fixed sizes in a scaled space; it stays inside its pills at every Dynamic Type size.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// "Arrows show which way it flows. Line style shows how strong the evidence is." and the three line samples.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                ForEach(SignalEvidence.allCases, id: \.self) { evidence in
                    HStack(spacing: 5) {
                        LineSample(style: evidence.line).frame(width: 26, height: 6)
                        Text(evidence.word).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

/// The drawing itself, free of the view so the Canvas closure captures only the layout.
private enum MapPainter {
    static func tint(_ key: String) -> Color { Color(hex: SignalAboutKey(rawValue: key)?.tintHex ?? 0x7A796F) }
    static func name(_ key: String) -> String { SignalAboutKey(rawValue: key)?.nodeName ?? key.capitalized }
    static func face(_ size: CGFloat, bold: Bool) -> Font { .custom(bold ? FATypography.sansBoldFace : FATypography.sansSemiboldFace, fixedSize: size) }

    static func summary(_ layout: SignalMapLayout) -> String {
        layout.edges.map { edge in
            let sentence = String(localized: "signal.about.map.edge", defaultValue: "\(name(edge.from)) to \(name(edge.to)): \(edge.label)")
            return "\(sentence), \(edge.evidence.word)"
        }.joined(separator: ". ")
    }

    static func draw(_ layout: SignalMapLayout, in context: inout GraphicsContext, size: CGSize) {
        let scale = size.width / layout.size.width
        context.scaleBy(x: scale, y: scale)

        for edge in layout.edges {
            let colour = tint(edge.from).opacity(0.82)
            let line = edge.evidence.line
            var path = Path()
            path.move(to: edge.start)
            path.addQuadCurve(to: edge.end, control: edge.control)
            context.stroke(path, with: .color(colour),
                           style: StrokeStyle(lineWidth: line.width, lineCap: line.roundCap ? .round : .butt, dash: line.dash))
            for head in edge.heads {
                var arrow = Path()
                arrow.move(to: head.tip)
                arrow.addLine(to: head.left)
                arrow.addLine(to: head.right)
                arrow.closeSubpath()
                context.fill(arrow, with: .color(colour))
            }
        }

        for node in layout.nodes {
            let rect = CGRect(x: node.center.x - node.half.width, y: node.center.y - node.half.height,
                              width: node.half.width * 2, height: node.half.height * 2)
            let shape = Path(roundedRect: rect, cornerRadius: node.half.height)
            let colour = tint(node.key)
            if node.isCentre {
                context.fill(shape, with: .color(colour))
            } else {
                context.fill(shape, with: .color(Color.white.opacity(0.9)))
                context.stroke(shape, with: .color(colour), lineWidth: 1.6)
            }
            let label = Text(name(node.key)).font(face(node.isCentre ? 12.5 : 11, bold: true))
                .foregroundStyle(node.isCentre ? Color.white : FAColor.ink)
            context.draw(context.resolve(label), at: node.center, anchor: .center)
        }

        for edge in layout.edges where !edge.label.isEmpty {
            let resolved = context.resolve(Text(edge.label).font(face(8.8, bold: false)).foregroundStyle(FAColor.ink))
            let measured = resolved.measure(in: CGSize(width: 140, height: 30))
            let pill = CGRect(x: edge.labelPoint.x - measured.width / 2 - 3, y: edge.labelPoint.y - measured.height / 2 - 1,
                              width: measured.width + 6, height: measured.height + 2)
            context.fill(Path(roundedRect: pill, cornerRadius: 5), with: .color(Color.white.opacity(0.78)))
            context.draw(resolved, at: edge.labelPoint, anchor: .center)
        }
    }
}

private struct LineSample: View {
    let style: SignalEvidence.LineStyle

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 3))
            path.addLine(to: CGPoint(x: 26, y: 3))
        }
        .stroke(FAColor.inkSecondary, style: StrokeStyle(lineWidth: style.width, lineCap: style.roundCap ? .round : .butt, dash: style.dash))
    }
}

// MARK: What's on your plate (Energy)

struct SignalPlateCard: View {
    let item: SignalExplanation.PlateItem
    let tint: Color

    var body: some View {
        let evidence = SignalEvidence(raw: item.evidence)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: SignalGlyph.plate(item.key)).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(item.title).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
            }
            Text(item.line)
                .font(FATypography.sans(12.5, relativeTo: .caption))
                .foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !item.evidence.isEmpty { SignalEvidenceBadge(evidence: evidence) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: evidence.badge.backgroundHex, opacity: 0.4), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Easy ways to influence it

/// One action with "+ Add to my day". The button opens the matching action card of the bank (where the member adds it)
/// or, with no matching card, the bank itself — it never makes a habit up.
struct SignalActionRow: View {
    let text: String
    let alreadyAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        FACard {
            HStack(alignment: .center, spacing: 12) {
                Text(text)
                    .font(FATypography.sans(14, relativeTo: .subheadline))
                    .foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button(action: onAdd) {
                    Text(alreadyAdded
                         ? String(localized: "signal.about.added", defaultValue: "In your day")
                         : String(localized: "signal.about.add", defaultValue: "+ Add to my day"))
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(alreadyAdded ? FAColor.forest : Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(alreadyAdded ? FAColor.forestSoft.opacity(0.16) : FAColor.forest, in: Capsule())
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "signal.about.add.hint", defaultValue: "Opens the action"))
            }
        }
    }
}

// MARK: Related reading

struct SignalRelatedCard: View {
    let article: LibraryArticle
    let tint: Color

    var body: some View {
        FACard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.35), Color.white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .overlay { Image(systemName: "book.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(tint) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title)
                        .font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "signal.about.fromLibrary", defaultValue: "From your library"))
                        .font(FATypography.sans(11.5, relativeTo: .caption))
                        .foregroundStyle(FAColor.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: Sources

/// The list at the bottom of the page: small and muted, one line per source, no numbers in the text above.
struct SignalSourcesList: View {
    let sources: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "signal.about.sources", defaultValue: "Sources").uppercased())
                .font(FATypography.label)
                .tracking(0.9)
                .foregroundStyle(FAColor.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                Text(source)
                    .font(FATypography.sans(11.5, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
