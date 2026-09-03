import SwiftUI

/// Full-screen "Your plate, read." flow: shows what the member gave, the pipeline steps, then the result.
struct CaptureView: View {
    @Environment(AppDependencies.self) private var dependencies
    let request: CaptureRequest
    let onFinish: () -> Void
    @State private var model: CaptureViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                FAColor.background.ignoresSafeArea()
                if let model {
                    CaptureContent(model: model, onFinish: onFinish)
                }
            }
            .navigationTitle(String(localized: "capture.title", defaultValue: "Your meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "action.close", defaultValue: "Close")) { onFinish() }
                        .foregroundStyle(FAColor.brand)
                }
            }
        }
        .task {
            if model == nil {
                let m = CaptureViewModel(request: request, meals: dependencies.meals, members: dependencies.members)
                model = m
                m.start()
            }
        }
        .onDisappear { model?.cancel() }
    }
}

private struct CaptureContent: View {
    @Bindable var model: CaptureViewModel
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FASpacing.lg) {
                inputPreview
                switch model.phase {
                case .starting, .working:
                    steps
                case .done(let meal):
                    result(meal)
                case .attention(let meal):
                    attention(meal)
                case .stillWorking:
                    stillWorking
                case .failed(let error):
                    FAErrorState(title: String(localized: "capture.failed.title", defaultValue: "Couldn't save this meal"), message: error.userMessage) {
                        model.restart()
                    }
                }
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: What the member gave

    @ViewBuilder
    private var inputPreview: some View {
        if let data = model.request.input.photos.first, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.lg, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                .accessibilityLabel(String(localized: "capture.photo.a11y", defaultValue: "Your meal photo"))
        } else if let words = model.request.input.trimmedDescription {
            FACard {
                VStack(alignment: .leading, spacing: FASpacing.xs) {
                    Text(String(localized: "capture.youSaid", defaultValue: "You said").uppercased())
                        .font(FATypography.label)
                        .foregroundStyle(FAColor.accent)
                        .tracking(0.8)
                    Text("“\(words)”")
                        .font(FATypography.body)
                        .italic()
                        .foregroundStyle(FAColor.ink)
                }
            }
        }
    }

    // MARK: Pipeline

    private var steps: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Text(String(localized: "capture.reading", defaultValue: "Your plate, read."))
                    .font(FATypography.title)
                    .foregroundStyle(FAColor.ink)
                step(1, String(localized: "capture.step.saved", defaultValue: "Meal saved"))
                step(2, String(localized: "capture.step.identifying", defaultValue: "Reading what's on the plate"))
                step(3, String(localized: "capture.step.pricing", defaultValue: "Adding calories & macros"))
                step(4, String(localized: "capture.step.done", defaultValue: "Done"))
                Text(String(localized: "capture.leaveHint", defaultValue: "You can close this — the meal keeps being analysed and updates in your list."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkMuted)
            }
        }
    }

    private func step(_ index: Int, _ title: String) -> some View {
        let current = model.stepIndex
        return HStack(spacing: FASpacing.sm) {
            Group {
                if index < current || (index == 4 && current == 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FAColor.success)
                } else if index == current {
                    ProgressView().tint(FAColor.brand)
                } else {
                    Image(systemName: "circle").foregroundStyle(FAColor.inkMuted)
                }
            }
            .frame(width: 22)
            Text(title)
                .font(FATypography.body)
                .foregroundStyle(index <= current ? FAColor.ink : FAColor.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Result

    private func result(_ meal: MealLog) -> some View {
        VStack(alignment: .leading, spacing: FASpacing.lg) {
            VStack(alignment: .leading, spacing: FASpacing.xs) {
                Text(String(localized: "capture.done.kicker", defaultValue: "Logged").uppercased())
                    .font(FATypography.label)
                    .foregroundStyle(FAColor.accent)
                    .tracking(0.8)
                Text(meal.displayName)
                    .font(FATypography.largeTitle)
                    .foregroundStyle(FAColor.ink)
                MacroLine(kcal: meal.totalCalories, protein: meal.totalProteinG, carbs: meal.totalCarbsG, fat: meal.totalFatG)
            }
            if let scores = meal.scores {
                MealScoresCard(scores: scores)
            }
            if !meal.items.isEmpty {
                MealItemsCard(items: meal.items)
            }
            FAButton(title: String(localized: "action.done", defaultValue: "Done")) { onFinish() }
        }
    }

    // MARK: Needs input / failed

    private func attention(_ meal: MealLog) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Label(
                    meal.status == .failed
                        ? String(localized: "capture.failed.short", defaultValue: "We couldn't read this meal")
                        : String(localized: "capture.needsInput.title", defaultValue: "Tell us a little more"),
                    systemImage: meal.status == .failed ? "exclamationmark.triangle" : "questionmark.circle"
                )
                .font(FATypography.headline)
                .foregroundStyle(FAColor.ink)
                Text(String(localized: "capture.needsInput.message", defaultValue: "What was on the plate? A few words are enough — we'll read it again."))
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.inkSecondary)
                TextField(String(localized: "food.describe.placeholder", defaultValue: "e.g. grilled chicken, sweet potato, salad"), text: $model.retryDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .font(FATypography.body)
                    .padding(12)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous)
                            .strokeBorder(FAColor.separator, lineWidth: 1)
                    }
                FAButton(title: String(localized: "action.tryAgain", defaultValue: "Try again")) { model.retry() }
                FAButton(title: String(localized: "capture.keep", defaultValue: "Keep it as is"), style: .tertiary) { onFinish() }
            }
        }
    }

    private var stillWorking: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Label(String(localized: "capture.slow.title", defaultValue: "Still working on it"), systemImage: "clock")
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
                Text(String(localized: "capture.slow.message", defaultValue: "Your meal is saved. The analysis finishes in the background and shows up in your list."))
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.inkSecondary)
                FAButton(title: String(localized: "action.done", defaultValue: "Done")) { onFinish() }
            }
        }
    }
}

