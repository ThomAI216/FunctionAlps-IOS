import Foundation

/// The 1€ filter (Casiez, Roussel & Vogel, CHI 2012): a low-pass filter whose cutoff rises with speed.
/// Nearly still → smooths hard (kills landmark jitter); moving fast → follows closely (little lag).
/// Own, tested implementation — reference: github.com/casiez/OneEuroFilter.
struct OneEuroFilter: Sendable {
    /// Cutoff (Hz) when still. Lower = smoother at rest.
    var minCutoff: Double
    /// How fast the cutoff grows with speed. Higher = less lag on fast moves.
    var beta: Double
    /// Cutoff (Hz) for the speed estimate itself.
    var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: TimeInterval?

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// The filtered value for `value` sampled at `time` (seconds). The first sample passes through;
    /// a sample that does not move time forward returns the last output unchanged.
    mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let previous = lastValue, let previousTime = lastTime else {
            lastValue = value
            lastTime = time
            return value
        }
        let dt = time - previousTime
        guard dt > 0 else { return previous }

        let rawDerivative = (value - previous) / dt
        let ad = Self.smoothing(cutoff: derivativeCutoff, dt: dt)
        let derivative = ad * rawDerivative + (1 - ad) * lastDerivative
        let cutoff = minCutoff + beta * abs(derivative)
        let a = Self.smoothing(cutoff: cutoff, dt: dt)
        let filtered = a * value + (1 - a) * previous

        lastValue = filtered
        lastDerivative = derivative
        lastTime = time
        return filtered
    }

    mutating func reset() {
        lastValue = nil
        lastDerivative = 0
        lastTime = nil
    }

    /// Exponential-smoothing factor for a first-order low-pass at `cutoff` Hz over `dt` seconds.
    static func smoothing(cutoff: Double, dt: TimeInterval) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// How hard an exercise smooths its landmarks. Slow movements take more; fast bounces (pogo jumps) take
/// less, because heavy smoothing erases a small, quick signal.
struct SmoothingProfile: Equatable, Sendable {
    var minCutoff: Double
    var beta: Double
    var derivativeCutoff: Double = 1

    /// Arm openers, raises, squats. Coordinates are 0…1, so beta is far larger than the paper's pixel values.
    static let slow = SmoothingProfile(minCutoff: 1.5, beta: 2.0)
    /// Jumps and other quick, small movements.
    static let fast = SmoothingProfile(minCutoff: 3.0, beta: 6.0)
}
