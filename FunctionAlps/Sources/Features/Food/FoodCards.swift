import SwiftUI

// The Food tab's cards, one-to-one with the Expo `(tabs)/log.tsx` components:
// `MacrosTodayCard` (+ `MacroBars` / `NutriRow`, on the shared `HashedBar`), `PhotoScanCard`, `FavoritesStrip`,
// `DescribeMealCard` (bare), `LogMealCard` (+ `MealReactionLine`) and `RelogToast`. Sizes, colours
// and spacings are the web's numbers; only the theme is fixed to the light palette the wall uses.

// MARK: - Palette (Expo `MacroBars.MACRO_PASTEL` / `LABEL`, `MacrosTodayCard.MICRO` / `CURSOR`)

enum FoodPalette {
    static let pastel: [String: UInt32] = ["kcal": 0x9FC8A6, "protein": 0xE0A0A0, "carbs": 0xE6CF85, "fat": 0xA6C2E0]
    static let label: [String: UInt32] = ["kcal": 0x5E9A6E, "protein": 0xC97B7B, "carbs": 0xC2A24A, "fat": 0x7BA0C9]
    static let micro = Color(hex: 0xC2A6DC)
    static let cursor = Color(red: 96 / 255, green: 116 / 255, blue: 140 / 255, opacity: 0.95)
    /// Light-theme tokens (`lib/theme/palette.ts`): hairline, muted text, soft fill, accent soft.
    static let hairline = Color(hex: 0x1A1A16, opacity: 0.08)
    static let muted = FAColor.stone
    static let surfaceSoft = Color.white.opacity(0.45)
    static let accentSoft = Color(hex: 0x4A8A5C, opacity: 0.14)
    /// The Expo `MACRO_RING_COLORS` — the meal card's macro line.
    static let ringKcal = FAColor.forestSoft
    static let ringProtein = Color(hex: 0xE0A0A0)
    static let ringCarbs = Color(hex: 0xE6CF85)
    static let ringFat = Color(hex: 0xA6C2E0)
}

// MARK: - MacroBars

/// One macro row's data (`MacroBarRow`).
struct MacroBarRow: Identifiable {
    let key: String
    let label: String
    let pct: Double
    let current: String
    let target: String
    var id: String { key }
}

/// Coloured name on the left, hashed bar, `current/target` on the right; the optional "NN MACROS"
/// header above.
struct MacroBars: View {
    let rows: [MacroBarRow]
    var score: Int? = nil
    var showScore = true
    var barHeight: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            if showScore {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Spacer(minLength: 0)
                    Text(score.map { "\($0)" } ?? "·")
                        .font(FATypography.sans(18, .bold, relativeTo: .title3))
                        .foregroundStyle(FAColor.ink)
                    Text(String(localized: "food.macros.header", defaultValue: "MACROS"))
                        .font(FATypography.sans(8, .bold, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(FoodPalette.muted)
                }
                .padding(.bottom, 10)
            }
            ForEach(rows) { m in
                HStack(spacing: 9) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: FoodPalette.pastel[m.key] ?? 0x9FC8A6)).frame(width: 7, height: 7)
                        Text(m.label)
                            .font(FATypography.sans(11, .semibold, relativeTo: .caption))
                            .foregroundStyle(FoodPalette.label[m.key].map { Color(hex: $0) } ?? FoodPalette.muted)
                            .lineLimit(1)
                    }
                    .frame(width: 78, alignment: .leading)
                    HashedBar(color: Color(hex: FoodPalette.pastel[m.key] ?? 0x9FC8A6), pct: m.pct, height: barHeight)
                    (Text(m.current).font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundColor(FAColor.ink)
                        + Text("/\(m.target)").font(FATypography.sans(11, relativeTo: .caption)).foregroundColor(FoodPalette.muted))
                        .frame(width: 66, alignment: .trailing)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(m.label): \(m.current) of \(m.target)")
            }
        }
    }
}

// MARK: - NutriRow

/// One nutri-score row: a thick red↔green gradient bar with a grey-blue cursor at the value (green to
/// the right, higher = better), then the number and the score name.
struct NutriRow: View {
    let label: String
    let value: Int?

