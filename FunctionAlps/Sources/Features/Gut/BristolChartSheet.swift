import SwiftUI

/// The Bristol chart, opened over the stool card: the seven types as the clinical drawings show them. Tap the
/// row that looks like yours and it becomes the answer (owner, 2026-11-10: "make the picture interactive · if
/// they click on 1 to 7, it will get the answer and the number").
struct BristolChartSheet: View {
    /// The current answer (1–7), nil when none.
    let selected: Int?
    let accent: Color
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Int?

    private var current: Int? { picked ?? selected }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "gut.bristol.chart.intro", defaultValue: "Tap the type that looks most like yours."))
                        .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    chart
                    if let current {
                        Text(String(localized: "gut.bristol.chart.picked", defaultValue: "Your answer · \(GutSchema.bristolLabel(current))"))
                            .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(accent)
                            .transition(.opacity)
                    }
                }
                .padding(FASpacing.md)
            }
            .background(FAColor.warm.ignoresSafeArea())
            .navigationTitle(String(localized: "gut.bristol.chart.title", defaultValue: "Bristol stool chart"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) { dismiss() }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
    }

    /// The image with one invisible button laid over each row — tappable, and read out by VoiceOver.
    private var chart: some View {
        Group {
            if let image = FAMedia.image(BristolChart.imageName, ext: BristolChart.imageExt) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(BristolChart.aspectRatio, contentMode: .fit)
                    .accessibilityHidden(true)
                    .overlay {
                        GeometryReader { geo in
                            ForEach(Array(BristolChart.types), id: \.self) { type in
                                if let r = BristolChart.rowRange(type) {
                                    rowButton(type, width: geo.size.width, top: geo.size.height * r.lowerBound, height: geo.size.height * (r.upperBound - r.lowerBound))
                                }
                            }
                        }
                    }
            } else {
                // The image is in the bundle; this only shows if it ever goes missing — the seven names still answer.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(BristolChart.types), id: \.self) { type in
                        Button(GutSchema.bristolLabel(type)) { pick(type) }
                            .font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1))
    }

    private func rowButton(_ type: Int, width: CGFloat, top: CGFloat, height: CGFloat) -> some View {
        let on = current == type
        return Button { pick(type) } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? accent.opacity(0.12) : Color.white.opacity(0.001))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(on ? accent : .clear, lineWidth: 2.5)
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white, accent)
                        .padding(6)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: width / 2, y: top + height / 2)
        .accessibilityLabel(GutSchema.bristolDescription(type))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func pick(_ type: Int) {
        withAnimation(.easeInOut(duration: 0.15)) { picked = type }
        onPick(type)
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            dismiss()
        }
    }
}
