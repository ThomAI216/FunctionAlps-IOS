import SwiftUI

/// The moment after "Morning check-in done": the wall, the FunctionAlps mark, a serif title and one line, chosen by
/// `MorningRules` from the three "Feeling for the day" sliders — like the "Bon appétit" moment after a meal, with up to two
/// small things to add to the day ("+ A 10-minute walk outside"). Continue goes Home. With no action to offer the screen
/// goes on by itself after a couple of seconds; with actions it waits for the member.
struct MorningEndView: View {
    let rule: MorningRule
    let onAction: (MorningAction) -> Void
    let onContinue: () -> Void
    /// Screenshots only: stay on screen.
    var holds = false

    @State private var shown = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a screen with nothing to offer stays before going on by itself.
    static let autoContinueSeconds: Double = 2.5

    private var actions: [MorningAction] { rule.offered }

    var body: some View {
        ZStack {
            Color.clear.faWall()
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                FAMarkGlyph(color: FAColor.forestSoft, size: 54)
                    .scaleEffect(shown ? 1 : 0.6)
                    .rotationEffect(.degrees(shown || reduceMotion ? 0 : -25))
                    .accessibilityHidden(true)
                Text(rule.title)
                    .font(FATypography.display(34, relativeTo: .largeTitle))
                    .foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.center)
                    .offset(y: shown || reduceMotion ? 0 : 14)
                    .accessibilityAddTraits(.isHeader)
                Text(rule.line)
                    .font(FATypography.sans(16, relativeTo: .body))
                    .foregroundStyle(FAColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .offset(y: shown || reduceMotion ? 0 : 10)
                if !actions.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(actions, id: \.self) { action in
                            actionButton(action)
                        }
                    }
                    .padding(.top, 14)
                }
                Spacer(minLength: 0)
                continueButton
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .opacity(shown ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: shown)
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true }
            // Tap anywhere goes on only when there is nothing to choose.
            if holds || !actions.isEmpty { return }
            try? await Task.sleep(for: .seconds(Self.autoContinueSeconds))
            finish()
        }
    }

    private func actionButton(_ action: MorningAction) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).accessibilityHidden(true)
                Text(action.label).font(FATypography.sans(15, .semibold, relativeTo: .callout)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(FAColor.forest)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "morning.end.add", defaultValue: "Add: \(action.label)"))
    }

    private var continueButton: some View {
        Button { finish() } label: {
            Text(String(localized: "morning.end.continue", defaultValue: "Continue"))
                .font(FATypography.sans(14, .semibold, relativeTo: .callout))
                .foregroundStyle(FAColor.inkSecondary)
                .frame(minWidth: 120, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "morning.end.hint", defaultValue: "Goes back to Home"))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.25)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            onContinue()
        }
    }
}
