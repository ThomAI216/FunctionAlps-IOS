import SwiftUI

struct FAButton: View {
    enum Style { case primary, secondary, tertiary, destructive }

    let title: String
    var style: Style = .primary
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FASpacing.sm) {
                if isLoading {
                    ProgressView().tint(foreground)
                }
                Text(title)
                    .font(FATypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous)
                        .strokeBorder(FAColor.brand, lineWidth: 1.5)
                }
            }
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