    var body: some View {
        let pos = value.map { Double(min(97, max(3, $0))) / 100 } ?? 0.5
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    if value == nil {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 1))
                            p.addLine(to: CGPoint(x: geo.size.width, y: 1))
                        }
                        .stroke(FoodPalette.hairline, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .frame(height: 2)
                    } else {
                        ZStack(alignment: .top) {
                            LinearGradient(colors: [Color(hex: 0xD98C7E), Color(hex: 0xE6CD7A), Color(hex: 0x8FBF97)], startPoint: .leading, endPoint: .trailing)
                            Rectangle().fill(Color.white.opacity(0.4)).frame(height: 2)
                        }
                        .frame(height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(value == nil ? FoodPalette.hairline : FoodPalette.cursor)
                        .frame(width: 3, height: 10)
                        .shadow(color: value == nil ? .clear : FoodPalette.cursor.opacity(0.5), radius: 3)
                        .offset(x: geo.size.width * pos - 1.5)
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8)
            Text(value.map { "\($0)" } ?? "·")
                .font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                .foregroundStyle(value == nil ? FoodPalette.muted : FAColor.ink)
                .frame(width: 24, alignment: .trailing)
            Text(label)
                .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2))
                .foregroundStyle(FoodPalette.muted)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(label): \($0) out of 100" } ?? "\(label): no data yet")
    }
}

// MARK: - MacrosTodayCard

/// The Food tab's lead card: macro bars + macros score, the 14-day micros trend, the three nutri-score
/// lines — three hairline-separated sections in one glass card. Bars are always shown; the targets and
/// the fill appear once the profile carries `target_*`.
struct MacrosTodayCard: View {
    let todayMeals: [MealLog]
    let profile: MemberProfile?
    /// 14 days oldest first, nil where no meal carries micros (`FoodViewModel.microTrend`).
    let microTrend: [Int?]
    let todayScores: MealScores?

    private var consumed: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        (todayMeals.compactMap(\.totalCalories).reduce(0, +),
         todayMeals.compactMap(\.totalProteinG).reduce(0, +),
         todayMeals.compactMap(\.totalCarbsG).reduce(0, +),
         todayMeals.compactMap(\.totalFatG).reduce(0, +))
    }

    private var rows: [MacroBarRow] {
        let c = consumed
        func row(_ key: String, _ label: String, _ value: Double, _ target: Int?, _ unit: String) -> MacroBarRow {
            var pct = 0.0
            if let target, target > 0 { pct = value / Double(target) }
            return MacroBarRow(key: key, label: label, pct: pct, current: "\(Int(value.rounded()))", target: target.map { "\($0)\(unit)" } ?? "·")
        }
        return [
            row("kcal", String(localized: "macros.calories", defaultValue: "Calories"), c.kcal, profile?.targetCalories, ""),
            row("protein", String(localized: "macros.protein", defaultValue: "Protein"), c.protein, profile?.targetProteinG, "g"),
            row("carbs", String(localized: "macros.carbs", defaultValue: "Carbs"), c.carbs, profile?.targetCarbsG, "g"),
            row("fat", String(localized: "macros.fat", defaultValue: "Fat"), c.fat, profile?.targetFatG, "g"),
        ]
    }

    private var macrosScore: Int? {
        let c = consumed
        return MicroCoverage.macroProximity(protein: c.protein, carbs: c.carbs, fat: c.fat, targetProtein: profile?.targetProteinG, targetCarbs: profile?.targetCarbsG, targetFat: profile?.targetFatG)
    }

    private var microToday: Int? { MicroCoverage.overall(meals: todayMeals, sex: profile?.sex) }

    private var microA11y: String {
        if let microToday {
            return String(localized: "food.micros.a11y", defaultValue: "Micronutrient coverage over 14 days, today \(microToday) percent")
        }
        return String(localized: "food.micros.a11y.none", defaultValue: "Micronutrient coverage over 14 days, no data today")
    }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                // ── Section 1 · Macros — horizontal bars + score ──
                MacroBars(rows: rows, score: macrosScore)

                // ── Section 2 · Micros — 14-day trend ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 7) {
                            Circle().fill(FoodPalette.micro).frame(width: 7, height: 7)
                            Text(String(localized: "food.micros.title", defaultValue: "Micros"))
                                .font(FATypography.sans(11.5, .semibold, relativeTo: .caption))
                                .foregroundStyle(FoodPalette.muted)
                            Text(String(localized: "food.micros.range", defaultValue: "· 14 days"))
                                .font(FATypography.sans(9.5, relativeTo: .caption2))
                                .foregroundStyle(FoodPalette.muted)
                        }
                        Spacer()
                        Text(microToday.map { "\($0)" } ?? "·")
                            .font(FATypography.sans(12, .bold, relativeTo: .caption))
                            .foregroundStyle(FAColor.ink)
                    }
                    MicroTrendBars(values: microTrend)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(FoodPalette.hairline).frame(height: 1) }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(microA11y)

                // ── Section 3 · Nutri scores — all three higher-is-better, green to the right ──
                VStack(spacing: 0) {
                    NutriRow(label: MealScoreKind.digestion.title, value: todayScores?.digestion)
                    NutriRow(label: MealScoreKind.inflammation.title, value: todayScores?.inflammation)
                    NutriRow(label: MealScoreKind.glycemic.title, value: todayScores?.glycemic)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(FoodPalette.hairline).frame(height: 1) }
                .padding(.top, 12)
            }
        }
    }
}

