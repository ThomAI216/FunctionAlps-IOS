import SwiftUI

/// One macro, from the bars on the Food tab and on Macros · Today: today's amount against the
/// target, the 7-day series from the meal log, and what the macro is and why it matters (the Expo
/// "Understanding the 3 macros" copy, plus the energy entry). There is no such page in the Expo app;
/// its explainers only exist as expandable cards on the targets page.
struct MacroDetailView: View {
    let macroKey: String
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model = NutritionScreenModel()

    private var entry: MacroEducation.Entry? { MacroEducation.entry(for: macroKey) }
    private var fill: Color { Color(hex: FoodPalette.pastel[macroKey] ?? 0x9FC8A6) }
    private var label: Color { Color(hex: FoodPalette.label[macroKey] ?? 0x5E9A6E) }
    private var unit: String { macroKey == "kcal" ? " kcal" : " g" }

    var body: some View {
        VStack(spacing: 0) {
            NutritionHeader(title: entry?.title ?? macroKey.capitalized, trailingSymbol: "slider.horizontal.3") { router.push(.nutritionTargets) }
            if let entry {
                ScrollView(showsIndicators: false) {
                    if !model.loaded {
                        FALoadingState().padding(.top, 60)
                    } else {
                        let series = dailySeries()
                        let today = series.last?.value ?? 0
                        let target = targetValue()
                        VStack(alignment: .leading, spacing: 12) {
                            heroCard(entry: entry, today: today, target: target, values: series.map(\.value))
                            trendCard(series: series)
                            educationCard(entry: entry)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, FASpacing.navBarClearance)
                    }
                }
            } else {
                Spacer()
                Text(String(localized: "macro.detail.missing", defaultValue: "Macro not found")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                Spacer()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(dependencies) }
    }

    // MARK: Data

    private func value(of meal: MealLog) -> Double {
        switch macroKey {
        case "kcal": meal.totalCalories ?? 0
        case "protein": meal.totalProteinG ?? 0
        case "carbs": meal.totalCarbsG ?? 0
        case "fat": meal.totalFatG ?? 0
        default: 0
        }
    }

    private func targetValue() -> Int? {
        guard let p = model.profile else { return nil }
        switch macroKey {
        case "kcal": return p.targetCalories
        case "protein": return p.targetProteinG
        case "carbs": return p.targetCarbsG
        case "fat": return p.targetFatG
        default: return nil
        }
    }

    /// One total per day for the last 7 days, oldest first.
    private func dailySeries() -> [(day: Date, value: Double)] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { return nil }
            let total = model.meals.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }.reduce(0.0) { $0 + value(of: $1) }
            return (day: calendar.startOfDay(for: day), value: total)
        }
    }

    // MARK: Cards

    private func heroCard(entry: MacroEducation.Entry, today: Double, target: Int?, values: [Double]) -> some View {
        let pct = target.map { $0 > 0 ? Int((today / Double($0) * 100).rounded()) : 0 }
        let logged = values.filter { $0 > 0 }
        let weekAvg = logged.isEmpty ? 0 : logged.reduce(0, +) / Double(logged.count)
        return FACard {
            ZStack {
                Text(entry.emoji).font(.system(size: 150)).opacity(0.1).frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 20) {
                        if let pct {
                            CoverageRing(pct: pct, size: 100, strokeWidth: 8, color: label, subLabel: String(localized: "micros.ofTarget", defaultValue: "of target"))
                        } else {
                            ZStack {
                                Circle().stroke(ProfilePalette.hairline, lineWidth: 8)
                                Text("·").font(FATypography.sans(22, .bold, relativeTo: .body)).foregroundStyle(ProfilePalette.muted)
                            }
                            .frame(width: 100, height: 100)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            MicroLabel(text: String(localized: "micros.today", defaultValue: "Today"))
                            Text("\(Int(today.rounded()))\(unit)").font(FATypography.sans(26, .bold, relativeTo: .title)).foregroundStyle(FAColor.ink)
                            Text(target.map { "\(String(localized: "micros.target", defaultValue: "target")): \($0)\(unit)" } ?? String(localized: "macro.detail.noTarget", defaultValue: "No target yet · set up your profile"))
                                .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                            Text(String(localized: "macro.detail.weekAvg", defaultValue: "7-day average \(Int(weekAvg.rounded()))\(unit)"))
                                .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(label).padding(.top, 8)
                        }
                    }
                    Text(entry.tagline).font(FATypography.display(16, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .padding(.top, 14).overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }.padding(.top, 16)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
    }

    private func trendCard(series: [(day: Date, value: Double)]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: String(localized: "micros.weekTrend", defaultValue: "7-day trend")).padding(.bottom, 14)
                HStack(alignment: .bottom, spacing: 6) {
                    let maxV = max(series.map(\.value).max() ?? 1, 1)
                    ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                        VStack(spacing: 4) {
                            Text(NutrientFormat.amount(point.value)).font(FATypography.sans(9.5, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.ink).lineLimit(1).minimumScaleFactor(0.7)
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill)
                                .frame(height: max(4, 60 * point.value / maxV))
                            Text(point.day.formatted(.dateTime.weekday(.abbreviated))).font(FATypography.sans(9, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func educationCard(entry: MacroEducation.Entry) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: String(localized: "macro.detail.why", defaultValue: "What it is and why it matters"), color: label).padding(.bottom, 8)
                Text(entry.why).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                MicroLabel(text: String(localized: "targets.edu.sources", defaultValue: "Best sources")).padding(.top, 16).padding(.bottom, 8)
                FlowLayout(spacing: 8) {
                    ForEach(entry.bestSources, id: \.self) { s in
                        Text(s).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(fill.opacity(0.22), in: Capsule()).overlay { Capsule().strokeBorder(fill.opacity(0.5), lineWidth: 1) }
                    }
                }
                MicroLabel(text: String(localized: "targets.edu.timing", defaultValue: "Timing")).padding(.top, 16).padding(.bottom, 4)
                Text(entry.timing).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                MicroLabel(text: String(localized: "targets.edu.myths", defaultValue: "Common myths")).padding(.top, 16).padding(.bottom, 4)
                ForEach(entry.myths, id: \.self) { m in
                    Text(m).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.bottom, 4)
                }
                Button { router.push(.nutritionTargets) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .bold))
                        Text(String(localized: "macro.detail.adjust", defaultValue: "Adjust my targets")).font(FATypography.sans(12.5, .bold, relativeTo: .caption))
                    }
                    .foregroundStyle(FAColor.charcoal).padding(.horizontal, 14).padding(.vertical, 9).background(FAColor.forestSoft, in: Capsule())
                }
                .buttonStyle(.plain).padding(.top, 14)
            }
        }
    }
}
