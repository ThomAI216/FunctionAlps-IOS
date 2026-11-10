import SwiftUI

/// One device on its own page: each reading it sent — sleep, resting heart rate, HRV, steps, whichever it has —
/// with the latest value, a curve over the window and the averages. "Readings as <source> sent them": the values
/// are the device's own, never re-scored.
struct WearableSourceDetailView: View {
    let deviceKey: String

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let trends = dependencies.trends
        ZStack {
            if let page = trends.page {
                if let device = page.devices.first(where: { $0.key == deviceKey }) {
                    content(page, device: device, trends: trends)
                } else {
                    FAEmptyState(
                        title: String(localized: "trends.device.gone.title", defaultValue: "This device isn't connected"),
                        message: String(localized: "trends.device.gone.message", defaultValue: "Connect it again from Devices in your settings."),
                        systemImage: "sensor.tag.radiowaves.forward")
                }
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
    }

    private func content(_ page: TrendsEngine.Page, device: TrendsEngine.Device, trends: TrendsService) -> some View {
        let metrics = page.deviceMetrics[device.key] ?? []
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                TrendDetailHeader(title: device.name) {
                    HStack(spacing: 6) {
                        Circle().fill(FAColor.forestSoft).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(statusLine(device))
                    }
                }
                TrendWindowPicker(selection: trends.window) { trends.setWindow($0) }
                if metrics.isEmpty {
                    FACard {
                        Text(String(localized: "trends.device.empty", defaultValue: "No readings from \(device.name) in this period yet."))
                            .font(FATypography.sans(13.5, relativeTo: .callout))
                            .foregroundStyle(FAColor.inkSecondary)
                    }
                }
                ForEach(metrics) { metric in metricCard(metric, days: page.window.days) }
                Text(String(localized: "trends.device.footer", defaultValue: "Readings as \(device.name) sent them."))
                    .font(FATypography.sans(12, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .refreshable { await trends.load(refresh: true) }
    }

    private func statusLine(_ device: TrendsEngine.Device) -> String {
        let sync = device.lastSync.map { HealthFormat.clock($0) }
        guard let sync else { return String(localized: "trends.device.connected", defaultValue: "Connected") }
        return String(localized: "trends.device.connectedSync", defaultValue: "Connected · last sync \(sync)")
    }

    private func metricCard(_ metric: TrendsEngine.DeviceMetric, days: Int) -> some View {
        let tint = metric.kind.tint
        return FACard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(metric.kind.title).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                }
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(metric.latest.map { metric.kind.text($0) } ?? "·")
                            .font(FATypography.display(32, relativeTo: .title)).foregroundStyle(FAColor.ink)
                        if let unit = metric.kind.unit {
                            Text(unit).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    TrendCurve(values: metric.values, tint: tint).frame(width: 120, height: 38)
                }
                Text(TrendsFormat.averageLine(average: metric.average.map { metric.kind.average($0) },
                                              previous: metric.previousAverage.map { metric.kind.average($0) }, days: days))
                    .font(FATypography.sans(12, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TrendsEngine.DeviceMetric.Kind {
    var title: String {
        switch self {
        case .sleep: String(localized: "trends.signal.sleep", defaultValue: "Sleep")
        case .restingHeartRate: String(localized: "health.restingHR", defaultValue: "Resting heart rate")
        case .hrv: String(localized: "health.hrv.short", defaultValue: "HRV")
        case .steps: String(localized: "health.steps", defaultValue: "Steps")
        }
    }

    var tint: Color {
        switch self {
        case .sleep: Color(hex: TrendSignal.sleep.tintHex)
        case .restingHeartRate: Color(hex: 0xE11D48)
        case .hrv: Color(hex: 0x4A8A5C)
        case .steps: Color(hex: 0x4F86C6)
        }
    }

    var unit: String? {
        switch self {
        case .sleep: String(localized: "trends.sleep.asleep", defaultValue: "asleep")
        case .restingHeartRate: "bpm"
        case .hrv: "ms"
        case .steps: nil
        }
    }

    /// The latest reading.
    func text(_ v: Double) -> String {
        switch self {
        case .sleep: TrendsFormat.hours(v)
        case .restingHeartRate, .hrv: TrendsFormat.whole(v)
        case .steps: HealthFormat.integer(v, locale: .current)
        }
    }

    /// An average, one decimal where the reading has them.
    func average(_ v: Double) -> String {
        switch self {
        case .sleep: TrendsFormat.hours(v)
        case .restingHeartRate, .hrv: TrendsFormat.oneDecimal(v)
        case .steps: HealthFormat.integer(v, locale: .current)
        }
    }
}
