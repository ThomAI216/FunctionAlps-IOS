import SwiftUI

/// The web app's Trends tab (`app/(tabs)/health.tsx`): the Functional Score crown, Gut Intelligence,
/// the check-in entry. Every number comes from `member-scores` — the app renders, it never scores.
struct TrendsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: TrendsViewModel?

    var body: some View {
        ZStack {
            if let model { content(model) }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = TrendsViewModel(backend: dependencies.backend, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
        .onAppear {
            if let model, model.state.value != nil { Task { await model.load(refresh: true) } }
        }
    }

    @ViewBuilder
    private func content(_ model: TrendsViewModel) -> some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "trends.error.title", defaultValue: "Couldn't compute your scores"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            FAErrorState(title: String(localized: "trends.error.title", defaultValue: "Couldn't compute your scores"), message: String(localized: "home.notRegistered.message", defaultValue: "This account isn't linked to a FunctionAlps client profile yet. Finish onboarding on the FunctionAlps web app, then come back."), retryTitle: nil, retry: nil)
        case .loaded(let scores):
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    FunctionalScoreCrown(scores: scores, open: model.openPillar) { model.toggle($0) }
                    GutIntelligenceCard(breakdown: scores.gut)
                    DailyCheckinCTA(slot: dependencies.checkins.currentSlot)
                }
                .padding(.horizontal, 16)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(refresh: true) }
        }
    }
}

/// Wheel (left) + 14-day chart (right), then the three pillar wheel-tiles; tapping one expands
/// inline: tip → factor bars → 14-day bars.
struct FunctionalScoreCrown: View {
    let scores: MemberScores
    let open: MemberScores.Pillar?
    let onToggle: (MemberScores.Pillar) -> Void
    private static let green = Color(hex: 0x8FBF97)

