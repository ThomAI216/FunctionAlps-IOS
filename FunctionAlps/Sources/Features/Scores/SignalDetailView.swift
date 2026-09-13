import SwiftUI

/// One body signal or one gut signal, explained — the Expo `(screens)/score/[key].tsx`: the hero (score,
/// status, 14-day bars), what it is, what influences it, how it connects (body) or what raises / lowers it
/// (gut), the band guide, and the way back to the hub.
struct SignalDetailView: View {
    enum Kind: Hashable { case body(BodySignal), gut(GutSignal) }
    let kind: Kind

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var signal: ScoresOverview.Signal?

    private var title: String { switch kind { case .body(let s): s.title; case .gut(let s): s.title } }
    private var subtitle: String { switch kind { case .body(let s): s.subtitle; case .gut(let s): s.subtitle } }
    private var tint: Color { switch kind { case .body(let s): s.tint; case .gut(let s): s.tint } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    Text("‹ " + String(localized: "scores.title", defaultValue: "Your Scores"))
                        .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                Text(title).font(FATypography.display(24, relativeTo: .title)).foregroundStyle(FAColor.ink)
                Text(subtitle).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).padding(.top, 2).padding(.bottom, 14)

                hero

                switch kind {
                case .body(let s):
                    heading(String(localized: "scoreX.whatItIs", defaultValue: "What it is"))
                    Text(s.explanation).font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    heading(String(localized: "signal.influences", defaultValue: "What influences it"))
                    VStack(spacing: 8) {
                        ForEach(s.focusAreas) { f in
                            FACard {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.title).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                                    Text(f.body).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    heading(String(localized: "signal.connects", defaultValue: "How it connects"))
                    FACard {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(s.connections.enumerated()), id: \.offset) { i, c in
                                VStack(alignment: .leading, spacing: 2) {
                                    if i > 0 { Rectangle().fill(FAColor.separator).frame(height: 1).padding(.bottom, 7) }
                                    Text(c.title).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                                    Text(c.body).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .gut(let s):
                    heading(String(localized: "scoreX.whatItIs", defaultValue: "What it is"))
                    Text(s.whatItIs).font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    heading(String(localized: "signal.influences", defaultValue: "What influences it"))
                    HStack(alignment: .top, spacing: 9) {
                        column(String(localized: "signal.raises", defaultValue: "↑ Raises it"), s.raises, tint: Color(hex: 0x4A8A5C))
                        column(String(localized: "signal.lowers", defaultValue: "↓ Lowers it"), s.lowers, tint: Color(hex: 0xC2554C))
                    }
                }

                heading(String(localized: "signal.bands", defaultValue: "Reading the bands"))
                FACard {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(ScoreBands.all) { b in
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 3).fill(b.color).frame(width: 11, height: 11)
                                Text(b.label).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink).frame(width: 120, alignment: .leading)
                                Text(b.range).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { router.push(.scores) } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "scores.exploreAll", defaultValue: "Explore all scores")).font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var hero: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(signal?.score.map(String.init) ?? "·").font(FATypography.display(40, relativeTo: .largeTitle)).foregroundStyle(tint)
                    Text("/100").font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                    Spacer()
                    if let score = signal?.score {
                        let status = ScoreStatus.of(score)
                        Text(status.label).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(status.color)
                    }
                }
                Text(heroCaption).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
                ScoreBarTrend(values: signal?.series ?? Array(repeating: nil, count: 14), color: tint, height: 72).padding(.top, 14)
                Text(String(localized: "signal.last14", defaultValue: "Last 14 days · higher is better")).font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).padding(.top, 6)
            }
        }
    }

    private var heroCaption: String {
        switch kind {
        case .body(let s): s.insight
        case .gut: String(localized: "signal.fromGut", defaultValue: "From your gut check-in.")
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(FATypography.sans(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).padding(.top, 20).padding(.bottom, 9)
    }

    private func column(_ title: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(tint).padding(.bottom, 4)
            ForEach(items, id: \.self) { item in
                Text("• " + item).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let member = try? await dependencies.members.currentMember() else { return }
        let calendar = Calendar.current
        let now = Date()
        let since = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        let sinceDay = ISO8601.dayString(since, calendar: calendar)
        let today = ISO8601.dayString(now, calendar: calendar)
        let backend = dependencies.backend
        switch kind {
        case .body(let s):
            let checkins = (try? await backend.dailyCheckins(patientId: member.patientId, since: sinceDay)) ?? []
            signal = ScoresOverview.body(s, checkins: checkins, now: now, calendar: calendar)
        case .gut(let s):
            var days = (try? await backend.gutHistory(patientId: member.patientId, since: sinceDay, before: today)) ?? []
            if let t = try? await backend.gutToday(patientId: member.patientId, day: today) { days.append(t.day) }
            signal = ScoresOverview.gut(s, days: days, now: now, calendar: calendar)
        }
    }
}