/// The three food scores as rings. Every line describes the FOOD, never the person.
struct MealScoresCard: View {
    let scores: MealScores

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Text(String(localized: "meal.scores.title", defaultValue: "How this meal reads"))
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
                HStack(alignment: .top, spacing: FASpacing.sm) {
                    ScoreRing(value: scores.inflammation, label: String(localized: "meal.score.inflammation", defaultValue: "Inflammation"), color: FAColor.scoreInflammation, verdict: Verdict.inflammation(scores.inflammation))
                    ScoreRing(value: scores.glycemic, label: String(localized: "meal.score.glycemic", defaultValue: "Glycemic"), color: FAColor.scoreGlycemic, verdict: Verdict.glycemic(scores.glycemic))
                    ScoreRing(value: scores.digestion, label: String(localized: "meal.score.digestion", defaultValue: "Digestion"), color: FAColor.scoreDigestion, verdict: Verdict.digestion(scores.digestion))
                }
            }
        }
    }

    /// Same thresholds and wording as the Expo app's `legacyVerdict` (72 / 55).
    enum Verdict {
        static func digestion(_ v: Int) -> String {
            v >= 72 ? String(localized: "verdict.digestion.high", defaultValue: "Fibre-rich, with good plant variety.")
                : v >= 55 ? String(localized: "verdict.digestion.mid", defaultValue: "Some fibre and plant variety · one more plant would lift it.")
                : String(localized: "verdict.digestion.low", defaultValue: "Little fibre or plant variety in this meal.")
        }
        static func inflammation(_ v: Int) -> String {
            v >= 72 ? String(localized: "verdict.inflammation.high", defaultValue: "Fat here comes mostly from whole-food sources.")
                : v >= 55 ? String(localized: "verdict.inflammation.mid", defaultValue: "A mixed picture of fat sources.")
                : String(localized: "verdict.inflammation.low", defaultValue: "Fat here comes mostly from processed or refined sources.")
        }
        static func glycemic(_ v: Int) -> String {
            v >= 72 ? String(localized: "verdict.glycemic.high", defaultValue: "Carbohydrate arrives largely with its fibre intact.")
                : v >= 55 ? String(localized: "verdict.glycemic.mid", defaultValue: "A mix of intact and refined carbohydrate.")
                : String(localized: "verdict.glycemic.low", defaultValue: "Carbohydrate here is mostly refined or sweetened.")
        }
    }
}

struct ScoreRing: View {
    let value: Int
    let label: String
    let color: Color
    let verdict: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, value))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
            }
            .frame(width: 64, height: 64)
            Text(label)
                .font(FATypography.label)
                .foregroundStyle(FAColor.ink)
            Text(verdict)
                .font(FATypography.caption)
                .foregroundStyle(FAColor.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) out of 100. \(verdict)")
    }
}

struct MealItemsCard: View {
    let items: [MealItem]

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                Text(String(localized: "meal.items.title", defaultValue: "On the plate"))
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name.capitalized)
                            .font(FATypography.body)
                            .foregroundStyle(FAColor.ink)
                        Spacer()
                        Text(detail(item))
                            .font(FATypography.caption)
                            .foregroundStyle(FAColor.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func detail(_ item: MealItem) -> String {
        var parts: [String] = []
        if let g = item.estimatedGrams { parts.append(Format.grams(g)) }
        if let k = item.kcal { parts.append(Format.kcal(k)) }
        return parts.joined(separator: " · ")
    }
}
