import SwiftUI

/// The small check of an action (owner, 2026-11-12: "smaller checks"): drawn about 28 pt, with a 44 pt tappable area
/// around it. Done is the filled mark, never colour alone (rule 10); the accessibility label names the action.
struct FACheck: View {
    let done: Bool
    /// The action's title, for VoiceOver.
    let title: String
    let action: () -> Void

    /// The mark as drawn.
    static let visualSize: CGFloat = 28
    /// The hit area (HIG minimum).
    static let hitSize: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: Self.visualSize - 4, weight: .regular))
                .foregroundStyle(done ? FAColor.accent : FAColor.inkMuted)
                .frame(width: Self.visualSize, height: Self.visualSize)
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done
            ? String(localized: "plan.a11y.done", defaultValue: "Done: \(title)")
            : String(localized: "plan.a11y.markDone", defaultValue: "Mark as done: \(title)"))
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}
