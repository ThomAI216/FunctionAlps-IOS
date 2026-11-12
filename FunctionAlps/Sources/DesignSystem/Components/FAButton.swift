import SwiftUI

struct FAButton: View {
    enum Style { case primary, secondary, tertiary, destructive }

    let title: String
    var style: Style = .primary
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    /// What the member sees, and what a finger gets.
    static let visualHeight: CGFloat = 34
    static let hitHeight: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack(spacing: FASpacing.sm) {
                if isLoading {
                    ProgressView().tint(foreground)
                }
                Text(title)
                    .font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
            }
            // Owner, 2026-11-12: smaller buttons. The drawn button is 34 pt tall; the tappable area stays 44 pt (HIG).
            .frame(maxWidth: .infinity, minHeight: Self.visualHeight)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous)
                        .strokeBorder(FAColor.brand, lineWidth: 1.25)
                }
            }
            .frame(minHeight: Self.hitHeight)
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }

    private var foreground: Color {
        switch style {
        case .primary: Color.white
        case .secondary, .tertiary: FAColor.brand
        case .destructive: FAColor.danger
        }
    }

    private var background: Color {
        switch style {
        case .primary: FAColor.brand
        case .secondary, .tertiary: .clear
        case .destructive: FAColor.danger.opacity(0.08)
        }
    }
}
