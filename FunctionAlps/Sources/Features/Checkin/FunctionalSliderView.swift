import SwiftUI

/// Continuous 0–100 slider, higher = better: red (left) → green (right) veil, a 5-word state
/// translation above the bar, the score on the right. Untouched = grey thumb parked at centre.
struct FunctionalSliderView: View {
    let spec: SliderSpec
    @Binding var value: Double?
    @State private var dragging = false

    static let ramp: [Color] = [Color(hex: 0x4A8A5C), Color(hex: 0x4F86C6), Color(hex: 0x8E7CC3), Color(hex: 0xE2BE3A), Color(hex: 0xDB5A4B)]
    private static let grey = Color(hex: 0x9CA3AF)

    private var color: Color {
        guard let value else { return Self.grey }
        return Self.ramp[CheckinEngine.stateRampIndex(value)]
    }
    private var word: String? {
        guard let value else { return nil }
        let idx = Int((min(100, max(0, value)) / 100 * 4).rounded())
        return spec.words.indices.contains(idx) ? spec.words[idx] : nil
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(spec.label).font(FATypography.callout).foregroundStyle(FAColor.ink)
                Spacer()
                Text(value.map { "\(Int($0))" } ?? "·")
                    .font(FATypography.headline)
                    .foregroundStyle(value == nil ? FAColor.inkMuted : color)
                    .monospacedDigit()
            }
            Text(word ?? "·")
                .font(FATypography.label)
                .foregroundStyle(word == nil ? FAColor.inkMuted : color)
            GeometryReader { geo in
                let width = geo.size.width
                let pos = CGFloat(min(100, max(0, value ?? 50))) / 100 * width
                let trackH: CGFloat = dragging ? 13 : 9
                let thumb: CGFloat = dragging ? 33 : 24
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: Self.ramp.reversed().map { $0.opacity(0.33) }, startPoint: .leading, endPoint: .trailing))
                        .frame(height: trackH)
                    if value != nil {
                        Capsule().fill(color).frame(width: max(trackH, pos), height: trackH)
                    }
                    ZStack {
                        Circle().fill(FAColor.cream)
                        Circle().strokeBorder(color, lineWidth: 1.5)
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: thumb * 0.42))
                            .foregroundStyle(color)
                            .opacity(value == nil ? 0.32 : 1)
                    }
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .offset(x: pos - thumb / 2)
                }
                .frame(height: 38)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            let fraction = Double(g.location.x) / Double(width)
                            let next: Double = min(100, max(0, fraction * 100))
                            value = next.rounded()
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: 38)
            .animation(.easeOut(duration: 0.12), value: dragging)
            HStack {
                Text(spec.lowLabel).font(FATypography.caption).foregroundStyle(Self.ramp[4])
                Spacer()
                Text(spec.highLabel).font(FATypography.caption).foregroundStyle(Self.ramp[0])
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.label)
        .accessibilityValue(value.map { "\(Int($0)) \(word ?? "")" } ?? String(localized: "marker.none", defaultValue: "not recorded"))
        .accessibilityAdjustableAction { direction in
            let current = value ?? 50
            value = direction == .increment ? min(100, current + 5) : max(0, current - 5)
        }
    }
}
