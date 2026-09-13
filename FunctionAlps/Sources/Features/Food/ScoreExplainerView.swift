import SwiftUI

/// One score, explained for THIS member — the Expo `score-explainer/[score].tsx`, as a sheet: the score-coloured
/// hero with the real 7-day average and trend (and this meal's score when opened from one), "Why it matters
/// for you" from their objectives and history, "What we've noticed" from the pattern engine, three tips or a
/// congratulation, the 14-day path, the science on request, and the mandatory About-this-score wording.
struct ScoreExplainerView: View {
    let kind: MealScoreKind
    var mealScore: Int? = nil

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var history: [ScoreHistory.Day] = []
    @State private var objectives: [String] = []
    @State private var patterns: [UserPattern] = []
    @State private var showScience = false

    private var copy: ScoreExplainerCopy { .copy(for: kind) }
    private var avg: Int? { ScoreHistory.recentAvg(history, kind) }
    private var trend: ScoreHistory.Trend? { ScoreHistory.trend(history, kind) }
    private var context: ScorePersonalization.Context { .init(avg: avg, trend: trend) }
    private var excellent: Bool { (avg ?? 0) >= 85 && avg != nil }
    private var why: String { ScorePersonalization.whyItMatters(kind, objectives: objectives, context) ?? copy.whyForYou }
    private var tips: [String] { ScorePersonalization.tips(kind, objectives: objectives, context) }
    private var noticed: [String] { PatternText.forScore(patterns, kind).compactMap(PatternText.sentence).prefix(2).map { $0 } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(copy.label).font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.charcoal)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
                }
                .padding(.vertical, 12)

                hero

                heading(String(localized: "scoreX.whyForYou", defaultValue: "Why it matters for you"))
                Text(why)
                    .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FAColor.forestSoft.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.28), lineWidth: 1) }

                if !noticed.isEmpty {
                    heading(String(localized: "scoreX.noticed", defaultValue: "What we've noticed"))
                    list(noticed) { s in
                        Text(s).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }

                if excellent {
                    heading(String(localized: "scoreX.keepItUp", defaultValue: "Keep it up"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "scoreX.excellent", defaultValue: "◆ Excellent")).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
                        Text(copy.congrats).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FAColor.forestSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.3), lineWidth: 1) }
                } else {
                    heading(String(localized: "scoreX.makeBetter", defaultValue: "Make it even better"))
                    list(tips) { tip in
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                                .frame(width: 21, height: 21).background(FAColor.forestSoft.opacity(0.18), in: Circle())
                            Text(tip).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                heading(String(localized: "scoreX.trend14", defaultValue: "Your trend · 14 days"))
                Group {
                    if ScoreHistory.hasEnoughData(history, kind, min: 1) {
                        TrendPath(values: ScoreHistory.series(history, kind), color: copy.color).frame(height: 68)
                    } else {
                        Text(String(localized: "scoreX.trend.empty", defaultValue: "Not enough scored meals yet · your 14-day trend builds as you log."))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(FAGlassSurface(cornerRadius: 13))

                if !showScience {
                    Button { withAnimation(.easeInOut(duration: 0.25)) { showScience = true } } label: {
                        Text(String(localized: "scoreX.science.cta", defaultValue: "Understand the science →"))
                            .font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(copy.color)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .modifier(FAGlassSurface(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                } else {
                    heading(String(localized: "scoreX.whatItIs", defaultValue: "What it is"))
                    Text(copy.whatItIs).font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    heading(String(localized: "scoreX.whatMoves", defaultValue: "What moves it"))
                    HStack(alignment: .top, spacing: 9) {
                        movesColumn("↑ " + copy.upLabel, copy.up, tint: FAColor.scoreInflammation)
                        movesColumn("↓ " + copy.downLabel, copy.down, tint: FAColor.forestSoft)
                    }
                    heading(String(localized: "scoreX.theScience", defaultValue: "The science"))
                    Text(copy.science).font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }

                // MANDATORY on every surface that shows a score — legal pack 07. Verbatim; do not reword.
                VStack(alignment: .leading, spacing: 6) {
                    Text(ScoreLegal.aboutTitle).font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    Text(ScoreLegal.aboutBody).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    if kind == .glycemic {
                        Text(ScoreLegal.carbNote).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1) }
                .padding(.top, 26)

                // The hub: every score the app shows, in one place. The sheet closes first so the push lands on the tab's stack.
                Button {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        router.push(.scores)
                    }
                } label: {
                    Text(String(localized: "scoreX.exploreAll", defaultValue: "Explore all scores →"))
                        .font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(copy.color)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .faWall()
        .task { await load() }
    }

    // MARK: Pieces

    private var trendLabel: String {
        switch trend {
        case .up: String(localized: "scoreX.trending.up", defaultValue: "trending up ↑")
        case .down: String(localized: "scoreX.trending.down", defaultValue: "trending down ↓")
        case .flat: String(localized: "scoreX.trending.flat", defaultValue: "trending steady →")
        case nil: String(localized: "scoreX.trending.none", defaultValue: "building your baseline")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "scoreX.kicker", defaultValue: "◆ Meal score").uppercased())
                .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(Color.white.opacity(0.82))
            Text(String(localized: "scoreX.impact", defaultValue: "\(copy.label) impact"))
                .font(FATypography.display(23, relativeTo: .title2)).foregroundStyle(.white).padding(.top, 7)
            Text(copy.subtitle).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(Color.white.opacity(0.9)).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 11) {
                Text(avg.map(String.init) ?? "·").font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(.white)
                Text(avgCaption).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(Color.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.top, 13)
            if let mealScore {
                Text(String(localized: "scoreX.thisMeal", defaultValue: "This meal · \(mealScore)"))
                    .font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.white.opacity(0.16), in: Capsule())
                    .padding(.top, 8)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                copy.color
                LinearGradient(colors: [.clear, Color.black.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(copy.color.opacity(0.4), lineWidth: 1) }
    }

    private var avgCaption: String {
        guard avg != nil else { return String(localized: "scoreX.avg.empty", defaultValue: "Your 7-day average appears here.\nLog meals to build it.") }
        let line1 = String(localized: "scoreX.avg.line", defaultValue: "Your 7-day average · \(trendLabel)")
        let line2 = String(localized: "scoreX.avg.higher", defaultValue: "Higher = better.")
        let line3 = excellent ? String(localized: "scoreX.avg.excelling", defaultValue: "You're excelling.") : String(localized: "scoreX.avg.onTrack", defaultValue: "You're on track.")
        return line1 + "\n" + line2 + " " + line3
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(FATypography.sans(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
            .padding(.top, 22).padding(.bottom, 9)
    }

    private func list<Row: View>(_ items: [String], @ViewBuilder row: @escaping (String) -> Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                row(item)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(FAColor.separator).frame(height: 1) } }
            }
        }
        .padding(.horizontal, 14)
        .modifier(FAGlassSurface(cornerRadius: 13))
    }

    private func movesColumn(_ title: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(tint).padding(.bottom, 3)
            ForEach(items, id: \.self) { item in
                Text("• " + item).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        guard let member = try? await dependencies.members.currentMember() else { return }
        let meals = dependencies.meals
        let backend = dependencies.backend
        async let recent = meals.recentMeals(patientId: member.patientId)
        async let profile = backend.memberProfile(patientId: member.patientId)
        async let found = meals.patterns(patientId: member.patientId)
        history = ScoreHistory.build((try? await recent) ?? [])
        objectives = (try? await profile)?.healthGoals ?? []
        patterns = await found
    }
}

/// 14 day slots across the width, score 0–100 mapped to the height; days without data break the line.
struct TrendPath: View {
    let values: [Int?]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = max(values.count - 1, 1)
            let points: [CGPoint?] = values.enumerated().map { i, v in
                v.map { CGPoint(x: 4 + CGFloat(i) * (w - 8) / CGFloat(n), y: h - 4 - CGFloat($0) / 100 * (h - 8)) }
            }
            let segments = Self.segments(points)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.3)); p.addLine(to: CGPoint(x: w, y: h * 0.3))
                    p.move(to: CGPoint(x: 0, y: h * 0.68)); p.addLine(to: CGPoint(x: w, y: h * 0.68))
                }
                .stroke(FAColor.separator, lineWidth: 1)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if seg.count > 1 {
                        Path { p in
                            p.move(to: seg[0])
                            for pt in seg.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    } else if let only = seg.first {
                        Circle().fill(color).frame(width: 5, height: 5).position(only)
                    }
                }
                if let last = segments.last?.last {
                    Circle().fill(color).frame(width: 7, height: 7).position(last)
                }
            }
        }
    }

    static func segments(_ points: [CGPoint?]) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var cur: [CGPoint] = []
        for p in points {
            if let p { cur.append(p) } else if !cur.isEmpty { out.append(cur); cur = [] }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
