import SwiftUI

/// The Trends tab, reworked after the owner-validated mockup (2026-11-10): the member's data as they logged it —
/// the functional score (six equal signals), the plan day by day, their devices, each signal (tap to open it in
/// place, tap again for its page), what they ate and how they felt, and the patterns their practitioner shared.
/// Every number is a count, an average or a plain read-back of the member's own logs (`TrendsEngine`); the one
/// sentence per signal comes from a fixed, owner-approved set (`TrendSentence`). Nothing here scores or diagnoses.
struct TrendsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var expanded: TrendSignal? = TrendsView.initialExpanded

    /// The showcase screenshot of an open Energy row starts with it open (there is no finger in the simulator).
    private static var initialExpanded: TrendSignal? {
        #if DEBUG
        return Showcase.screen == .trendsEnergyOpen ? .energy : nil
        #else
        return nil
        #endif
    }

    var body: some View {
        let trends = dependencies.trends
        ZStack {
            content(trends)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await trends.load() }
        .onAppear {
            // The scores hub used to hand a pillar over here; Trends no longer has pillars, so the hand-over is dropped.
            router.pendingPillar = nil
            Task { await trends.refreshIfStale() }
        }
    }

    @ViewBuilder
    private func content(_ trends: TrendsService) -> some View {
        switch trends.phase {
        case .idle, .loading:
            FALoadingState()
        case .failed(let message):
            FAErrorState(title: String(localized: "trends.error.load", defaultValue: "Couldn't load your trends"), message: message) {
                Task { await trends.load() }
            }
        case .empty:
            FAErrorState(title: String(localized: "trends.error.load", defaultValue: "Couldn't load your trends"),
                         message: String(localized: "home.notRegistered.message", defaultValue: "This account isn't linked to a FunctionAlps client profile yet. Finish onboarding on the FunctionAlps web app, then come back."),
                         retryTitle: nil, retry: nil)
        case .loaded:
            if let page = trends.page { loaded(page, trends: trends) }
        }
    }

    private func loaded(_ page: TrendsEngine.Page, trends: TrendsService) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "trends.title", defaultValue: "Trends"))
                            .font(FATypography.display(34, relativeTo: .largeTitle))
                            .foregroundStyle(FAColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(String(localized: "trends.subtitle", defaultValue: "Your data, as you logged it."))
                            .font(FATypography.sans(14, relativeTo: .subheadline))
                            .foregroundStyle(FAColor.inkSecondary)
                    }
                    .padding(.horizontal, 2)
                    TrendWindowPicker(selection: trends.window) { trends.setWindow($0) }
                    if page.hasAnyLog {
                        sections(page)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await trends.load(refresh: true) }
            #if DEBUG
            .task { await Showcase.scroll(proxy, to: "trends.plan", on: .trendsMiddle) }
            .task { await Showcase.scroll(proxy, to: "trends.food", on: .trendsBottom) }
            .task { await Showcase.scroll(proxy, to: "trends.signals", on: .trendsEnergyOpen) }
            #endif
        }
    }

    @ViewBuilder
    private func sections(_ page: TrendsEngine.Page) -> some View {
        TrendsScoreCard(page: page)
        TrendsPlanCard(page: page).id("trends.plan")
        if !page.devices.isEmpty {
            TrendsDevicesCard(devices: page.devices) { router.push(.trendDevice($0.key)) }
        }
        HStack(alignment: .firstTextBaseline) {
            TrendLabel(text: String(localized: "trends.signals.title", defaultValue: "Your signals"))
            Spacer()
            Text(String(localized: "trends.signals.hint", defaultValue: "Tap to expand · tap again for details"))
                .font(FATypography.sans(10.5, relativeTo: .caption2))
                .foregroundStyle(FAColor.inkSecondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .id("trends.signals")
        ForEach(TrendSignal.allCases) { signal in
            TrendSignalRow(page: page, signal: signal, expanded: expanded == signal) { tap(signal) }
        }
        TrendsFoodCard(page: page).id("trends.food")
        TrendsPatternsRow(count: page.patterns.count) { router.push(.trendPatterns) }
        NavigationLink(value: Route.scores) {
            HStack(spacing: 4) {
                Text(String(localized: "trends.allScores", defaultValue: "All your scores"))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption))
                    .foregroundStyle(FAColor.forestSoft)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// First tap opens the row in place; a tap on the open row goes to its page.
    private func tap(_ signal: TrendSignal) {
        if expanded == signal {
            router.push(.trendSignal(signal))
        } else {
            withAnimation(.easeOut(duration: 0.22)) { expanded = signal }
        }
    }

    private var emptyState: some View {
        FACard {
            VStack(spacing: 12) {
                FAEmptyState(
                    title: String(localized: "trends.empty.title", defaultValue: "Your trends start with a check-in"),
                    message: String(localized: "trends.empty.message", defaultValue: "Log how you feel and what you eat, and your days appear here."),
                    systemImage: "chart.line.uptrend.xyaxis")
                NavigationLink(value: Route.checkin(.evening)) {
                    Text(String(localized: "trends.empty.cta", defaultValue: "Start today's check-in"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(FAColor.forest)
                }
                .buttonStyle(.plain)
            }
        }
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