/// The 14 day bars, 24 tall: 3 px hairline stubs where there is no data.
private struct MicroTrendBars: View {
    let values: [Int?]
    @State private var fill: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(v == nil ? FoodPalette.hairline : FoodPalette.micro)
                    .frame(maxWidth: .infinity)
                    .frame(height: v.map { max(3, CGFloat(min(100, max(0, $0))) / 100 * 24 * CGFloat(fill)) } ?? 3)
                    .opacity(v == nil ? 0.45 : 1)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .mountFill($fill)
    }
}

// MARK: - PhotoScanCard

/// The capture hero: the plate-demo photo with the scan band sweeping it on loop, one food priced
/// (bobbing), one still being read (shimmering), and the Photo action on the bottom veil.
struct PhotoScanCard: View {
    let onPress: () -> Void
    private static let height: CGFloat = 150

    var body: some View {
        Button(action: onPress) {
            ZStack(alignment: .topLeading) {
                Color(hex: 0x1B1A17)
                FABundledImage(name: "plate-demo", ext: "jpg", contentMode: .fill)
                    .frame(height: Self.height)
                    .frame(maxWidth: .infinity)
                    .clipped()

                // scan band: 2100 ms sweep, 1200 ms pause, reset
                TimelineView(.animation) { context in
                    let cycle = 3.3
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                    let raw = min(1, phase / 2.1)
                    let eased = 0.5 - 0.5 * cos(raw * .pi)
                    LinearGradient(
                        colors: [
                            Color(hex: 0x8FBF97, opacity: 0), Color(hex: 0x8FBF97, opacity: 0.22), Color.white.opacity(0.5),
                            Color(hex: 0x8FBF97, opacity: 0.22), Color(hex: 0x8FBF97, opacity: 0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: Self.height * 0.42)
                    .offset(y: -Self.height * 0.45 + CGFloat(eased) * Self.height * 1.5)
                }
                .allowsHitTesting(false)

                // one food priced (bobbing), one still being read (shimmer)
                TimelineView(.animation) { context in
                    let raw = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
                    let bob = 0.5 - 0.5 * cos(raw * 2 * .pi)
                    (Text("Avocado · 70 g ").foregroundColor(Color(hex: 0x1A1A16))
                        + Text(String(localized: "food.scan.demoKcal", defaultValue: "112 kcal")).foregroundColor(FAColor.forestSoft))
                        .font(FATypography.sans(10, .bold, relativeTo: .caption2))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .offset(y: -3 * CGFloat(bob))
                }
                .padding(12)
                .allowsHitTesting(false)

                ShimmerBar(height: 6, width: 44, radius: 3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)

                // bottom veil + action row
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(FAColor.forestSoft)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(FAColor.charcoal)
                            }
                            .frame(width: 34, height: 34)
                            Text(String(localized: "food.photo.cta", defaultValue: "Photo"))
                                .font(FATypography.display(18, relativeTo: .title3))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("›")
                                .font(FATypography.sans(16, .bold, relativeTo: .body))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "food.photo.title", defaultValue: "Add your meal by photo"))
    }
}

// MARK: - FavoritesStrip

/// "Or log a favorite again" — the chip strip inside the capture card; renders nothing until the
/// first favorite exists.
struct FavoritesStrip: View {
    let favorites: [FavoriteMeal]
    let onLog: (FavoriteMeal) -> Void

