import SwiftUI

/// "Your Apple Health" — today's readings next to the member's own last seven days, straight from HealthKit.
/// Every line describes a reading; nothing here judges the body. Reached from the Home card.
struct HealthView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let wearables = dependencies.wearables
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Button { dismiss() } label: {
                    Text("‹ " + String(localized: "scores.back", defaultValue: "Back"))
                        .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "health.page.title", defaultValue: "Your Apple Health"))
                        .font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink)
                    Text(String(localized: "health.page.intro", defaultValue: "Today next to your own last seven days. Readings come from the Health app on this iPhone — your Apple Watch and any app that writes to Health."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)

                if !wearables.isConnected {
                    notConnected
                } else if let snapshot = wearables.snapshot {
                    if !snapshot.hasAnyReading {
                        FACard { Text(String(localized: "home.health.empty", defaultValue: "No readings yet · open the Health app on your iPhone to check what it holds.")).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary) }
                    }
                    section(String(localized: "health.section.activity", defaultValue: "Activity"), metrics: HealthSnapshot.Metric.activity, snapshot: snapshot)
                    if let night = snapshot.night { SleepNightCard(night: night, stat: snapshot.stat(.sleep)) }
                    else if let stat = snapshot.stat(.sleep) { section(String(localized: "health.section.sleep", defaultValue: "Last night"), metrics: [.sleep], snapshot: snapshot, stats: [stat]) }
                    section(String(localized: "health.section.heart", defaultValue: "Heart & breathing"), metrics: HealthSnapshot.Metric.heart, snapshot: snapshot)
                    section(String(localized: "health.section.body", defaultValue: "Body"), metrics: HealthSnapshot.Metric.body, snapshot: snapshot)
                    if !snapshot.workoutsToday.isEmpty { workouts(snapshot.workoutsToday) }
                    footer(snapshot)
                } else {
                    FACard { HStack(spacing: 10) { ProgressView(); Text(String(localized: "home.health.reading", defaultValue: "Reading Health…")).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary) } }
                }
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await wearables.refreshSnapshot() }
        .refreshable { await wearables.sync(); await wearables.refreshSnapshot() }
    }

    private var notConnected: some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "health.notConnected.title", defaultValue: "Apple Health isn't connected")).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                Text(String(localized: "health.notConnected.body", defaultValue: "Connect it in Devices to see your steps, sleep and heart readings here, next to what you log."))
                    .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                FAButton(title: String(localized: "health.manage", defaultValue: "Open Devices"), style: .secondary) { router.push(.wearables) }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, metrics: [HealthSnapshot.Metric], snapshot: HealthSnapshot, stats: [HealthSnapshot.Stat]? = nil) -> some View {
        let rows = stats ?? metrics.compactMap(snapshot.stat)
        if !rows.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    ForEach(rows) { stat in HealthStatRow(stat: stat) }
                }
            }
        }
    }

    private func workouts(_ list: [HealthSnapshot.Workout]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "health.section.workouts", defaultValue: "Workouts today")).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                ForEach(list) { w in
                    HStack {
                        Image(systemName: "figure.run").foregroundStyle(FAColor.forestSoft).frame(width: 18)
                        Text(HealthWorkoutLabel.label(w.name)).font(FATypography.sans(13, .medium, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                        Spacer()
                        Text(Self.workoutDetail(w))
                            .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
        }
    }

    /// "42 min · 310 kcal" — built outside the view tree so the type-checker has one string to look at.
    private static func workoutDetail(_ w: HealthSnapshot.Workout) -> String {
        var text = HealthFormat.integer(w.minutes, locale: .current) + " min"
        if let kcal = w.kcal { text += " · " + HealthFormat.integer(kcal, locale: .current) + " kcal" }
        return text
    }

    private func footer(_ snapshot: HealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "health.footer", defaultValue: "FunctionAlps shows these readings next to what you log; it never diagnoses. Nothing is written back to Health."))
                .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                let readAt = HealthFormat.clock(snapshot.capturedAt)
                Text(String(localized: "home.health.synced", defaultValue: "Read \(readAt)")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkMuted)
                Spacer()
                Button { router.push(.wearables) } label: {
                    Text(String(localized: "health.manage.short", defaultValue: "Manage in Devices")).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// One reading: symbol, name, today's value, the delta against the member's week, the eight-day bars, one line about it.
struct HealthStatRow: View {
    let stat: HealthSnapshot.Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: stat.metric.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft).frame(width: 18)
                Text(stat.metric.label).font(FATypography.sans(13, .medium, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                Spacer()
                if let today = stat.today {
                    Text(HealthFormat.value(today, metric: stat.metric)).font(FATypography.display(15, relativeTo: .headline)).foregroundStyle(FAColor.ink).monospacedDigit()
                } else {
                    Text(String(localized: "health.today.none", defaultValue: "No reading today")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkMuted)
                }
            }
            HStack(alignment: .center, spacing: 10) {
                HealthMiniBars(series: stat.series).frame(height: 22)
                Spacer(minLength: 0)
                if let mean = stat.weekMean {
                    let meanText = HealthFormat.value(mean, metric: stat.metric)
                    Text(String(localized: "health.week.mean", defaultValue: "7-day average \(meanText)"))
                        .font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                }
                if let delta = stat.deltaRatio { HealthDeltaChip(ratio: delta) }
            }
            Text(stat.metric.about).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "+12 %" against the member's own week — a comparison of two readings, nothing more.
struct HealthDeltaChip: View {
    let ratio: Double
    var body: some View {
        Text(HealthFormat.delta(ratio))
            .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.ink)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(FAColor.forestSoft.opacity(0.14), in: Capsule())
    }
}

/// Eight thin bars, oldest → today; today in the accent, days without a reading as a hairline.
struct HealthMiniBars: View {
    let series: [Double?]
    var body: some View {
        let peak = series.compactMap { $0 }.max() ?? 1
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(series.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(v == nil ? FAColor.inkMuted.opacity(0.35) : (i == series.count - 1 ? FAColor.forestSoft : FAColor.forestSoft.opacity(0.4)))
                    .frame(width: 6, height: v.map { max(3, 22 * CGFloat($0 / max(peak, 0.0001))) } ?? 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Last night as Apple assembled it: time asleep, in bed, the stage bar (when a Watch was worn), latency, wake-ups.
struct SleepNightCard: View {
    let night: SleepNight
    let stat: HealthSnapshot.Stat?

    private var stages: [(label: String, seconds: Double, color: Color)] {
        [
            (String(localized: "health.stage.deep", defaultValue: "Deep"), night.deepSeconds, FAColor.forestDark),
            (String(localized: "health.stage.core", defaultValue: "Core"), night.lightSeconds, FAColor.forestSoft),
            (String(localized: "health.stage.rem", defaultValue: "REM"), night.remSeconds, FAColor.goldSoft),
            (String(localized: "health.stage.awake", defaultValue: "Awake"), night.awakeSeconds, FAColor.inkMuted.opacity(0.6)),
        ].filter { $0.seconds > 0 }
    }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "health.section.sleep", defaultValue: "Last night")).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    Spacer()
                    Text(window).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(HealthFormat.hours(night.asleepSeconds / 3600)).font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    Text(String(localized: "health.sleep.asleep", defaultValue: "asleep")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    if let delta = stat?.deltaRatio { HealthDeltaChip(ratio: delta) }
                    Spacer()
                }
                if !stages.isEmpty {
                    GeometryReader { geo in
                        let total = max(stages.reduce(0) { $0 + $1.seconds }, 1)
                        HStack(spacing: 2) {
                            ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(s.color).frame(width: max(3, geo.size.width * s.seconds / total))
                            }
                        }
                    }
                    .frame(height: 10)
                    HStack(spacing: 10) {
                        ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                            HStack(spacing: 4) {
                                Circle().fill(s.color).frame(width: 6, height: 6)
                                Text(s.label + " " + HealthFormat.hours(s.seconds / 3600)).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    detail(HealthFormat.hours(night.inBedSeconds / 3600), String(localized: "health.sleep.inBed", defaultValue: "in bed"))
                    if let eff = night.efficiencyPct { detail("\(eff) %", String(localized: "health.sleep.efficiency", defaultValue: "efficiency")) }
                    detail(latencyText, String(localized: "health.sleep.latency", defaultValue: "to fall asleep"))
                    detail("\(night.interruptions)", String(localized: "health.sleep.interruptions", defaultValue: "wake-ups"))
                }
                if let stat {
                    HStack(spacing: 10) {
                        HealthMiniBars(series: stat.series).frame(height: 22)
                        if let mean = stat.weekMean {
                            let meanText = HealthFormat.value(mean, metric: .sleep)
                            Text(String(localized: "health.week.mean", defaultValue: "7-day average \(meanText)")).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                }
                Text(HealthSnapshot.Metric.sleep.about).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var window: String { HealthFormat.clock(night.start) + " → " + HealthFormat.clock(night.end) }
    private var latencyText: String { HealthFormat.integer(night.latencySeconds / 60, locale: .current) + " min" }

    private func detail(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.ink).monospacedDigit()
            Text(label).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
        }
    }
}

/// The reader's workout names → words (the catalogue keeps the raw name).
enum HealthWorkoutLabel {
    static func label(_ name: String) -> String {
        switch name {
        case "running": String(localized: "workout.running", defaultValue: "Running")
        case "walking": String(localized: "workout.walking", defaultValue: "Walking")
        case "cycling": String(localized: "workout.cycling", defaultValue: "Cycling")
        case "hiking": String(localized: "workout.hiking", defaultValue: "Hiking")
        case "swimming": String(localized: "workout.swimming", defaultValue: "Swimming")
        case "yoga": String(localized: "workout.yoga", defaultValue: "Yoga")
        case "strength": String(localized: "workout.strength", defaultValue: "Strength")
        case "hiit": String(localized: "workout.hiit", defaultValue: "HIIT")
        case "rowing": String(localized: "workout.rowing", defaultValue: "Rowing")
        case "elliptical": String(localized: "workout.elliptical", defaultValue: "Elliptical")
        case "pilates": String(localized: "workout.pilates", defaultValue: "Pilates")
        case "snow_sports": String(localized: "workout.snow", defaultValue: "Snow sports")
        default: String(localized: "workout.other", defaultValue: "Workout")
        }
    }
}
