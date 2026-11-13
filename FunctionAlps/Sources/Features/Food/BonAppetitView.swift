import SwiftUI

/// The moment between a validated meal and Home: the wall, the FunctionAlps mark, one phrase from
/// `BonAppetit.phrases` in the middle of the screen — then home on its own after a couple of seconds, or at a tap.
struct BonAppetitView: View {
    let phrase: BonAppetit.Phrase
    let onDone: () -> Void
    /// Screenshots only: stay on screen instead of going home.
    var holds = false

    @State private var shown = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.clear.faWall()
            VStack(spacing: 16) {
                FAMarkGlyph(color: FAColor.forestSoft, size: 54)
                    .scaleEffect(shown ? 1 : 0.6)
                    .rotationEffect(.degrees(shown || reduceMotion ? 0 : -25))
                Text(phrase.title)
                    .font(FATypography.display(38, relativeTo: .largeTitle))
                    .foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.center)
                    .offset(y: shown || reduceMotion ? 0 : 14)
                Text(phrase.line)
                    .font(FATypography.sans(16, relativeTo: .body))
                    .foregroundStyle(FAColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .offset(y: shown || reduceMotion ? 0 : 10)
            }
            .padding(.horizontal, 32)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "bonappetit.hint", defaultValue: "Goes back to Home"))
        .sensoryFeedback(.success, trigger: shown)
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true }
            if holds { return }
            try? await Task.sleep(for: .seconds(BonAppetit.seconds))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.25)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            onDone()
        }
    }
}