    var body: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(String(localized: "food.favorites.title", defaultValue: "Or log a favorite again").uppercased())
                    .font(FATypography.sans(9.5, .bold, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(FoodPalette.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favorites) { fav in
                            FavoriteChip(favorite: fav) { onLog(fav) }
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(FoodPalette.hairline).frame(height: 1) }
            .padding(.top, 12)
        }
    }
}

private struct FavoriteChip: View {
    let favorite: FavoriteMeal
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 8) {
                if favorite.photoPath != nil {
                    MealPhotoView(path: favorite.photoPath, width: 28, height: 28, cornerRadius: 14)
                } else {
                    Circle().fill(Color(hex: 0x4A8A5C, opacity: 0.25)).frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(favorite.name)
                        .font(FATypography.sans(11, .semibold, relativeTo: .caption))
                        .foregroundStyle(FAColor.ink)
                        .lineLimit(1)
                    if let kcal = favorite.kcal {
                        Text("\(Int(kcal.rounded())) kcal")
                            .font(FATypography.sans(9, relativeTo: .caption2))
                            .foregroundStyle(FoodPalette.muted)
                    }
                }
                ZStack {
                    Circle().fill(FAColor.forestSoft)
                    Image(systemName: "plus").font(.system(size: 10, weight: .heavy)).foregroundStyle(FAColor.charcoal)
                }
                .frame(width: 18, height: 18)
                .padding(.leading, 2)
            }
            .padding(.vertical, 5)
            .padding(.leading, 5)
            .padding(.trailing, 11)
            .background(FoodPalette.surfaceSoft, in: Capsule())
            .overlay { Capsule().strokeBorder(FoodPalette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "food.favorites.logAgain", defaultValue: "Log \(favorite.name) again"))
    }
}

// MARK: - DescribeMeal (bare)

/// Speak (button on top) or type (under) a meal, then the text summary with "Analyse with AI".
struct DescribeMealBare: View {
    @Bindable var model: FoodViewModel
    let onAnalyse: () -> Void
    @FocusState private var focused: Bool
    @State private var pulse = false

    var body: some View {
        let dictation = model.dictation
        VStack(alignment: .leading, spacing: 0) {
            Button { dictation.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic").font(.system(size: 14, weight: .semibold))
                    Text(dictation.listening
                         ? String(localized: "food.voice.listening", defaultValue: "Listening… speak your meal")
                         : String(localized: "food.voice.cta", defaultValue: "Describe by voice"))
                        .font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                }
                .foregroundStyle(dictation.listening ? Color.white : FAColor.forestSoft)
                .opacity(dictation.listening && pulse ? 0.55 : 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(dictation.listening ? FAColor.forestSoft : FoodPalette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .onChange(of: dictation.listening) { _, on in
                if on { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } } else { withAnimation(.default) { pulse = false } }
            }

            if dictation.listening, !dictation.interim.isEmpty {
                Text(dictation.interim + "…")
                    .font(FATypography.sans(13, relativeTo: .subheadline)).italic()
                    .foregroundStyle(FoodPalette.muted)
                    .lineLimit(2)
                    .padding(.top, 8)
            }
            if let error = dictation.error {
                Text(error)
                    .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xC0453A))
                    .padding(.top, 8)
            }

            TextField(
                String(localized: "food.describe.placeholder", defaultValue: "or type · e.g. grilled chicken, sweet potato, salad"),
                text: $model.description,
                axis: .vertical
            )
            .lineLimit(2...6)
            .font(FATypography.sans(15, relativeTo: .body))
            .foregroundStyle(FAColor.ink)
            .focused($focused)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 52, alignment: .top)
            .background(FoodPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FoodPalette.hairline, lineWidth: 1) }
            .padding(.top, 10)

            // Text-only summary: the typed meal split into lines + the analyse button.
            let items = model.describedItems
            if !dictation.listening, !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(items.prefix(2).joined(separator: " + "))
                        .font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                        .foregroundStyle(FAColor.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(items, id: \.self) { item in
                            Text("• \(item)")
                                .font(FATypography.sans(11.5, relativeTo: .caption))
                                .foregroundStyle(FoodPalette.muted)
                        }
                    }
                    .padding(.top, 6)
                    Button {
                        focused = false
                        onAnalyse()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                            Text(String(localized: "food.describe.analyse", defaultValue: "Analyse with AI"))
                                .font(FATypography.sans(13.5, .bold, relativeTo: .subheadline))
                        }
                        .foregroundStyle(FAColor.charcoal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(FAColor.forestSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .padding(12)
                .background(FoodPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FoodPalette.hairline, lineWidth: 1) }
                .padding(.top, 10)
            }
        }
    }
}

