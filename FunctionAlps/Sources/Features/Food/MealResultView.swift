import SwiftUI

// The "final meal page" — the Expo confirm screen in read mode (ConfirmHero → ingredient rows with
// their flags → the flag legend → the three score wheels → "Go back to home"), rendered for a row
// the server is still pricing as well as for a finished one.

/// Top of the page: the plate, the dish name, the macro line, and the one line that says where this
/// meal stands. THE MACRO LINE IS ABSENT, NOT ZERO, before pricing lands.
struct ConfirmHero: View {
    let photo: UIImage?
    let photoPath: String?
    let meal: MealLog?
    let itemCount: Int
    let numbersReady: Bool
    let showItems: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else if let photoPath {
                        MealPhotoView(path: photoPath, width: nil, height: 160, cornerRadius: 16)
                    } else {
                        AsyncImage(url: MealPlaceholderImage.url(mealType: meal?.mealType, dishName: meal?.name ?? "")) { phase in
                            if case .success(let image) = phase { image.resizable().scaledToFill() } else { FAColor.surfaceMuted }
                        }
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if photo == nil && photoPath == nil {
                    Text(String(localized: "meal.mockup", defaultValue: "Mockup image · to illustrate your plate"))
                        .font(FATypography.sans(9, .semibold, relativeTo: .caption2)).foregroundStyle(Color(hex: 0xB9B4A8))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color(hex: 0x14140F, opacity: 0.5), in: Capsule())
                        .padding(8)
                }
            }
            .padding(.bottom, 14)

            Text(meal?.displayName ?? String(localized: "capture.scanning.plate", defaultValue: "Scanning your plate…"))
                .font(FATypography.display(21, relativeTo: .title2)).foregroundStyle(FAColor.ink)

            if numbersReady, let meal {
                MacroLine(kcal: meal.totalCalories, protein: meal.totalProteinG, carbs: meal.totalCarbsG, fat: meal.totalFatG)
                    .padding(.top, 7)
            } else if showItems {
                ShimmerBar(height: 13, width: 190, radius: 7).padding(.top, 9)
            }

            HStack(spacing: 6) {
                if numbersReady {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(FAColor.forestSoft)
                    Text(String(localized: "meal.logged", defaultValue: "Logged to your day")).font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.accent)
                    Text(showItems ? String(localized: "meal.working.pricing", defaultValue: "Looking up the nutrition…") : String(localized: "meal.working.reading", defaultValue: "Reading your plate…"))
                        .font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.accent)
                }
                if itemCount > 0 {
                    Text("· " + String(localized: "meal.ingredients.count", defaultValue: "\(itemCount) ingredients")).font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// The read-mode ingredient list with its PROGRESSIVE REVEAL: rows unveil one after another
/// (60 ms apart) because a list that pops in all at once reads as a page load, while one that
/// resolves in sequence reads as work being finished. Numbers arrive separately from names.
struct MealItemRows: View {
    let items: [MealItem]
    let numbersReady: Bool
    @State private var revealedItems = 0
    @State private var revealedNumbers = 0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i >= revealedItems {
                    VStack(alignment: .leading, spacing: 7) {
                        ShimmerBar(height: 13, radius: 7).frame(maxWidth: 200)
                        ShimmerBar(height: 11, radius: 6).frame(maxWidth: 280)
                    }
                    .padding(.vertical, 12)
                } else {
                    MealItemRow(item: item, numbers: numbersReady && i < revealedNumbers)
                }
                Divider().overlay(FAColor.separator)
            }
        }
        .task(id: items.count) {
            revealedItems = 0
            while revealedItems < items.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.25)) { revealedItems += 1 }
            }
        }
        .task(id: numbersReady) {
            revealedNumbers = 0
            guard numbersReady else { return }
            while revealedNumbers < items.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.25)) { revealedNumbers += 1 }
            }
        }
    }
}

/// One ingredient: name · grams, its flags, then the per-item macro line (or a shimmer).
struct MealItemRow: View {
    let item: MealItem
    var numbers = true

