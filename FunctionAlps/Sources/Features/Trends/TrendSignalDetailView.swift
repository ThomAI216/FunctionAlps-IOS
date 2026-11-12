import SwiftUI

/// One signal's page — the second tap on its row. The same window control and sentence as the page, the curve
/// with every day labelled, then the days one by one: each day's value with that day's check-in words. Sleep
/// adds the nights (hours, the clock, the source); Digestion adds stool, the symptoms ticked and every meal with
/// the reaction the member noted.
struct TrendSignalDetailView: View {
    let signal: TrendSignal

    @Environment(AppDependencies.self) private var dependencies
    @State private var showEarlier = false

    private static let firstDays = 7

    var body: some View {
        let trends = dependencies.trends
        ZStack {
            if let page = trends.page {
                content(page, trends: trends)
            } else if case .failed(let message) = trends.phase {
                FAErrorState(title: String(localized: "trends.error.load", defaultValue: "Couldn't load your trends"), message: message) {
                    Task { await trends.load() }
                }
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await trends.loadIfNeeded() }
        .task { await dependencies.signals.loadIfNeeded() }
    }

    private var tint: Color { Color(hex: signal.tintHex) }

    /// "Learn about <signal>" at the top of the page — only when the practice's explanation is loaded.
    @ViewBuilder
    private var aboutLink: some View {
        if let key = SignalAboutKey(rawValue: signal.rawValue), dependencies.signals.content(for: key.rawValue) != nil {
            NavigationLink(value: Route.signalAbout(key.rawValue)) { SignalAboutLinkLabel(key: key) }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
        }
    }

    private func content(_ page: TrendsEngine.Page, trends: TrendsService) -> some View {
        let facts = page.facts(signal)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                TrendDetailHeader(title: signal.title) { subtitle(facts) }
                aboutLink
                TrendWindowPicker(selection: trends.window) { trends.setWindow($0) }
                TrendSentenceBox(text: page.sentence(signal))
                chartCard(page, facts: facts)
                switch signal {
                case .sleep:
                    if page.sleep.hasNights { sleepTable(page) }
                    sleepRefreshed(page)
                case .digestion:
                    digestionCard(page)
                default:
                    dayList(page)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .refreshable { await trends.load(refresh: true) }
    }

    @ViewBuilder
    private func subtitle(_ facts: TrendRowFacts) -> some View {
        switch signal {
        case .sleep:
            Text(facts.badge ?? String(localized: "trends.detail.fromCheckin", defaultValue: "From your daily check-in"))
        case .stress:
            Text(String(localized: "trends.detail.stress", defaultValue: "Stress level, 0–10 · from your daily check-in"))
        case .digestion:
            Text(String(localized: "trends.detail.digestion", defaultValue: "Comfort, stool and meal reactions · as you logged them"))
        default:
            Text(String(localized: "trends.detail.fromCheckin", defaultValue: "From your daily check-in"))
        }
    }

    // MARK: The curve

    private func chartCard(_ page: TrendsEngine.Page, facts: TrendRowFacts) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                TrendLabel(text: facts.isNight
                           ? String(localized: "trends.detail.hours", defaultValue: "Hours asleep, \(page.window.days) days")
                           : String(localized: "trends.detail.last", defaultValue: "Last \(page.window.days) days"))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(facts.big).font(FATypography.display(32, relativeTo: .title)).foregroundStyle(FAColor.ink)
                    Text(facts.unit)
                        .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                }
                if let sub = facts.sub {
                    Text(sub).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
                if facts.isNight {
                    TrendBars(values: facts.plotted, tint: tint, top: barTop(facts.plotted), gridlines: [6, 7, 8])
                        .frame(height: 110)
                        .padding(.top, 4)
                } else {
                    TrendCurve(values: facts.plotted, tint: tint, showAllDots: true, columns: true, lineWidth: 2)
                        .frame(height: 110)
                        .padding(.top, 4)
                }
                TrendValueStrip(days: page.days, labels: facts.labels, tint: tint)
                Text(facts.averageLine)
                    .font(FATypography.sans(12, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
                    .padding(.top, 2)
            }
        }
    }

    /// The bar chart's top: a round hour above the longest night, never under 9.
    private func barTop(_ hours: [Double?]) -> Double {
        max(9, (hours.compactMap { $0 }.max() ?? 0).rounded(.up) + 0.5)
    }

    // MARK: Day by day

    private func dayList(_ page: TrendsEngine.Page) -> some View {
        let rows = page.series(signal).map { TrendsEngine.dayRows($0, index: page.index) } ?? []
        let shown = showEarlier ? rows : Array(rows.prefix(Self.firstDays))
        return FACard {
            VStack(alignment: .leading, spacing: 0) {
                TrendLabel(text: String(localized: "trends.detail.byDay", defaultValue: "Day by day")).padding(.bottom, 10)
                if rows.isEmpty {
                    Text(String(localized: "trends.noData", defaultValue: "Nothing logged in this period yet"))
                        .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Divider().overlay(Color.white.opacity(0.7)).padding(.vertical, 10) }
                    dayRow(row)
                }
                earlierButton(hidden: rows.count - shown.count)
            }
        }
    }

