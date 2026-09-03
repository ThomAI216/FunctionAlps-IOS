import SwiftUI

/// Full-screen capture flow: the scanning transition (plate sweep / reading canvas, the colour-cycling
/// mark, two honest pipeline steps, a rotating tip) hands off to the meal page the moment the food is
/// identified — the Expo `analyzing.tsx` → `confirm.tsx` pair, ON ONE SCREEN.
struct CaptureView: View {
    @Environment(AppDependencies.self) private var dependencies
    let request: CaptureRequest
    let onFinish: () -> Void
    @State private var model: CaptureViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                if let model {
                    if model.showsResult {
                        MealResultPage(model: model, onFinish: onFinish)
                            .transition(.opacity)
                    } else {
                        AnalyzingScreen(model: model, onFinish: onFinish)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: model?.showsResult ?? false)
            .faWall()
            .toolbar(.hidden, for: .navigationBar)
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

// MARK: - The scanning transition

private struct AnalyzingScreen: View {
    @Bindable var model: CaptureViewModel
    let onFinish: () -> Void
    @State private var tips: [MealTip] = []
    @State private var tipIndex = 0

    private var isPhoto: Bool { !model.request.input.photos.isEmpty }
    private var done: Bool { model.status == .complete || model.status == .pricing }

    var body: some View {
        GeometryReader { geo in
            let hero = min(geo.size.width - 36, (geo.size.height * 0.46).rounded())
            ScrollView {
                VStack(spacing: 0) {
                    if isPhoto, let data = model.request.input.photos.first, let image = UIImage(data: data) {
                        PhotoScanCanvas(image: image, size: hero, done: done)
                    } else {
                        ReadingCanvas(width: hero, description: model.request.input.trimmedDescription ?? "", done: done)
                    }

                    VStack(spacing: 8) {
                        ColorCycleMark(size: 44)
                        Text(title).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.charcoal)
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(steps, id: \.label) { step in stepRow(step) }
                    }
                    .padding(.top, 10)

                    if case .stillWorking = model.phase {
                        stillWorking
                    } else if case .failed(let error) = model.phase {
                        FAErrorState(title: String(localized: "capture.failed.title", defaultValue: "Couldn't save this meal"), message: error.userMessage) { model.restart() }
                            .padding(.top, 16)
                    } else if let tip = tips.isEmpty ? nil : tips[tipIndex % tips.count] {
                        tipCard(tip).padding(.top, 16)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 52)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { onFinish() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.charcoal)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0x1A1A16, opacity: 0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
        }
        .onAppear {
            if tips.isEmpty {
                tips = MealTips.select(dayPart: .current(hour: Calendar.current.component(.hour, from: Date())))
                tipIndex = tips.isEmpty ? 0 : Int.random(in: 0..<tips.count)
            }
        }
    }

    private var title: String {
        isPhoto
            ? (done ? String(localized: "capture.reading", defaultValue: "Your plate, read.") : String(localized: "capture.scanning.plate", defaultValue: "Scanning your plate…"))
            : (done ? String(localized: "capture.reading.text.done", defaultValue: "Got it · your meal.") : String(localized: "capture.reading.text", defaultValue: "Reading your meal…"))
    }

    /// Each step is bound to a real pipeline state written by the server: the model IDENTIFIES, the
    /// resolver PRICES. Two steps, because the pipeline has two phases.
    private struct Step { let label: String; let activeAt: [MealLog.AnalysisStatus]; let doneAt: [MealLog.AnalysisStatus] }
    private var steps: [Step] {
        [
            Step(label: isPhoto ? String(localized: "capture.step.readingPlate", defaultValue: "Reading your plate") : String(localized: "capture.step.readingWords", defaultValue: "Reading your description"),
                 activeAt: [.queued, .identifying], doneAt: [.pricing, .complete]),
            Step(label: String(localized: "capture.step.nutrition", defaultValue: "Looking up nutrition"), activeAt: [.pricing], doneAt: [.complete]),
        ]
    }

    private enum StepState { case done, active, pending }
    private func state(_ step: Step) -> StepState {
        guard let status = model.status else { return step.label == steps[0].label ? .active : .pending }
        if step.doneAt.contains(status) { return .done }
        if step.activeAt.contains(status) { return .active }
        return .pending
    }

    private func stepRow(_ step: Step) -> some View {
        let s = state(step)
        return HStack(spacing: 9) {
            if s == .done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(FAColor.forestSoft)
            } else {
                Circle().fill(FAColor.forestSoft).frame(width: 5, height: 5)
            }
            Text(step.label).font(FATypography.sans(11.5, s == .active ? .semibold : .regular, relativeTo: .caption)).foregroundStyle(s == .done ? FAColor.stone : Color(hex: 0x6E6C62))
        }
        .opacity(s == .pending ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    /// The tip — kept, light: kicker + browse arrow, then the insight in serif.
    private func tipCard(_ tip: MealTip) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("◆ " + tip.kind.label.uppercased()).font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(FAColor.forestSoft)
                    Spacer()
                    Button { tipIndex = (tipIndex + 1) % max(1, tips.count) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                            .frame(width: 32, height: 32)
                            .background(FAColor.forestSoft.opacity(0.12), in: Circle())
                            .overlay { Circle().strokeBorder(FAColor.forestSoft.opacity(0.45), lineWidth: 1.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "capture.tip.next", defaultValue: "Next tip"))
                }
                Text(tip.text).font(FATypography.display(16, relativeTo: .body)).foregroundStyle(FAColor.charcoal).lineSpacing(5)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.4), lineWidth: 1) }
        .animation(.easeInOut(duration: 0.2), value: tipIndex)
    }