    var body: some View {
        let flags = FoodFlag.flags(of: item)
        let shown = flags.prefix(4)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name.prefix(1).uppercased() + String(item.name.dropFirst()) + (item.estimatedGrams.map { " · \(Int($0.rounded()))g" } ?? ""))
                    .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    ForEach(Array(shown)) { FoodFlagIcon(flag: $0) }
                    if flags.count > shown.count {
                        Text("+\(flags.count - shown.count)").font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
            if numbers {
                (Text(item.kcal.map { "\(Int($0.rounded())) kcal" } ?? "· kcal").foregroundColor(FAColor.forestSoft).bold()
                    + Text("  ·  ").foregroundColor(FAColor.inkSecondary)
                    + Text("P \(Int((item.proteinG ?? 0).rounded()))").foregroundColor(FAColor.protein).bold()
                    + Text("  ").foregroundColor(FAColor.inkSecondary)
                    + Text("C \(Int((item.carbsG ?? 0).rounded()))").foregroundColor(FAColor.carbs).bold()
                    + Text("  ").foregroundColor(FAColor.inkSecondary)
                    + Text("F \(Int((item.fatG ?? 0).rounded()))").foregroundColor(FAColor.fat).bold())
                    .font(FATypography.sans(11.5, relativeTo: .caption))
            } else {
                // A zero here would read as a FACT, so the space where the numbers go shimmers instead.
                ShimmerBar(height: 10, radius: 5).frame(maxWidth: 210).padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Only the flags present in this meal.
struct FlagLegend: View {
    let flags: [FoodFlag]

    var body: some View {
        if !flags.isEmpty {
            FlowLayout(spacing: 10) {
                ForEach(flags) { f in
                    HStack(spacing: 4) {
                        FoodFlagIcon(flag: f, size: 12)
                        Text(f.label).font(FATypography.sans(10, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
            .padding(.top, 10)
        }
    }
}

/// The three food scores — Plants & Fibre leads, because it is the one members can act on most directly.
enum MealScoreKind: CaseIterable, Identifiable, Sendable {
    case digestion, inflammation, glycemic
    var id: Self { self }

    var title: String {
        switch self {
        case .digestion: String(localized: "score.digestion.title", defaultValue: "Plants & Fibre")
        case .inflammation: String(localized: "score.inflammation.title", defaultValue: "Fat Quality")
        case .glycemic: String(localized: "score.glycemic.title", defaultValue: "Carb Quality")
        }
    }
    var short: String {
        switch self {
        case .digestion: String(localized: "score.digestion.short", defaultValue: "Plants")
        case .inflammation: String(localized: "score.inflammation.short", defaultValue: "Fat")
        case .glycemic: String(localized: "score.glycemic.short", defaultValue: "Carbs")
        }
    }
    var color: Color {
        switch self {
        case .digestion: FAColor.scoreDigestion
        case .inflammation: FAColor.scoreInflammation
        case .glycemic: FAColor.scoreGlycemic
        }
    }
    func value(in scores: MealScores) -> Int {
        switch self {
        case .digestion: scores.digestion
        case .inflammation: scores.inflammation
        case .glycemic: scores.glycemic
        }
    }
    /// Every line describes the FOOD, never the person (the Expo `legacyVerdict`, 72 / 55).
    func verdict(_ v: Int) -> String {
        switch self {
        case .digestion: MealScoresCard.Verdict.digestion(v)
        case .inflammation: MealScoresCard.Verdict.inflammation(v)
        case .glycemic: MealScoresCard.Verdict.glycemic(v)
        }
    }
}

/// The three reaction wheels, tappable into their explainers. ONLY EVER RENDERED WITH REAL SCORES.
struct MealScoresRow: View {
    let scores: MealScores
    @State private var explaining: MealScoreKind?

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "meal.scores.heading", defaultValue: "How this meal scored").uppercased())
                .font(FATypography.sans(11, .bold, relativeTo: .caption)).tracking(1.4).foregroundStyle(FAColor.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22).padding(.bottom, 12)
            HStack {
                ForEach(MealScoreKind.allCases) { kind in
                    Button { explaining = kind } label: {
                        VStack(spacing: 5) {
                            ScoreWheel(value: kind.value(in: scores), color: kind.color)
                            Text(kind.short.uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(0.4).foregroundStyle(FAColor.inkSecondary)
                            Text(String(localized: "meal.score.understand", defaultValue: "Understand ›")).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forestSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.title): \(kind.value(in: scores)) out of 100. \(kind.verdict(kind.value(in: scores)))")
                }
            }
            .padding(.bottom, 18)
            Text(String(localized: "meal.scores.curious", defaultValue: "Curious what your plate is really doing? Tap a score and see exactly what's driving it."))
                .font(FATypography.display(15, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).multilineTextAlignment(.center)
                .padding(.horizontal, 10).padding(.bottom, 14)
        }
        .sheet(item: $explaining) { kind in
            ScoreExplainerSheet(kind: kind, value: kind.value(in: scores))
                .presentationDetents([.medium])
        }
    }
}

/// What is driving one score, in plain words.
struct ScoreExplainerSheet: View {
    let kind: MealScoreKind
    let value: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: FASpacing.md) {
            ScoreWheel(value: value, color: kind.color, size: 84)
            Text(kind.title).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
            Text(kind.verdict(value)).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.center)
            Text(String(localized: "meal.score.foodOnly", defaultValue: "This describes the food on the plate, not your body. It changes only when the plate changes."))
                .font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.inkMuted).multilineTextAlignment(.center)
            FAButton(title: String(localized: "action.done", defaultValue: "Done")) { dismiss() }
        }
        .padding(FASpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FAColor.warm)
    }
}
