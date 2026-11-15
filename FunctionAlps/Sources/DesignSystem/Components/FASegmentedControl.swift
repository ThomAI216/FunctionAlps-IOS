import SwiftUI

/// Equal-width segments in a soft pill with a white selected thumb — the `TrendWindowPicker` look, for any list of
/// options (Food: Logging · Plan · Groceries; the recipe card: Preparation | Cooking).
struct FASegmentedControl<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let on = option == selection
                Button { onSelect(option) } label: {
                    Text(title(option))
                        .font(FATypography.sans(13, on ? .bold : .medium, relativeTo: .footnote))
                        .foregroundStyle(on ? FAColor.ink : FAColor.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