    private var stillWorking: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Label(String(localized: "capture.slow.title", defaultValue: "Still working on it"), systemImage: "clock")
                    .font(FATypography.headline).foregroundStyle(FAColor.ink)
                Text(String(localized: "capture.slow.message", defaultValue: "Your meal is saved. The analysis finishes in the background and shows up in your list."))
                    .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                FAButton(title: String(localized: "action.done", defaultValue: "Done")) { onFinish() }
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - The final meal page

private struct MealResultPage: View {
    @Bindable var model: CaptureViewModel
    let onFinish: () -> Void

    private var meal: MealLog? { model.latest }
    private var numbersReady: Bool { meal?.status == .complete && meal?.scores != nil }
    private var needsAttention: Bool { if case .attention = model.phase { return true } else { return false } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ConfirmHero(
                    photo: model.request.input.photos.first.flatMap(UIImage.init(data:)),
                    photoPath: nil,
                    meal: meal,
                    itemCount: meal?.items.count ?? 0,
                    numbersReady: numbersReady,
                    showItems: !(meal?.items.isEmpty ?? true)
                )
                if needsAttention, let meal {
                    attention(meal)
                } else if let meal, !meal.items.isEmpty {
                    MealItemRows(items: meal.items, numbersReady: numbersReady)
                    if numbersReady { FlagLegend(flags: FoodFlag.flags(in: meal.items)) }
                }
                if numbersReady, let scores = meal?.scores {
                    MealScoresRow(scores: scores)
                }
                FAButton(title: String(localized: "capture.goHome", defaultValue: "Go back to home")) { onFinish() }
                    .padding(.top, numbersReady ? 0 : 16)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The pipeline ran out of guesses → ask the person. Not an error surface.
    private func attention(_ meal: MealLog) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Label(
                    meal.status == .failed
                        ? String(localized: "capture.failed.short", defaultValue: "We couldn't read this meal")
                        : String(localized: "capture.needsInput.title", defaultValue: "Tell us a little more"),
                    systemImage: meal.status == .failed ? "exclamationmark.triangle" : "questionmark.circle"
                )
                .font(FATypography.headline).foregroundStyle(FAColor.ink)
                Text(String(localized: "capture.needsInput.message", defaultValue: "What was on the plate? A few words are enough — we'll read it again."))
                    .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                TextField(String(localized: "food.describe.placeholder", defaultValue: "e.g. grilled chicken, sweet potato, salad"), text: $model.retryDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .font(FATypography.body)
                    .padding(12)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1) }
                FAButton(title: String(localized: "action.tryAgain", defaultValue: "Try again")) { model.retry() }
                FAButton(title: String(localized: "capture.keep", defaultValue: "Keep it as is"), style: .tertiary) { onFinish() }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 16)
    }
}

// MARK: - Shared with the meal detail

/// The three food scores as rings with their verdicts (kept for the detail page's cards).
struct MealScoresCard: View {
    let scores: MealScores

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                Text(String(localized: "meal.scores.title", defaultValue: "How this meal reads"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink)
                HStack(alignment: .top, spacing: FASpacing.sm) {
                    ForEach(MealScoreKind.allCases) { kind in
                        ScoreRing(value: kind.value(in: scores), label: kind.title, color: kind.color, verdict: kind.verdict(kind.value(in: scores)))
                    }
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
    var compact = false

    var body: some View {
        if compact {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, value))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(FATypography.sans(9, .bold, relativeTo: .caption2))
                    .foregroundStyle(FAColor.ink)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
        } else {
            VStack(spacing: 6) {
                ScoreWheel(value: value, color: color, size: 64)
                Text(label).font(FATypography.label).foregroundStyle(FAColor.ink)
                Text(verdict).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value) out of 100. \(verdict)")
        }
    }
}

struct MealItemsCard: View {
    let items: [MealItem]

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                Text(String(localized: "meal.items.title", defaultValue: "On the plate"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        MealItemRow(item: item)
                        if i < items.count - 1 { Divider().overlay(FAColor.separator) }
                    }
                }
            }
        }
    }
}