    private func dayRow(_ row: TrendsEngine.DayRow) -> some View {
        let level = TrendsEngine.level(signal, marker: row.marker)
        return HStack(alignment: .top, spacing: 10) {
            Text(TrendsFormat.dayLabel(row.day))
                .font(FATypography.sans(12.5, .bold, relativeTo: .caption))
                .foregroundStyle(FAColor.ink)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 3)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(TrendsFormat.whole(level)).font(FATypography.display(22, relativeTo: .title3)).foregroundStyle(tint)
                Text("/10").font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
            }
            .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if let word = row.word {
                    Text(word).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                }
                if !row.pills.isEmpty {
                    TrendFlow(spacing: 5) {
                        ForEach(Array(row.pills.enumerated()), id: \.offset) { _, pill in TrendWordChip(text: pill) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func earlierButton(hidden: Int) -> some View {
        if hidden > 0 || showEarlier {
            Button { showEarlier.toggle() } label: {
                Text(showEarlier
                     ? String(localized: "trends.detail.fewer", defaultValue: "Show fewer days")
                     : String(localized: "trends.detail.earlier", defaultValue: "Show earlier days"))
                    .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(FAColor.forest)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    // MARK: Sleep

    private func sleepTable(_ page: TrendsEngine.Page) -> some View {
        let nights = Array(page.sleep.recent.prefix(Self.firstDays))
        return FACard {
            VStack(alignment: .leading, spacing: 10) {
                TrendLabel(text: String(localized: "trends.sleep.table", defaultValue: "Last 7 nights"))
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 0) {
                    GridRow {
                        header(String(localized: "trends.sleep.col.day", defaultValue: "Day"))
                        header(String(localized: "trends.sleep.col.inBed", defaultValue: "In bed"))
                        header(String(localized: "trends.sleep.col.asleep", defaultValue: "Asleep"))
                        header(String(localized: "trends.sleep.col.bedWake", defaultValue: "Bed → Wake"))
                        header(String(localized: "trends.sleep.col.woke", defaultValue: "Woke"))
                        header(String(localized: "trends.sleep.col.source", defaultValue: "Source"))
                    }
                    ForEach(nights) { night in
                        Divider().overlay(Color.white.opacity(0.7))
                        GridRow {
                            cell(TrendsFormat.dayLabel(night.day), bold: true)
                            cell(night.inBedMin.map { TrendsFormat.hours(minutes: $0) } ?? "–")
                            cell(night.asleepMin.map { TrendsFormat.hours(minutes: $0) } ?? "–")
                            cell(TrendsFormat.bedToWake(bed: night.bedTime, wake: night.wakeTime))
                            cell(TrendsFormat.wakeLabel(night.wakeBand))
                            cell(night.source)
                        }
                    }
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(FATypography.sans(9, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).lineLimit(1)
            .padding(.bottom, 6)
    }

    private func cell(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(FATypography.sans(10.5, bold ? .bold : .regular, relativeTo: .caption2))
            .foregroundStyle(FAColor.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sleepRefreshed(_ page: TrendsEngine.Page) -> some View {
        if let refreshed = page.sleep.refreshed {
            let value = TrendsFormat.whole(Double(refreshed.value) / 10)
            FACard {
                VStack(alignment: .leading, spacing: 6) {
                    TrendLabel(text: String(localized: "trends.sleep.checkin", defaultValue: "From your check-in"))
                    Text(refreshed.day == page.today
                         ? String(localized: "trends.sleep.refreshedToday", defaultValue: "Refreshed \(value)/10 today")
                         : String(localized: "trends.sleep.refreshedOn", defaultValue: "Refreshed \(value)/10 on \(TrendsFormat.dayLabel(refreshed.day))"))
                        .font(FATypography.sans(14, relativeTo: .subheadline))
                        .foregroundStyle(FAColor.ink)
                }
            }
        }
    }

    // MARK: Digestion

    private func digestionCard(_ page: TrendsEngine.Page) -> some View {
        let shown = showEarlier ? page.digestion : Array(page.digestion.prefix(Self.firstDays))
        return FACard {
            VStack(alignment: .leading, spacing: 0) {
                TrendLabel(text: String(localized: "trends.detail.byDay", defaultValue: "Day by day")).padding(.bottom, 6)
                Text(String(localized: "trends.digestion.note", defaultValue: "Comfort, stool, meals and the reactions you noted, as logged."))
                    .font(FATypography.sans(11.5, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkMuted)
                    .padding(.bottom, 10)
                if page.digestion.isEmpty {
                    Text(String(localized: "trends.noData", defaultValue: "Nothing logged in this period yet"))
                        .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, day in
                    if i > 0 { Divider().overlay(Color.white.opacity(0.7)).padding(.vertical, 12) }
                    digestionDay(day)
                }
                earlierButton(hidden: page.digestion.count - shown.count)
            }
        }
    }

    private func digestionDay(_ day: TrendsEngine.DigestionDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(TrendsFormat.dayLabel(day.day)).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                Spacer()
                if let headline = day.headline {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(TrendsFormat.whole(headline / 10)).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(tint)
                        Text(day.headlineIsComfort
                             ? String(localized: "trends.digestion.comfort", defaultValue: "/10 comfort")
                             : "/10")
                            .font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
                    }
                }
            }
            TrendFlow(spacing: 6) {
                if let stool = stoolText(day) { TrendWordChip(text: stool) }
                if day.symptoms.isEmpty {
                    Text(String(localized: "trends.digestion.noSymptoms", defaultValue: "no symptoms ticked"))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkMuted)
                } else {
                    TrendWordChip(text: ticked(day), tone: .strong)
                }
            }
            ForEach(day.meals) { meal in TrendMealRow(meal: meal, showsPhoto: false) }
        }
    }

    /// "Ticked: gas, bloating".
    private func ticked(_ day: TrendsEngine.DigestionDay) -> String {
        let list = day.symptoms.joined(separator: ", ")
        return String(localized: "trends.digestion.ticked", defaultValue: "Ticked: \(list)")
    }

    /// "Stool 1× · Type 4" — how often, and the Bristol type the member picked.
    private func stoolText(_ day: TrendsEngine.DigestionDay) -> String? {
        var parts: [String] = []
        if let f = day.stoolFrequency { parts.append("\(f)×") }
        if let b = day.bristol {
            parts.append(String(localized: "trends.digestion.type", defaultValue: "Type \(b)"))
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: " · ")
        return String(localized: "trends.digestion.stool", defaultValue: "Stool \(joined)")
    }
}
