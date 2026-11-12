import CoreGraphics
import Foundation

/// Pure geometry behind the sleep dial: a 24-hour clock face, midnight at the top, time running clockwise
/// (Apple Health's sleep schedule). Kept out of the SwiftUI view so it can be tested and never touches the
/// main actor — the night's arithmetic once crashed inside a view (0a3a6d4).
enum SleepDialMath {
    static let dayMinutes = 1440
    /// Handles land on 5-minute steps.
    static let step = 5

    /// Minutes past midnight → angle in radians, 0 at the top, clockwise.
    static func angle(minutes: Int) -> Double {
        Double(normalized(minutes)) / Double(dayMinutes) * 2 * .pi
    }

    /// A touch at `point` on a dial centred on `center` → minutes past midnight, snapped to `step`.
    static func minutes(at point: CGPoint, center: CGPoint) -> Int {
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        // atan2 measured from the top, clockwise: swap the axes and flip y.
        var a = atan2(dx, -dy)
        if a < 0 { a += 2 * .pi }
        let raw = a / (2 * .pi) * Double(dayMinutes)
        return snap(Int(raw.rounded()))
    }

    /// The point on a circle of `radius` for `minutes`.
    static func point(minutes: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let a = angle(minutes: minutes)
        return CGPoint(x: center.x + radius * CGFloat(sin(a)), y: center.y - radius * CGFloat(cos(a)))
    }

    static func snap(_ minutes: Int) -> Int {
        normalized(Int((Double(minutes) / Double(step)).rounded()) * step)
    }

    static func normalized(_ minutes: Int) -> Int {
        ((minutes % dayMinutes) + dayMinutes) % dayMinutes
    }

    /// The arc from bed to wake as trim fractions of a circle that starts at the top. A night that crosses
    /// midnight wraps, so it comes back as two pieces.
    static func arcSegments(bed: Int, wake: Int) -> [(from: Double, to: Double)] {
        let b = Double(normalized(bed)) / Double(dayMinutes)
        let w = Double(normalized(wake)) / Double(dayMinutes)
        if b == w { return [] }
        return b < w ? [(b, w)] : [(b, 1), (0, w)]
    }

    /// "7 h 30" — the night's length for the dial's centre.
    static func durationLabel(_ minutes: Int) -> String {
        let m = max(0, minutes)
        return m % 60 == 0 ? "\(m / 60) h" : String(format: "%d h %02d", m / 60, m % 60)
    }

    /// One step on the VoiceOver adjustable action.
    static let accessibilityStep = 15
}
