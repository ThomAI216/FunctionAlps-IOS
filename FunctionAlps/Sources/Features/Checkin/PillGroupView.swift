import SwiftUI

/// A titled row of toggle pills. Coloured AT REST (hue at ~35%), filled once chosen.
struct PillGroupView: View {
    let title: String?
    let options: [PillOption]
    let isOn: (String) -> Bool
    let onToggle: (String) -> Void
    /// Fallback hue when a pill has no catalog pillar.
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
            }
            FlowLayout(spacing: 7) {
                ForEach(options) { option in
                    PillButton(label: option.label, hue: hue(for: option.key), on: isOn(option.key)) { onToggle(option.key) }
                }
            }
        }
        .padding(.top, 12)
    }

    private func hue(for key: String) -> Color {
        if let pillar = PillCatalog.pill(key)?.pillar { return Color(hex: pillar.hueHex) }
        return accent
    }
}

struct PillButton: View {
    let label: String
    let hue: Color
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(on ? FATypography.label : FATypography.caption)
                .foregroundStyle(hue)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(on ? hue.opacity(0.13) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? hue : hue.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(on ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: on)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Single-choice pills (time to fall asleep, wakings). Tapping the active one clears it.
struct PillSelectView: View {
    let title: String
    let options: [PillOption]
    @Binding var value: String?
    let accent: Color

    var body: some View {
        PillGroupView(title: title, options: options, isOn: { value == $0 }, onToggle: { key in
            value = value == key ? nil : key
        }, accent: accent)
    }
}
