import SwiftUI

/// What a nutrient card shows: the full catalogue grouped (`MealNutrients`) and the two omega metrics.
struct NutrientBreakdown: Equatable {
    let sections: [MealNutrients.Section]
    let metrics: [MealNutrients.Metric]

    /// One meal, as stored (`micronutrient_totals`, `resolution_meta`).
    static func meal(_ meal: MealLog, catalogue: NutrientCatalogue, sex: MemberProfile.Sex?) -> NutrientBreakdown {
        let prefer = MealNutrientNames.preferTranslated
        let source = MealNutrients.source(meal: meal, knownKeys: MealNutrients.knownKeys(catalogue))
        return NutrientBreakdown(
            sections: MealNutrients.sections(source: source, catalogue: catalogue, sex: sex, preferTranslated: prefer,
                                             translated: MealNutrientNames.translated, fallback: MealNutrientNames.fallback),
            metrics: MealNutrients.metrics(meal: meal, catalogue: catalogue, sex: sex, preferTranslated: prefer,
                                           translated: MealNutrientNames.translated, fallback: MealNutrientNames.fallback)
        )
    }

    /// A day's analysed meals summed. No metrics: a ratio does not add up across meals.
    static func day(_ meals: [MealLog], catalogue: NutrientCatalogue, sex: MemberProfile.Sex?) -> NutrientBreakdown {
        let source = MealNutrients.source(day: meals, knownKeys: MealNutrients.knownKeys(catalogue))
        return NutrientBreakdown(
            sections: MealNutrients.sections(source: source, catalogue: catalogue, sex: sex, preferTranslated: MealNutrientNames.preferTranslated,
                                             translated: MealNutrientNames.translated, fallback: MealNutrientNames.fallback),
            metrics: []
        )
    }

    /// Whether anything at all was measured (a value, traces, or a metric that is not "no data").
    var hasData: Bool {
        sections.contains { $0.measured > 0 } || metrics.contains { $0.state != .noData }
    }
}

extension MealNutrients.Group {
    var title: String {
        switch self {
        case .vitamins: return String(localized: "nutrientGroup.vitamins.name", defaultValue: "Vitamins")
        case .minerals: return String(localized: "nutrientGroup.minerals.name", defaultValue: "Minerals")
        case .aminoAcids: return String(localized: "meal.nutrients.group.aminoAcids", defaultValue: "Amino acids")
        case .fattyAcids: return String(localized: "meal.nutrients.group.fattyAcids", defaultValue: "Fatty acids")
        case .carotenoids: return String(localized: "meal.nutrients.group.carotenoids", defaultValue: "Carotenoids")
        case .other: return String(localized: "meal.nutrients.group.other", defaultValue: "Other")
        }
    }
}

/// Amounts across six orders of magnitude (grams of fat, micrograms of selenium) in the member's locale.
enum NutrientAmount {
    static func number(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value < 0.001 { return "<" + 0.001.formatted(.number.precision(.fractionLength(3))) }
        if value >= 100 { return "\(Int(value.rounded()))" }
        let digits = value >= 1 ? 1 : value >= 0.1 ? 2 : 3
        return value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func text(_ value: Double, unit: String) -> String {
        unit.isEmpty || unit == "ratio" ? number(value) : "\(number(value)) \(unit)"
    }
}

/// The nutrient card: the metrics, then one collapsible line per group ("N of M measured"); a nutrient without a
/// value reads "No data", never 0. Status is always a word, never a colour alone.
struct NutrientBreakdownCard: View {
    let title: String
    let breakdown: NutrientBreakdown
    @State private var open: Set<MealNutrients.Group> = []

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased()).font(FATypography.sans(11, .bold, relativeTo: .caption)).tracking(1.4).foregroundStyle(FAColor.inkSecondary)
                if !breakdown.hasData {
                    Text(String(localized: "micros.noData", defaultValue: "No data"))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                } else {
                    if !breakdown.metrics.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(breakdown.metrics) { MetricLine(metric: $0) }
                        }
                        Divider().overlay(FAColor.separator)
                    }
                    ForEach(breakdown.sections) { section in
                        groupBlock(section)
                    }
                }
            }
        }
    }

    private func groupBlock(_ section: MealNutrients.Section) -> some View {
        let isOpen = open.contains(section.group)
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { open.remove(section.group) } else { open.insert(section.group) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(section.group.title).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    Spacer(minLength: 4)
                    Text(String(localized: "micros.measuredOf", defaultValue: "\(section.measured) of \(section.rows.count) measured"))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            if isOpen {
                ForEach(section.rows) { NutrientValueLine(row: $0) }
            }
        }
    }
}

private struct NutrientValueLine: View {
    let row: MealNutrients.Row

    private var valueText: String {
        switch row.state {
        case .noData: return String(localized: "micros.noData", defaultValue: "No data")
        case .traces: return String(localized: "meal.nutrients.traces", defaultValue: "Traces")
        case .value(let v): return NutrientAmount.text(v, unit: row.unit)
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if let pct = row.percentOfReference { parts.append(String(localized: "meal.nutrients.ofReference", defaultValue: "\(pct)% of daily reference")) }
        if row.partial { parts.append(String(localized: "meal.nutrients.partial", defaultValue: "Partial")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.name).font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(valueText).font(FATypography.sans(12.5, .semibold, relativeTo: .footnote))
                    .foregroundStyle(row.state == .noData ? FAColor.inkMuted : FAColor.ink)
                if let detail {
                    Text(detail).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MetricLine: View {
    let metric: MealNutrients.Metric

    private var valueText: String {
        switch metric.state {
        case .noData: return String(localized: "micros.noData", defaultValue: "No data")
        case .partial: return String(localized: "meal.nutrients.partial", defaultValue: "Partial")
        case .value(let v): return metric.unit == "ratio" ? "\(NutrientAmount.number(v)) : 1" : NutrientAmount.text(v, unit: metric.unit)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(metric.name).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(valueText).font(FATypography.sans(13, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(metric.state == .noData ? FAColor.inkMuted : FAColor.ink)
                if let pct = metric.percentOfReference {
                    Text(String(localized: "meal.nutrients.ofReference", defaultValue: "\(pct)% of daily reference"))
                        .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
