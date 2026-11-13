import SwiftUI

// Small pieces the Trends page and its detail pages share — the owner-validated mockup v2 (2026-11-10).

/// The little uppercase caption over a card ("YOUR FUNCTIONAL SCORE").
struct TrendLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(FATypography.label)
            .tracking(0.9)
            .foregroundStyle(FAColor.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 7 / 14 / 28 days — one control, the same on the page and on every detail page.
struct TrendWindowPicker: View {
    let selection: TrendWindow
    let onSelect: (TrendWindow) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrendWindow.allCases) { window in
                let on = selection == window
                Button { onSelect(window) } label: {
                    Text(window.label)
                        .font(FATypography.sans(13, on ? .bold : .medium, relativeTo: .footnote))
                        .foregroundStyle(on ? FAColor.ink : FAColor.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The one-line read of a signal, in its sparkle box. The wording is `TrendSentence`'s fixed set.
struct TrendSentenceBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FAColor.forest)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .font(FATypography.sans(13.5, relativeTo: .callout))
                .foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(FAColor.forest.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forest.opacity(0.18), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// A line over the window's days. Gaps (a day not logged) break the line; the dots are the logged days.
/// `columns` centres each point in its day's column, so a value strip under the curve lines up with it.
struct TrendCurve: View {
    let values: [Double?]
    let tint: Color
    var showAllDots = false
    var columns = false
    var lineWidth: CGFloat = 1.8

    private var domain: ClosedRange<Double> {
        let present = values.compactMap { $0 }
        guard let lo = present.min(), let hi = present.max() else { return 0...10 }
        let mid = (lo + hi) / 2
        let span = max(hi - lo + 2, 4)
        return (mid - span / 2)...(mid + span / 2)
    }

    private func points(in size: CGSize) -> [CGPoint?] {
        let n = values.count
        let range = domain
        let inset: CGFloat = 4
        let height = max(1, size.height - 2 * inset)
        return values.enumerated().map { i, value in
            guard let value else { return nil }
            let x: CGFloat
            if columns { x = (CGFloat(i) + 0.5) * size.width / CGFloat(max(1, n)) }
            else if n > 1 { x = inset + CGFloat(i) * (size.width - 2 * inset) / CGFloat(n - 1) }
            else { x = size.width / 2 }
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            return CGPoint(x: x, y: size.height - inset - CGFloat(t) * height)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            let last = pts.lastIndex(where: { $0 != nil })
            ZStack {
                Path { path in
                    var open = false
                    for point in pts {
                        if let point {
                            if open { path.addLine(to: point) } else { path.move(to: point); open = true }
                        } else {
                            open = false
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                ForEach(pts.indices, id: \.self) { i in
                    if let point = pts[i], showAllDots || i == last {
                        Circle()
                            .fill(tint)
                            .frame(width: i == last ? 8 : 5, height: i == last ? 8 : 5)
                            .position(point)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One bar per day on a zero baseline — hours asleep.
struct TrendBars: View {
    let values: [Double?]
    let tint: Color
    /// The top of the scale (hours); bars never exceed it.
    let top: Double
    var gridlines: [Double] = []

    var body: some View {
        GeometryReader { geo in
            let n = max(1, values.count)
            let gap: CGFloat = n > 14 ? 2 : 4
            let barWidth = max(2, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            ZStack(alignment: .bottomLeading) {
                ForEach(gridlines, id: \.self) { line in
                    Rectangle()
                        .fill(FAColor.inkSecondary.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, CGFloat(line / top) * geo.size.height)
                }
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(values.indices, id: \.self) { i in
                        let v = values[i]
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint.opacity(i == values.count - 1 ? 1 : 0.55))
                            .frame(width: barWidth, height: v == nil ? 0 : max(3, CGFloat(min(top, max(0, v ?? 0)) / top) * geo.size.height))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The labelled value under each day of a curve or bar chart: the value, the weekday's initial, the date.
/// A 28-day window has no room for all of it, so it keeps the value and dates every seventh day.
struct TrendValueStrip: View {
    let days: [String]
    /// The value text of each day, nil = not logged.
    let labels: [String?]
    let tint: Color

    var body: some View {
        let dense = days.count > 14
        HStack(spacing: 0) {
            ForEach(days.indices, id: \.self) { i in
                let last = i == days.count - 1
                VStack(spacing: 2) {
                    Text(labels[i] ?? "·")
                        .font(FATypography.sans(dense ? 8.5 : 11, .bold, relativeTo: .caption2))
                        .foregroundStyle(labels[i] == nil ? FAColor.inkMuted : (last ? FAColor.forest : FAColor.ink))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !dense {
                        Text(TrendsFormat.weekdayInitial(days[i]))
                            .font(FATypography.sans(9, last ? .bold : .regular, relativeTo: .caption2))
                            .foregroundStyle(last ? FAColor.forest : FAColor.inkMuted)
                    }
                    Text(!dense || i % 7 == 0 || last ? TrendsFormat.dayNumber(days[i]) : " ")
                        .font(FATypography.sans(9, last ? .bold : .regular, relativeTo: .caption2))
                        .foregroundStyle(last ? FAColor.forest : FAColor.inkMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Six equal segments, one per signal in its colour, each filled to that signal's value.
struct TrendScoreRing: View {
    let chips: [TrendsEngine.Chip]
    let value: Int?
    var size: CGFloat = 150
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            ForEach(Array(chips.enumerated()), id: \.element.id) { i, chip in
                segment(i, fill: (chip.marker ?? 0) / 100, tint: Color(hex: chip.signal.tintHex))
            }
            VStack(spacing: 0) {
                Text(value.map(String.init) ?? "·")
                    .font(FATypography.display(40, relativeTo: .largeTitle))
                    .foregroundStyle(value == nil ? FAColor.inkSecondary : FAColor.ink)
                Text(String(localized: "trends.score.outOf", defaultValue: "out of 100"))
                    .font(FATypography.sans(11, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "trends.score.a11y", defaultValue: "Functional score \(shown) out of 100"))
    }

    private var shown: String { value.map(String.init) ?? "–" }

    private func segment(_ i: Int, fill: Double, tint: Color) -> some View {
        let gap = 0.014
        let length = 1.0 / 6.0 - gap
        let start = Double(i) / 6.0 + gap / 2
        let filled = max(0, min(1, fill))
        return ZStack {
            Circle()
                .trim(from: start, to: start + length)
                .stroke(Color(white: 0.47, opacity: 0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            Circle()
                .trim(from: start, to: start + length * filled)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        }
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
    }
}

/// A chip of words — a pill the member ticked, a reaction they noted. A `tone` (green / orange / red) or a
/// supplement `.blue` colours it; the word is always there, so colour is never the only signal.
struct TrendWordChip: View {
    let text: String
    var tint: Color? = nil
    var tone: ReactionTone? = nil
    var isSupplement = false

    var body: some View {
        let style = Self.style(tone: tone, isSupplement: isSupplement)
        Text(text)
            .font(FATypography.sans(11.5, .medium, relativeTo: .caption))
            .foregroundStyle(style?.text ?? FAColor.inkSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(style?.fill ?? (tint ?? Color(white: 0.47)).opacity(0.14), in: Capsule())
    }

    private static func style(tone: ReactionTone?, isSupplement: Bool) -> (text: Color, fill: Color)? {
        if isSupplement { return (Color(hex: 0x1D4E89), Color(hex: 0x4F86C6, opacity: 0.15)) }
        switch tone {
        case .positive?: return (Color(hex: 0x2E5438), Color(hex: 0x4A8A5C, opacity: 0.16))
        case .mild?: return (Color(hex: 0xC2410C), Color(hex: 0xF97316, opacity: 0.14))
        case .strong?: return (Color(hex: 0xB42318), Color(hex: 0xEF4444, opacity: 0.13))
        case .neutral?, nil: return nil
        }
    }
}

/// Chips that wrap onto as many lines as they need.
struct TrendFlow: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "‹ Trends" over a detail page's title and its one-line subtitle.
struct TrendDetailHeader<Subtitle: View>: View {
    let title: String
    @ViewBuilder let subtitle: Subtitle
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
            Text(title)
                .font(FATypography.display(34, relativeTo: .largeTitle))
                .foregroundStyle(FAColor.ink)
                .accessibilityAddTraits(.isHeader)
            subtitle
                .font(FATypography.sans(14, relativeTo: .subheadline))
                .foregroundStyle(FAColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