// MARK: - LogMealCard

/// The past-meal card (C-1): name with the macros under it, the reaction line, photo on the right
/// in a bordered radius-16 square, the two pills and the greyed date. Deleting lives on meal detail.
struct LogMealCard: View {
    let meal: MealLog
    let reaction: MealReaction?
    let isFavorite: Bool
    let when: String
    let onRelog: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: Route.meal(meal.id)) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(meal.displayName)
                                .font(FATypography.sans(13.5, .bold, relativeTo: .subheadline))
                                .foregroundStyle(FAColor.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            statusOrMacros.padding(.top, 3)
                            MealReactionLine(reaction: reaction).padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if meal.photoPath != nil {
                            MealPhotoView(path: meal.photoPath, width: 76, height: 76, cornerRadius: 16)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(FoodPalette.surfaceSoft)
                                .frame(width: 76, height: 76)
                                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FoodPalette.hairline, lineWidth: 1) }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .bottom, spacing: 7) {
                    MealPill(label: String(localized: "food.meal.logAgain", defaultValue: "Log again"), systemImage: "plus", kind: .primary, action: onRelog)
                        .accessibilityLabel(String(localized: "food.favorites.logAgain", defaultValue: "Log \(meal.displayName) again"))
                    MealPill(label: String(localized: "food.meal.favorite", defaultValue: "Favorite"), systemImage: isFavorite ? "star.fill" : "star", iconColor: isFavorite ? FAColor.goldSoft : FAColor.ink, kind: .outline, action: onToggleFavorite)
                        .accessibilityLabel(isFavorite
                            ? String(localized: "food.meal.unfavorite.a11y", defaultValue: "Remove \(meal.displayName) from favorites")
                            : String(localized: "food.meal.favorite.a11y", defaultValue: "Add \(meal.displayName) to favorites"))
                    Spacer(minLength: 0)
                    Text(when)
                        .font(FATypography.sans(9.5, relativeTo: .caption2))
                        .foregroundStyle(FoodPalette.muted)
                }
                .padding(.top, 11)
            }
        }
    }

    @ViewBuilder
    private var statusOrMacros: some View {
        switch meal.status {
        case .queued, .identifying, .pricing:
            Label(String(localized: "meal.status.analyzing", defaultValue: "Analysing…"), systemImage: "sparkles")
                .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.accent)
        case .needsInput:
            Label(String(localized: "meal.status.needsInput", defaultValue: "Needs your input"), systemImage: "questionmark.circle")
                .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.warning)
        case .failed:
            Label(String(localized: "meal.status.failed", defaultValue: "Analysis failed"), systemImage: "exclamationmark.circle")
                .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.danger)
        case .complete:
            LogMacroLine(kcal: meal.totalCalories, protein: meal.totalProteinG, carbs: meal.totalCarbsG, fat: meal.totalFatG)
        }
    }
}

/// `420 kcal · P 18 C 60 F 12` in the locked macro palette (meal detail, result page).
struct MacroLine: View {
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    var body: some View {
        (Text(Format.kcal(kcal ?? 0)).foregroundColor(FAColor.accent).bold()
            + Text("  ·  ").foregroundColor(FAColor.inkMuted)
            + Text("P \(Int((protein ?? 0).rounded()))").foregroundColor(FAColor.protein).bold()
            + Text("   ").foregroundColor(FAColor.inkMuted)
            + Text("C \(Int((carbs ?? 0).rounded()))").foregroundColor(FAColor.carbs).bold()
            + Text("   ").foregroundColor(FAColor.inkMuted)
            + Text("F \(Int((fat ?? 0).rounded()))").foregroundColor(FAColor.fat).bold())
            .font(FATypography.caption)
            .accessibilityLabel(String(localized: "macros.a11y", defaultValue: "\(Int((kcal ?? 0).rounded())) kilocalories, protein \(Int((protein ?? 0).rounded())) grams, carbs \(Int((carbs ?? 0).rounded())) grams, fat \(Int((fat ?? 0).rounded())) grams"))
    }
}

