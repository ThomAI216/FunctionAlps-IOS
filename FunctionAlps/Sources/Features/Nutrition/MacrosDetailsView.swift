import SwiftUI

/// The Expo `(screens)/macros-details.tsx`: the intermediate "Macros · Today" page — the macro
/// summary, the micronutrients card, today's summary from the check-in, and today's meals with their
/// per-meal nutrient score. The sliders icon opens the targets page.
struct MacrosDetailsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model = NutritionScreenModel()
    @State private var openSummary = false

    var body: some View {
        VStack(spacing: 0) {
            NutritionHeader(title: String(localized: "macros.details.title", defaultValue: "Macros · Today"), trailingSymbol: "slider.horizontal.3") {
                router.push(.nutritionTargets)
            }
            ScrollView(showsIndicators: false) {
                if !model.loaded {
                    FALoadingState().padding(.top, 60)
                } else if let message = model.errorMessage, model.member == nil {
                    FAErrorState(title: String(localized: "food.error.title", defaultValue: "Couldn't load your meals"), message: message) { Task { await model.load(dependencies) } }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryCard
                        micronutrientsCard
                        todaySummaryCard
                        Text(String(localized: "macros.details.todayMeals", defaultValue: "Today's meals").uppercased())
                            .font(FATypography.sans(11, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted)
                            .padding(.top, 8).padding(.leading, 2)
                        mealsList
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, FASpacing.navBarClearance)
                }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(dependencies) }
    }

    // MARK: 1 · Summary

    private var consumed: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let meals = model.todayMeals
        return (meals.compactMap(\.totalCalories).reduce(0, +), meals.compactMap(\.totalProteinG).reduce(0, +),
                meals.compactMap(\.totalCarbsG).reduce(0, +), meals.compactMap(\.totalFatG).reduce(0, +))
    }

    private var macroRows: [MacroBarRow]? {
        guard let p = model.profile, p.hasBodyData, p.hasTargets else { return nil }
        let c = consumed
        func row(_ key: String, _ label: String, _ value: Double, _ target: Int?, _ unit: String) -> MacroBarRow {
            var pct = 0.0
            if let target, target > 0 { pct = value / Double(target) }
            return MacroBarRow(key: key, label: label, pct: pct, current: "\(Int(value.rounded()))", target: target.map { "\($0)\(unit)" } ?? "·")
        }
        return [
            row("kcal", String(localized: "macros.calories", defaultValue: "Calories"), c.kcal, p.targetCalories, ""),
            row("protein", String(localized: "macros.protein", defaultValue: "Protein"), c.protein, p.targetProteinG, "g"),
            row("carbs", String(localized: "macros.carbs", defaultValue: "Carbs"), c.carbs, p.targetCarbsG, "g"),
            row("fat", String(localized: "macros.fat", defaultValue: "Fat"), c.fat, p.targetFatG, "g"),
        ]
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let rows = macroRows {
            FACard { MacroBars(rows: rows, showScore: false, onTap: { router.push(.macro($0)) }) }
        } else {
            Button { router.push(.nutritionTargets) } label: {
                FACard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(localized: "macros.setup.title", defaultValue: "Set up your nutrition profile")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink).padding(.bottom, 6)
                        Text(String(localized: "macros.setup.body", defaultValue: "Add your height, weight and age to calculate personalised macro targets and daily progress."))
                            .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.bottom, 14)
                        Text(String(localized: "macros.setup.cta", defaultValue: "Set up profile ›")).font(FATypography.sans(13, .semibold, relativeTo: .caption)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(FAColor.forestSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous).strokeBorder(FAColor.goldSoft.opacity(0.7), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 2 · Micronutrients

    private var micronutrientsCard: some View {
        let consumedMicros = model.consumedToday
        let score = MicroCoverage.overall(meals: model.todayMeals, sex: model.sex) ?? 0
        let gaps = NutritionMath.gaps(threshold: 0.7, sex: model.sex, limit: 99, consumed: consumedMicros).count
        let tone: Color = score >= 75 ? FAColor.forestSoft : score >= 50 ? FAColor.warning : CoverageTone.red
        return Button { router.push(.micronutrients) } label: {
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(String(localized: "micros.title", defaultValue: "Micronutrients")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(score)%").font(FATypography.sans(17, .bold, relativeTo: .body)).foregroundStyle(tone)
                            Text(String(localized: "micros.coverage", defaultValue: "coverage")).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                        }
                    }
                    Text(String(localized: "micros.belowTarget", defaultValue: "\(gaps) below target")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                    VStack(spacing: 12) {
                        ForEach(NutrientCatalog.groups) { group in
                            let pct = NutritionMath.groupCoverage(group.key, sex: model.sex, consumed: consumedMicros)
                            VStack(spacing: 6) {
                                HStack {
                                    Text(group.name).font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                                    Spacer()
                                    Text("\(pct)%").font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(group.color)
                                }
                                HashedBar(color: group.color, pct: Double(pct) / 100, height: 7)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 3 · Today's summary

    @ViewBuilder
    private var todaySummaryCard: some View {
        if let summary = NutritionMath.todaySummary(checkin: model.checkin, mealsCount: model.todayMeals.count) {
            Button { withAnimation(.spring(duration: 0.3)) { openSummary.toggle() } } label: {
                FACard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.goldSoft)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.title).font(FATypography.display(16, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                if !openSummary {
                                    Text(String(localized: "macros.summary.tap", defaultValue: "Today's summary · tap to expand")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(ProfilePalette.muted).rotationEffect(.degrees(openSummary ? 180 : 0))
                        }
                        if openSummary {
                            Text(summary.note).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5).padding(.top, 12)
                            HStack(spacing: 8) {
                                ForEach(summary.metrics) { metric in
                                    VStack(spacing: 3) {
                                        Text(metric.value).font(FATypography.sans(16, .bold, relativeTo: .body)).foregroundStyle(metric.good ? Color(hex: 0x4A8A5C) : FAColor.warning)
                                        Text(metric.label.uppercased()).font(FATypography.sans(9.5, .semibold, relativeTo: .caption2)).tracking(0.4).foregroundStyle(ProfilePalette.muted)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.top, 14)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            FACard {
                Text(String(localized: "macros.summary.empty", defaultValue: "Complete today's check-in to see your summary")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
            }
        }
    }

    // MARK: 4 · Today's meals

    @ViewBuilder
    private var mealsList: some View {
        let meals = model.todayMeals
        if meals.isEmpty {
            FACard {
                Text(String(localized: "macros.meals.none", defaultValue: "No meals logged today")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
            }
        } else {
            ForEach(meals) { meal in
                Button { router.push(.meal(meal.id)) } label: {
                    MealSummaryRow(meal: meal, nutrientScore: NutritionMath.mealNutrientScore(meal, sex: model.sex, mealsToday: meals.count))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The Expo `MealCard` as the macros page uses it: name, time, macro line, the per-meal nutrient score.
struct MealSummaryRow: View {
    let meal: MealLog
    let nutrientScore: Int?

    var body: some View {
        FACard(padded: false) {
            HStack(spacing: 12) {
                MealThumb(meal: meal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.displayName).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(1)
                    Text(Format.time(meal.loggedAt)).font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    LogMacroLine(kcal: meal.totalCalories, protein: meal.totalProteinG, carbs: meal.totalCarbsG, fat: meal.totalFatG)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Text(String(localized: "macros.meal.nutrients", defaultValue: "Nutrients")).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                    Text(nutrientScore.map { "\($0)" } ?? "·").font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                    Text("›").foregroundStyle(ProfilePalette.muted).padding(.leading, 2)
                }
            }
            .padding(12)
        }
    }
}

/// A small photo or a meal-type glyph, the meal card's left edge.
private struct MealThumb: View {
    let meal: MealLog
    @Environment(AppDependencies.self) private var dependencies
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FAColor.forestGlow)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "fork.knife").font(.system(size: 16, weight: .medium)).foregroundStyle(FAColor.forestSoft)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: meal.photoPath) {
            guard let path = meal.photoPath, image == nil else { return }
            if let url = try? await dependencies.meals.photoURL(path: path), let (data, _) = try? await URLSession.shared.data(from: url) {
                image = UIImage(data: data)
            }
        }
    }
}
