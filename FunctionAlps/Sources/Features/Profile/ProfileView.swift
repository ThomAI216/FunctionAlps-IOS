import SwiftUI

/// The Expo `(tabs)/profile.tsx`, card for card: profile card → access window strip → Functional
/// trend → Your care plan → Your baseline → Your feedback → Learn.
struct ProfileView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: ProfileViewModel?

    var body: some View {
        ZStack {
            if let model { ProfileScreen(model: model) }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = ProfileViewModel(members: dependencies.members, auth: dependencies.auth, profile: dependencies.profile, backend: dependencies.backend)
                model = m
                await m.load()
            }
        }
    }
}

private struct ProfileScreen: View {
    @Bindable var model: ProfileViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "profile.error.title", defaultValue: "Couldn't load your profile"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            VStack(spacing: FASpacing.lg) {
                FAEmptyState(
                    title: String(localized: "home.notRegistered.title", defaultValue: "Almost there"),
                    message: String(localized: "home.notRegistered.message", defaultValue: "This account isn't linked to a FunctionAlps client profile yet. Finish onboarding on the FunctionAlps web app, then come back."),
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                FAButton(title: String(localized: "profile.signOut", defaultValue: "Sign out"), style: .destructive, isLoading: model.isSigningOut) {
                    Task { await model.signOut() }
                }
            }
            .padding(FASpacing.lg)
        case .loaded(let member):
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    profileCard(member).padding(.top, 6)
                    accessStrip
                    ProfileSectionLabel(title: String(localized: "profile.trend", defaultValue: "Functional trend"), action: String(localized: "profile.trend.open", defaultValue: "Open Health ›")) { router.tab = .trends }
                    trendCard
                    ProfileSectionLabel(title: String(localized: "profile.carePlan", defaultValue: "Your care plan"), action: String(localized: "profile.carePlan.open", defaultValue: "View full plan ›")) { router.profilePath.append(.carePlan) }
                    carePlanPreview(member)
                    ProfileSectionLabel(title: String(localized: "profile.details", defaultValue: "Your baseline"))
                    ProfileIconRowCard(
                        symbol: "safari",
                        title: String(localized: "profile.baseline.title", defaultValue: "Baseline & energy compass"),
                        subtitle: String(localized: "profile.baseline.sub", defaultValue: "Age, height, weight and activity. Updating them re-estimates your daily energy")
                    ) { router.profilePath.append(.baseline) }
                    ProfileSectionLabel(title: String(localized: "profile.feedback", defaultValue: "Your feedback"))
                    ProfileIconRowCard(
                        symbol: "bubble.left.and.text.bubble.right",
                        title: String(localized: "profile.feedback.title", defaultValue: "Tell us about the app"),
                        subtitle: String(localized: "profile.feedback.sub", defaultValue: "What is confusing, slow or missing. It helps us a lot, and it goes to the team, not your nutritionist"),
                        tintHex: 0xC48B35, borderHex: 0xC48B35
                    ) { router.profilePath.append(.feedback) }
                    ProfileSectionLabel(title: String(localized: "profile.learn", defaultValue: "Learn"))
                    ProfileIconRowCard(
                        symbol: "book",
                        title: String(localized: "profile.learn.title", defaultValue: "How this app works"),
                        subtitle: String(localized: "profile.learn.sub", defaultValue: "Every screen explained, in plain language"),
                        borderHex: 0x4A8A5C
                    ) { router.profilePath.append(.guide) }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: Profile card

    private func profileCard(_ member: Member) -> some View {
        Button { router.profilePath.append(.settings) } label: {
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 13) {
                        ZStack {
                            Circle().fill(Color(hex: 0x4A8A5C, opacity: 0.18))
                            Circle().strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.55), lineWidth: 1.5)
                            Text(String(member.firstName.prefix(1)).uppercased())
                                .font(FATypography.display(26, relativeTo: .title))
                                .foregroundStyle(FAColor.forestSoft)
                        }
                        .frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.firstName).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink).lineLimit(1)
                            // "client", never "patient" — D-18.
                            Text(String(localized: "profile.client", defaultValue: "FunctionAlps client")).font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 4) {
                        Text(String(localized: "profile.settingsRow", defaultValue: "Account & settings"))
                            .font(FATypography.sans(11.5, .semibold, relativeTo: .caption))
                            .foregroundStyle(ProfilePalette.muted)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.gold)
                    }
                    .padding(.top, 11)
                    .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
                    .padding(.top, 12)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                    .strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "profile.settingsRow", defaultValue: "Account & settings"))
    }

    // MARK: Access window strip (windowed tiers only; nothing for a client)

    @ViewBuilder
    private var accessStrip: some View {
        if let c = model.countdown {
            let tint: Color = c.urgent ? FAColor.gold : FAColor.forestSoft
            let strip = HStack(spacing: 11) {
                ZStack {
                    Circle().fill(c.urgent ? Color(hex: 0xC48B35, opacity: 0.18) : ProfilePalette.accentSoft)
                    Image(systemName: "hourglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.label.uppercased()).font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(tint)
                    Text(c.headline).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).padding(.top, 2)
                    Text(c.detail).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(3).padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if c.tier == .discovery {
                    Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                }
            }
            .padding(13)
            .background(c.urgent ? Color(hex: 0xC48B35, opacity: 0.10) : ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.urgent ? Color(hex: 0xC48B35, opacity: 0.45) : ProfilePalette.hairline, lineWidth: 1) }
            .padding(.top, 10)

            if c.tier == .discovery {
                Button { openURL(AccessCountdown.membersRequestURL) } label: { strip }.buttonStyle(.plain)
            } else {
                strip
            }
        }
    }

    // MARK: Functional trend (compact)

    private var trendCard: some View {
        Button { router.tab = .trends } label: {
            FACard {
                HStack(spacing: 12) {
                    TrendSparkline(series: model.scores?.crownSeries ?? [])
                        .frame(width: 92, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trendHeadline).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        HStack(spacing: 5) {
                            ForEach(pillarChips, id: \.0) { chip in
                                Text(chip.0)
                                    .font(FATypography.sans(10, .bold, relativeTo: .caption2))
                                    .foregroundStyle(chip.1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(ProfilePalette.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("›").font(.system(size: 18)).foregroundStyle(ProfilePalette.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var trendHeadline: String {
        guard let scores = model.scores, let score = scores.composite.score else {
            return String(localized: "profile.trend.none", defaultValue: "No trend yet · log a few days")
        }
        let n = Int(score.rounded())
        switch scores.trend {
        case .up: return String(localized: "profile.trend.up", defaultValue: "Trending up · \(n)")
        case .down: return String(localized: "profile.trend.down", defaultValue: "Trending down · \(n)")
        default: return String(localized: "profile.trend.flat", defaultValue: "Holding steady · \(n)")
        }
    }

    /// `Energy ↑ · Sleep → · Digestion ↑` from the three pillar breakdowns' 14-day series.
    private var pillarChips: [(String, Color)] {
        guard let s = model.scores else {
            return [(String(localized: "profile.chip.energy", defaultValue: "Energy") + " →", ProfilePalette.muted),
                    (String(localized: "profile.chip.sleep", defaultValue: "Sleep") + " →", ProfilePalette.muted),
                    (String(localized: "profile.chip.digestion", defaultValue: "Digestion") + " →", ProfilePalette.muted)]
        }
        func arrow(_ series: [Double?]) -> (String, Color) {
            let values = series.compactMap { $0 }
            guard values.count >= 4 else { return ("→", ProfilePalette.muted) }
            let half = values.count / 2
            let early = values.prefix(half).reduce(0, +) / Double(half)
            let late = values.suffix(values.count - half).reduce(0, +) / Double(values.count - half)
            if late - early >= 2 { return ("↑", FAColor.forestSoft) }
            if early - late >= 2 { return ("↓", FAColor.warning) }
            return ("→", ProfilePalette.muted)
        }
        let e = arrow(s.vitality.series14d), sl = arrow(s.metabolic.series14d), d = arrow(s.gut.series14d)
        return [(String(localized: "profile.chip.energy", defaultValue: "Energy") + " " + e.0, e.1),
                (String(localized: "profile.chip.sleep", defaultValue: "Sleep") + " " + sl.0, sl.1),
                (String(localized: "profile.chip.digestion", defaultValue: "Digestion") + " " + d.0, d.1)]
    }

    // MARK: Care plan preview

    @ViewBuilder
    private func carePlanPreview(_ member: Member) -> some View {
        if let plan = model.plan {
            Button { router.profilePath.append(.carePlan) } label: {
                FACard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(plan.title).font(FATypography.display(17, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                        Text(plan.practitioner + (plan.startDate.isEmpty ? "" : String(localized: "profile.carePlan.since", defaultValue: " · since \(plan.startDate)")))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).padding(.top, 3)

                        let complaints = (member.profile?.currentComplaints ?? []).map(ComplaintLabels.label)
                        if !complaints.isEmpty {
                            Text(String(localized: "profile.carePlan.addressing", defaultValue: "Addressing").uppercased())
                                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(ProfilePalette.muted)
                                .padding(.top, 15).padding(.bottom, 8)
                            FlowLayout(spacing: 6) {
                                ForEach(complaints, id: \.self) { c in
                                    Text(c)
                                        .font(FATypography.sans(11.5, .semibold, relativeTo: .caption))
                                        .foregroundStyle(FAColor.forestSoft)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Color(hex: 0x4A8A5C, opacity: 0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.3), lineWidth: 1) }
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "target").font(.system(size: 12, weight: .semibold)).foregroundStyle(ProfilePalette.gold)
                            Text(String(localized: "profile.carePlan.objectives", defaultValue: "Objectives").uppercased())
                                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(ProfilePalette.muted)
                        }
                        .padding(.top, 16).padding(.bottom, 9)
                        ForEach(plan.goals.prefix(3), id: \.self) { goal in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(ProfilePalette.gold).frame(width: 5, height: 5).padding(.top, 6)
                                Text(goal).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4)
                            }
                            .padding(.bottom, 7)
                        }

                        if let tip = plan.sections.first(where: { $0.category == "Lifestyle" })?.items.first?.text ?? plan.sections.first?.items.first?.text {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft).padding(.top, 1)
                                Text(tip).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ProfilePalette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            FACard {
                Text(model.planLoading
                     ? String(localized: "careplan.loading", defaultValue: "Loading your plan…")
                     : String(localized: "careplan.waiting", defaultValue: "Your personalised care plan appears here once your practitioner publishes it after your call."))
                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
            }
        }
    }
}

/// The 92×36 polyline with the end dot, from the 14-day composite series (dashes when empty).
private struct TrendSparkline: View {
    let series: [Int?]

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(FAColor.forestSoft, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Circle().fill(FAColor.forestSoft).frame(width: 6, height: 6).position(pts[pts.count - 1])
                } else {
                    Path { p in
                        p.move(to: CGPoint(x: 2, y: geo.size.height * 0.6))
                        p.addLine(to: CGPoint(x: geo.size.width - 2, y: geo.size.height * 0.6))
                    }
                    .stroke(ProfilePalette.hairline, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let values = series.compactMap { $0 }
        guard values.count >= 2 else { return [] }
        let lo = Double(values.min() ?? 0), hi = Double(values.max() ?? 100)
        let span = max(1, hi - lo)
        return values.enumerated().map { i, v in
            let x = 2 + CGFloat(i) / CGFloat(values.count - 1) * (size.width - 4)
            let y = 4 + (1 - CGFloat((Double(v) - lo) / span)) * (size.height - 8)
            return CGPoint(x: x, y: y)
        }
    }
}