/// `420 kcal  ·  P 18  C 60  F 12` in the Expo `MACRO_RING_COLORS` (forest kcal, pastel P/C/F) — the
/// log card's line. Meal detail and the result page keep `MacroLine` (the locked macro palette).
struct LogMacroLine: View {
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    var body: some View {
        let bold = FATypography.sans(11, .bold, relativeTo: .caption)
        let plain = FATypography.sans(11, relativeTo: .caption)
        (Text("\(Int((kcal ?? 0).rounded())) kcal").font(bold).foregroundColor(FoodPalette.ringKcal)
            + Text("  ·  ").font(plain).foregroundColor(FoodPalette.muted)
            + Text("P \(Int((protein ?? 0).rounded()))").font(bold).foregroundColor(FoodPalette.ringProtein)
            + Text("  ").font(plain)
            + Text("C \(Int((carbs ?? 0).rounded()))").font(bold).foregroundColor(FoodPalette.ringCarbs)
            + Text("  ").font(plain)
            + Text("F \(Int((fat ?? 0).rounded()))").font(bold).foregroundColor(FoodPalette.ringFat))
            .accessibilityLabel(String(localized: "macros.a11y", defaultValue: "\(Int((kcal ?? 0).rounded())) kilocalories, protein \(Int((protein ?? 0).rounded())) grams, carbs \(Int((carbs ?? 0).rounded())) grams, fat \(Int((fat ?? 0).rounded())) grams"))
    }
}

/// The "how it felt" line: sentiment dot + word + top flags; un-rated meals show the hint.
struct MealReactionLine: View {
    let reaction: MealReaction?
    var size: CGFloat = 10.5

    var body: some View {
        if let reaction, let sentiment = reaction.sentiment {
            let tone: Color = sentiment == .good ? Color(hex: 0x4A8A5C) : sentiment == .watch ? Color(hex: 0xC99A3B) : Color(hex: 0xC0453A)
            let word = sentiment == .good
                ? String(localized: "meal.felt.good", defaultValue: "Sat well")
                : sentiment == .watch ? String(localized: "meal.felt.watch", defaultValue: "A bit off") : String(localized: "meal.felt.bad", defaultValue: "Rough")
            let labels = reaction.flagLabels()
            HStack(spacing: 5) {
                Circle().fill(tone).frame(width: 6, height: 6)
                Text(word).font(FATypography.sans(size, .semibold, relativeTo: .caption2)).foregroundStyle(tone)
                if !labels.isEmpty {
                    Text("· " + labels.joined(separator: ", ")).font(FATypography.sans(size, relativeTo: .caption2)).foregroundStyle(FoodPalette.muted)
                }
            }
            .lineLimit(1)
        } else {
            Text(String(localized: "meal.felt.unrated", defaultValue: "How did it feel?"))
                .font(FATypography.sans(size, relativeTo: .caption2))
                .foregroundStyle(FoodPalette.muted)
        }
    }
}

private struct MealPill: View {
    enum Kind { case primary, outline }
    let label: String
    let systemImage: String
    var iconColor: Color? = nil
    let kind: Kind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: kind == .primary ? .heavy : .semibold))
                    .foregroundStyle(iconColor ?? (kind == .primary ? FAColor.charcoal : FAColor.ink))
                Text(label)
                    .font(FATypography.sans(10.5, .bold, relativeTo: .caption2))
                    .foregroundStyle(kind == .primary ? FAColor.charcoal : FAColor.ink)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(kind == .primary ? FAColor.forestSoft : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(kind == .primary ? FAColor.forestSoft : FoodPalette.hairline, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RelogToast

/// "{name} logged · NNN kcal added to today" with Adjust / Undo, pinned above the tab bar.
struct RelogToast: View {
    let name: String
    let kcal: Double?
    let onAdjust: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(FAColor.forestSoft)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(FAColor.charcoal)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "food.relog.logged", defaultValue: "\(name) logged"))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xF4F1EA))
                    .lineLimit(1)
                if let kcal {
                    Text(String(localized: "food.relog.added", defaultValue: "\(Int(kcal.rounded())) kcal added to today"))
                        .font(FATypography.sans(10, relativeTo: .caption2))
                        .foregroundStyle(Color(hex: 0xF4F1EA, opacity: 0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onAdjust) {
                Text(String(localized: "food.relog.adjust", defaultValue: "Adjust"))
                    .font(FATypography.sans(12, .bold, relativeTo: .caption))
                    .foregroundStyle(FAColor.forestSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.5), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            Button(action: onUndo) {
                Text(String(localized: "food.relog.undo", defaultValue: "Undo"))
                    .font(FATypography.sans(12, .bold, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xF4F1EA))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xF4F1EA, opacity: 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 460)
        .background(Color(hex: 0x1A1A16, opacity: 0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