    private var series: [Int] { scores.crownSeries.compactMap { $0 } }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    ActivityRing(pct: Double(scores.composite.intScore ?? 0) / 100, color: Self.green) {
                        VStack(spacing: 1) {
                            Text(scores.composite.intScore.map(String.init) ?? "·")
                                .font(FATypography.display(30, relativeTo: .title))
                                .foregroundStyle(scores.composite.intScore == nil ? FAColor.inkSecondary : FAColor.ink)
                            Text(String(localized: "home.hero.functional", defaultValue: "Functional").uppercased())
                                .font(FATypography.sans(7.5, .semibold, relativeTo: .caption2))
                                .tracking(1.2)
                                .foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                    VStack(alignment: .trailing, spacing: 6) {
                        trendPill
                        if series.count >= 2 {
                            ScoreBarTrend(values: scores.crownSeries, color: Self.green, height: 84)
                            HStack {
                                Text(series.count >= 14 ? String(localized: "trends.days14", defaultValue: "14 days") : String(localized: "trends.daysN", defaultValue: "\(series.count) days"))
                                    .font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                                Spacer()
                                Text(String(localized: "day.today", defaultValue: "Today"))
                                    .font(FATypography.sans(10, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.ink)
                            }
                        } else {
                            Text(series.count == 1
                                 ? String(localized: "trends.baseline.one", defaultValue: "Baseline set · one more check-in and your bars grow.")
                                 : String(localized: "trends.baseline.none", defaultValue: "Complete a check-in to start your 14-day trend."))
                                .font(FATypography.sans(12, relativeTo: .caption))
                                .foregroundStyle(FAColor.inkSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Divider().overlay(FAColor.separator).padding(.top, 14)

                HStack(spacing: 8) {
                    ForEach(MemberScores.Pillar.allCases, id: \.self) { pillar in
                        let v = scores.breakdown(pillar).intScore
                        let active = open == pillar
                        Button { onToggle(pillar) } label: {
                            VStack(spacing: 6) {
                                ActivityRing(pct: Double(v ?? 0) / 100, color: Color(hex: pillar.tintHex), size: 62, strokeWidth: 8, trackColor: Color(white: 0.47, opacity: 0.16)) {
                                    Text(v.map(String.init) ?? "·")
                                        .font(FATypography.display(17, relativeTo: .headline))
                                        .foregroundStyle(v == nil ? FAColor.inkSecondary : FAColor.ink)
                                }
                                Text(pillar.title)
                                    .font(FATypography.sans(11, .semibold, relativeTo: .caption))
                                    .foregroundStyle(active ? FAColor.ink : FAColor.inkSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(active ? Color.black.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pillar.title): \(v.map(String.init) ?? "·")")
                    }
                }
                .padding(.top, 14)

                if let open {
                    PillarExpansion(pillar: open, breakdown: scores.breakdown(open))
                        .padding(.top, 12)
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: open)
    }

    private var trendPill: some View {
        let (label, symbol): (String, String) = {
            switch scores.trend {
            case .up: (String(localized: "trend.up", defaultValue: "Trending up"), "arrow.up.right")
            case .down: (String(localized: "trend.down", defaultValue: "Off baseline"), "arrow.down.right")
            case .flat: (String(localized: "trend.flat", defaultValue: "Holding steady"), "minus")
            case nil: (String(localized: "trend.none", defaultValue: "Building baseline"), "minus")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(label).font(FATypography.sans(11, .semibold, relativeTo: .caption))
        }
        .foregroundStyle(FAColor.ink)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color(red: 74 / 255, green: 138 / 255, blue: 92 / 255, opacity: 0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(red: 74 / 255, green: 138 / 255, blue: 92 / 255, opacity: 0.28), lineWidth: 1))
    }
}

/// Tip first, then the factors, then the 14-day bars — for the tapped pillar.
struct PillarExpansion: View {
    let pillar: MemberScores.Pillar
    let breakdown: ScoreBreakdown
    private static let bad = Color(hex: 0xC2554C)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(FAColor.separator)
            if let tip = breakdown.tip {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tip.summaryText(label: pillar.title))
                        .font(FATypography.sans(13, .semibold, relativeTo: .callout)).foregroundStyle(FAColor.ink)
                    if !tip.good.isEmpty {
                        Text(tip.good).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    }
                    if !tip.bad.isEmpty {
                        Text(tip.bad).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(Self.bad)
                    }
                }
            }
            VStack(spacing: 7) {
                ForEach(breakdown.factors.filter { $0.value != nil }) { factor in
                    FactorBarRow(factor: factor, tint: Color(hex: pillar.tintHex))
                }
            }
            if breakdown.series14d.contains(where: { $0 != nil }) {
                VStack(alignment: .leading, spacing: 4) {
                    ScoreBarTrend(values: breakdown.intSeries, color: Color(hex: pillar.tintHex), height: 78)
                    Text(String(localized: "trends.last14", defaultValue: "Last 14 days"))
                        .font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }
}

struct FactorBarRow: View {
    let factor: ScoreFactor
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Text(factor.label)
                .font(FATypography.sans(11.5, .medium, relativeTo: .caption))
                .foregroundStyle(FAColor.inkSecondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            HashedBar(color: tint, pct: Double(factor.intValue ?? 0) / 100, height: 9, raised: true)
            Text(factor.intValue.map(String.init) ?? "·")
                .font(FATypography.sans(12, .bold, relativeTo: .caption))
                .foregroundStyle(factor.value == nil ? FAColor.inkSecondary : FAColor.ink)
                .frame(width: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 14 hashed vertical bars on a fixed 0–100 scale with a ruler on the right (ScoreBarTrend.tsx).
struct ScoreBarTrend: View {
    let values: [Int?]
    let color: Color
    var height: CGFloat = 78
    private let marks: [Int] = [25, 50, 75, 100]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ZStack(alignment: .bottom) {
                ForEach(marks, id: \.self) { m in
                    Rectangle().fill(FAColor.separator.opacity(0.45)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, CGFloat(m) / 100 * height)
                }
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                        let empty = v == nil
                        let h: CGFloat = empty ? 3 : max(3, CGFloat(max(0, min(100, v ?? 0))) / 100 * height)
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(empty ? AnyShapeStyle(FAColor.separator) : AnyShapeStyle(LinearGradient(colors: [color.shaded(0.35), color, color.shaded(-0.25)], startPoint: .top, endPoint: .bottom)))
                            if !empty {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(ImagePaint(image: Image(uiImage: HatchTile.image(color: color, cell: 6, lineWidth: 1.5, opacity: 0.35))))
                                Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                        .opacity(empty ? 0.5 : 1)
                    }
                }
            }
            .frame(height: height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(marks.reversed(), id: \.self) { m in
                    Text("\(m)").font(FATypography.sans(8, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
                    if m != 25 { Spacer(minLength: 0) }
                }
            }
            .frame(width: 24, height: height * 0.75, alignment: .top)
            .offset(y: -height * 0.25 + 4)
        }
        .accessibilityHidden(true)
    }
}

/// Gut Intelligence: wheel + tip + factor bars + 14-day bars (GutIntelligenceCard.tsx).
struct GutIntelligenceCard: View {
    let breakdown: ScoreBreakdown
    private static let tint = Color(hex: 0x86B8A6)
    private static let bad = Color(hex: 0xC2554C)

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "trends.gut.title", defaultValue: "Gut Intelligence"))
                    .font(FATypography.sans(13, .semibold, relativeTo: .callout)).foregroundStyle(FAColor.ink)
                HStack(alignment: .center, spacing: 14) {
                    ActivityRing(pct: Double(breakdown.intScore ?? 0) / 100, color: Self.tint, size: 78, strokeWidth: 10, trackColor: Color(red: 120 / 255, green: 150 / 255, blue: 130 / 255, opacity: 0.3)) {
                        VStack(spacing: 0) {
                            Text(breakdown.intScore.map(String.init) ?? "·")
                                .font(FATypography.display(22, relativeTo: .title2))
                                .foregroundStyle(breakdown.intScore == nil ? FAColor.inkSecondary : FAColor.ink)
                            Text(String(localized: "trends.gut.short", defaultValue: "Gut").uppercased())
                                .font(FATypography.sans(7, .semibold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                    if let tip = breakdown.tip {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tip.summaryText(label: String(localized: "trends.gut.label", defaultValue: "gut")))
                                .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                            if !tip.good.isEmpty { Text(tip.good).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.ink) }
                            if !tip.bad.isEmpty { Text(tip.bad).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(Self.bad) }
                        }
                    }
                }
                VStack(spacing: 7) {
                    ForEach(breakdown.factors.filter { $0.value != nil }) { factor in
                        FactorBarRow(factor: factor, tint: Self.tint)
                    }
                }
                if breakdown.series14d.contains(where: { $0 != nil }) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScoreBarTrend(values: breakdown.intSeries, color: Self.tint, height: 78)
                        Text(String(localized: "trends.last14", defaultValue: "Last 14 days"))
                            .font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
        }
    }
}

/// The single entry into the daily check-in (DailyCheckinCTA.tsx) — opens the current moment.
struct DailyCheckinCTA: View {
    let slot: MomentSlot

    var body: some View {
        NavigationLink(value: Route.checkin(slot)) {
            FACard {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous).fill(FAColor.accent.opacity(0.14))
                        RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(FAColor.accent.opacity(0.3), lineWidth: 1)
                        Image(systemName: "sun.max").font(.system(size: 20)).foregroundStyle(FAColor.ink)
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "trends.checkin.title", defaultValue: "Daily Check-in"))
                            .font(FATypography.sans(16, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "trends.checkin.sub", defaultValue: "Log today’s signals in under 2 minutes"))
                            .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Text(String(localized: "trends.checkin.start", defaultValue: "Start")).font(FATypography.sans(12, .semibold, relativeTo: .caption))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(FAColor.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(FAColor.accent.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(FAColor.accent.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
