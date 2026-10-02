import Foundation

/// The generic two-phase repetition: NEUTRAL → ACTIVE → NEUTRAL = one rep, with the four anti-jitter
/// guards every detector needs:
/// - hysteresis: entering ACTIVE and leaving it use different thresholds, so a signal hovering around
///   one value cannot flip the state;
/// - consecutive-frame confirmation: a change of phase needs `confirmFrames` frames in a row;
/// - plausible cadence: reps closer than `minimumRepInterval`, or an ACTIVE phase longer than
///   `maximumActiveDuration`, do not count;
/// - tracking loss: a gap up to `freezeWindow` keeps the phase; a longer one forgets it, and a phase
///   re-established after that (or at the start) never counts on its own — a rep needs the whole cycle
///   to be seen.
struct TwoPhaseRepCounter: Equatable, Sendable {
    enum Phase: String, Sendable { case unknown, neutral, active }

    struct Config: Equatable, Sendable {
        /// The signal must pass this to become ACTIVE…
        var enterActive: Double
        /// …and come back past this to return to NEUTRAL.
        var exitActive: Double
        /// True when ACTIVE means a HIGH signal (arms apart); false when it means a low one (hips dropped).
        var activeIsHigh = true
        var confirmFrames = 3
        var minimumRepInterval: TimeInterval = 0.35
        var maximumActiveDuration: TimeInterval = 8
        var freezeWindow: TimeInterval = 0.6
    }

    let config: Config
    private(set) var phase: Phase = .unknown
    private(set) var reps = 0
    private var candidate: Phase?
    private var candidateFrames = 0
    private var activeSince: TimeInterval?
    private var lastRepAt: TimeInterval?
    private var lastReliableAt: TimeInterval?

    init(config: Config) {
        self.config = config
    }

    /// Feeds one reliable sample. Returns true when this sample completed a repetition.
    mutating func process(_ signal: Double, at time: TimeInterval) -> Bool {
        if let last = lastReliableAt, time - last > config.freezeWindow {
            // Unseen for too long: whatever happened meanwhile is unknown.
            phase = .unknown
            activeSince = nil
            clearCandidate()
        }
        lastReliableAt = time

        let zone = self.zone(of: signal)
        let target: Phase? = switch phase {
        case .unknown: zone
        case .neutral: zone == .active ? .active : nil
        case .active: zone == .neutral ? .neutral : nil
        }
        guard let target else {
            clearCandidate()
            return false
        }
        if candidate == target {
            candidateFrames += 1
        } else {
            candidate = target
            candidateFrames = 1
        }
        guard candidateFrames >= config.confirmFrames else { return false }

        let from = phase
        phase = target
        clearCandidate()
        switch (from, target) {
        case (.neutral, .active):
            activeSince = time
            return false
        case (.active, .neutral):
            defer { activeSince = nil }
            // Nil when ACTIVE was found already in progress (start, reacquisition): half a rep.
            guard let since = activeSince, time - since <= config.maximumActiveDuration else { return false }
            if let lastRepAt, time - lastRepAt < config.minimumRepInterval { return false }
            reps += 1
            lastRepAt = time
            return true
        default:
            // From .unknown: the phase is established, nothing is counted.
            return false
        }
    }

    /// A frame without a usable signal: it breaks any run of confirming frames.
    mutating func markUnreliable() {
        clearCandidate()
    }

    mutating func reset() {
        self = TwoPhaseRepCounter(config: config)
    }

    /// Which side of the hysteresis band the signal is on; nil inside the band.
    private func zone(of signal: Double) -> Phase? {
        if config.activeIsHigh {
            if signal > config.enterActive { return .active }
            if signal < config.exitActive { return .neutral }
        } else {
            if signal < config.enterActive { return .active }
            if signal > config.exitActive { return .neutral }
        }
        return nil
    }

    private mutating func clearCandidate() {
        candidate = nil
        candidateFrames = 0
    }
}
