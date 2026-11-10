import SwiftUI

/// The night as Apple Health draws a sleep schedule: a 24-hour ring, midnight at the top, the moon on the
/// bedtime and the sun on the wake time — drag either round the ring. The arc between them is the night, its
/// length in the middle. Shown when nothing (no wearable, no Apple Health sleep) recorded the night; owner,
/// 2026-11-10: "the circle where we can select the night time and the wake time by sliding the two".
struct SleepDialView: View {
    /// Minutes past midnight.
    let bed: Int
    let wake: Int
    /// False until the member has touched a handle: the arc is drawn faded and nothing counts yet.
    let isSet: Bool
    let accent: Color
    let onChange: (_ bed: Int, _ wake: Int) -> Void

    private enum Handle { case bed, wake }
    @State private var dragging: Handle?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let ring = max(26, side * 0.15)
            let radius = side / 2 - ring / 2
            let center = CGPoint(x: side / 2, y: side / 2)
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.10), lineWidth: ring)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                ticks(center: center, radius: radius - ring / 2 - 5)
                ForEach(Array(SleepDialMath.arcSegments(bed: bed, wake: wake).enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.from, to: seg.to)
                        .stroke(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.65)], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: ring - 6, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                        .opacity(isSet ? 1 : 0.35)
                }
                centre
                    .frame(width: (radius - ring) * 1.6)
                    .position(center)
                    .animation(.easeInOut(duration: 0.15), value: dragging)
                knob(.bed, minutes: bed, systemImage: "moon.fill", center: center, radius: radius, size: ring - 2)
                knob(.wake, minutes: wake, systemImage: "sun.max.fill", center: center, radius: radius, size: ring - 2)
            }
            .frame(width: side, height: side)
            .coordinateSpace(name: "sleepDial")
        }
        .aspectRatio(1, contentMode: .fit)
        #if DEBUG
        .onAppear { if Showcase.screen == .checkinSleepDrag { dragging = .bed } }
        #endif
        .sensoryFeedback(.selection, trigger: bed)
        .sensoryFeedback(.selection, trigger: wake)
    }

    private var centre: some View {
        VStack(spacing: 2) {
            if let dragging {
                // Under the finger: the handle's own time, moving 5 minutes at a time (owner, 2026-11-10).
                Text(dragging == .bed ? String(localized: "sleep.bedtime", defaultValue: "Bedtime") : String(localized: "sleep.wake", defaultValue: "Wake"))
                    .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2)).foregroundStyle(accent)
                Text(Self.clock(dragging == .bed ? bed : wake))
                    .font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: dragging == .bed ? bed : wake)
                Text(SleepDialMath.durationLabel(SleepSpecials.windowMinutes(bed: Self.clock(bed), wake: Self.clock(wake)) ?? 0))
                    .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    .monospacedDigit()
            } else if isSet {
                Text(SleepDialMath.durationLabel(SleepSpecials.windowMinutes(bed: Self.clock(bed), wake: Self.clock(wake)) ?? 0))
                    .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                    .monospacedDigit()
                Text(String(localized: "sleep.dial.inBed", defaultValue: "in bed"))
                    .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
            } else {
                Text(String(localized: "sleep.dial.hint", defaultValue: "Slide the moon and the sun"))
                    .font(FATypography.sans(10.5, .medium, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true)
    }

    /// 24 hour marks, the four cardinal hours numbered (00 · 06 · 12 · 18).
    private func ticks(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            ForEach(0..<24, id: \.self) { h in
                let p = SleepDialMath.point(minutes: h * 60, center: center, radius: radius)
                if h % 6 == 0 {
                    Text(String(format: "%02d", h))
                        .font(FATypography.sans(9.5, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                        .position(SleepDialMath.point(minutes: h * 60, center: center, radius: radius - 4))
                } else {
                    Circle().fill(FAColor.inkMuted.opacity(0.6)).frame(width: 2, height: 2).position(p)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func knob(_ handle: Handle, minutes: Int, systemImage: String, center: CGPoint, radius: CGFloat, size: CGFloat) -> some View {
        let label = handle == .bed ? String(localized: "sleep.bedtime", defaultValue: "Bedtime") : String(localized: "sleep.wake", defaultValue: "Wake")
        let active = dragging == handle
        return ZStack {
            // The grab halo: the handle swells under the finger so it can be seen round the thumb.
            Circle().fill(accent.opacity(active ? 0.22 : 0)).scaleEffect(active ? 1.45 : 1)
            Circle().fill(Color.white)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(active ? 0.28 : 0.14), radius: active ? 6 : 2.5, y: 1)
        .scaleEffect(active ? 1.5 : 1)
        .zIndex(active ? 1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
        .position(SleepDialMath.point(minutes: minutes, center: center, radius: radius))
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("sleepDial"))
                .onChanged { g in
                    dragging = handle
                    let m = SleepDialMath.minutes(at: g.location, center: center)
                    if handle == .bed { if m != bed || !isSet { onChange(m, wake) } } else if m != wake || !isSet { onChange(bed, m) }
                }
                .onEnded { _ in dragging = nil }
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Self.clock(minutes))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? SleepDialMath.accessibilityStep : -SleepDialMath.accessibilityStep
            let m = SleepDialMath.normalized(minutes + delta)
            if handle == .bed { onChange(m, wake) } else { onChange(bed, m) }
        }
    }

    static func clock(_ minutes: Int) -> String {
        let m = SleepDialMath.normalized(minutes)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
