import Foundation

/// Pure scoring + roll-up for the check-in, ported line-for-line from the Expo app's
/// `functional-engine.ts`, `moments.ts` and `moment-persistence.ts` so a moment saved
/// from the phone and one saved from the web agree to the point. No I/O, no Date().
enum CheckinEngine {
    private static func clamp(_ v: Double) -> Double { max(0, min(100, v)) }
    private static func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

    // MARK: Dimension scores

    static func availableCaseMean(_ vals: [Double?]) -> Int? {
        let present = vals.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return jsRound(present.reduce(0, +) / Double(present.count))
    }

    /// Energy = mean(body, mind) modulated by stability (±15%, neutral at 50).
    static func energyOverall(body: Double?, mind: Double?, stability: Double?) -> Int? {
        guard let base = availableCaseMean([body, mind]) else { return nil }
        let factor = stability.map { 0.85 + 0.3 * ($0 / 100) } ?? 1
        return jsRound(clamp(Double(base) * factor))
    }

    static let latencyScore: [String: Int] = ["lt_15": 100, "15_30": 80, "30_60": 50, "gt_60": 20]
    static let wakeScore: [String: Int] = ["0": 100, "1_2": 70, "3plus": 35]

    /// 420–540 min (7–9 h) = 100, tapering outside.
    static func durationScore(_ min: Int?) -> Int? {
        guard let min else { return nil }
        if min >= 420 && min <= 540 { return 100 }
        if min < 420 { return jsRound(clamp(100 - Double(420 - min) / 3)) }
        return jsRound(clamp(100 - Double(min - 540) / 6))
    }

    static func sleepOverall(durationMin: Int?, latency: String?, wakeCount: String?, refreshed: Double?) -> Int? {
        let parts: [(Double?, Double)] = [
            (refreshed, 0.35),
            (durationScore(durationMin).map(Double.init), 0.3),
            (latency.flatMap { latencyScore[$0] }.map(Double.init), 0.2),
            (wakeCount.flatMap { wakeScore[$0] }.map(Double.init), 0.15),
        ]
        let present = parts.compactMap { v, w in v.map { ($0, w) } }
        guard !present.isEmpty else { return nil }
        let wSum = present.reduce(0) { $0 + $1.1 }
        return jsRound(present.reduce(0) { $0 + $1.0 * $1.1 } / wSum)
    }

    static func dimensionOverall(_ key: DimKey, _ a: DimAnswers) -> Int? {
        switch key {
        case .energy:
            return energyOverall(body: a.sliders["body"], mind: a.sliders["mind"], stability: a.sliders["stability"])
        case .sleep:
            return sleepOverall(durationMin: a.specials.durationMin, latency: a.specials.latency, wakeCount: a.specials.wakeCount, refreshed: a.sliders["refreshed"])
        case .mood:
            return a.sliders["mood"].map(jsRound)
        case .stress:
            return a.sliders["calm"].map(jsRound) // stress = calmness
        }
    }

    /// 0–100 → the legacy 1–5 mountain scale.
    static func toLegacy(_ v: Int?) -> Int? {
        guard let v else { return nil }
        return max(1, min(5, jsRound(Double(v) / 20)))
    }

    static func selectPills(_ spec: DimensionSpec, _ a: DimAnswers) -> [PillModule] {
        spec.pills.filter { $0.when(a) }
    }

    // MARK: Answers ⇄ moment

    private static func int(_ v: Double?) -> Int? { v.map(jsRound) }

    /// Every non-empty pill group across the answered dimensions (catalog-owned groups skipped).
    static func collectAnswerPills(_ answers: FunctionalAnswers) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for a in answers.values {
            for (group, keys) in a.pills where !PillCatalog.ownedGroups.contains(group) && !keys.isEmpty {
                out[group] = keys
            }
        }
        return out
    }

    static func momentFromAnswers(slot: MomentSlot, answers: FunctionalAnswers, catalogPills: [String: [String]], note: String?, submittedAt: Date) -> CheckinMoment {
        let energy = answers[.energy] ?? .empty
        let mood = answers[.mood] ?? .empty
        let stress = answers[.stress] ?? .empty
        let sleep = answers[.sleep] ?? .empty

        var pills = collectAnswerPills(answers)
        for (group, keys) in catalogPills {
            if keys.isEmpty { pills.removeValue(forKey: group) } else { pills[group] = keys }
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CheckinMoment(
            slot: slot,
            submittedAt: submittedAt,
            energyBody: int(energy.sliders["body"]),
            energyMind: int(energy.sliders["mind"]),
            energyStability: int(energy.sliders["stability"]),
            energyOverall: energyOverall(body: energy.sliders["body"], mind: energy.sliders["mind"], stability: energy.sliders["stability"]),
            moodScore: dimensionOverall(.mood, mood),
            stressScore: dimensionOverall(.stress, stress), // CALMNESS — never inverted
            sleepOverall: dimensionOverall(.sleep, sleep),
            sleepRefreshed: int(sleep.sliders["refreshed"]),
            sleepDurationMin: sleep.specials.durationMin,
            sleepLatencyBand: sleep.specials.latency,
            sleepWakeCount: sleep.specials.wakeCount,
            pills: pills,
            note: (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        )
    }

    /// Guards against stamping a phantom moment when someone taps Save without answering.
    static func momentHasContent(_ m: CheckinMoment) -> Bool {
        let markers: [Int?] = [m.energyBody, m.energyMind, m.energyStability, m.energyOverall, m.moodScore, m.stressScore, m.sleepOverall, m.sleepRefreshed, m.sleepDurationMin]
        if markers.contains(where: { $0 != nil }) { return true }
        if m.sleepLatencyBand != nil || m.sleepWakeCount != nil { return true }
        if m.note != nil { return true }
        return m.pills.values.contains { !$0.isEmpty }
    }

    /// Which dimension owns a pill group (catalog groups own themselves).
    static func dimension(forGroup group: String) -> DimKey? {
        for spec in FunctionalSchema.dimensions where !PillCatalog.ownedGroups.contains(group) {
            if spec.pills.contains(where: { $0.key == group }) { return spec.key }
        }
        return nil
    }

    /// Rebuild the editable answers from a saved moment (edit-mode prefill).
    static func answersFromMoment(_ moment: CheckinMoment?) -> FunctionalAnswers {
        var answers = FunctionalAnswers.blank
        guard let moment else { return answers }
        var energy = DimAnswers.empty
        if let v = moment.energyBody { energy.sliders["body"] = Double(v) }
        if let v = moment.energyMind { energy.sliders["mind"] = Double(v) }
        if let v = moment.energyStability { energy.sliders["stability"] = Double(v) }
        answers[.energy] = energy
        var mood = DimAnswers.empty
        if let v = moment.moodScore { mood.sliders["mood"] = Double(v) }
        answers[.mood] = mood
        var stress = DimAnswers.empty
        if let v = moment.stressScore { stress.sliders["calm"] = Double(v) }
        answers[.stress] = stress
        var sleep = DimAnswers.empty
        if let v = moment.sleepRefreshed { sleep.sliders["refreshed"] = Double(v) }
        sleep.specials = SleepSpecials(durationMin: moment.sleepDurationMin, latency: moment.sleepLatencyBand, wakeCount: moment.sleepWakeCount)
        answers[.sleep] = sleep
        for (group, keys) in moment.pills where !keys.isEmpty {
            guard let dim = dimension(forGroup: group) else { continue }
            answers[dim]?.pills[group] = keys
        }
        return answers
    }

    static func catalogPills(from moment: CheckinMoment?) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for group in PillGroup.allCases {
            if let keys = moment?.pills[group.rawValue], !keys.isEmpty { out[group.rawValue] = keys }
        }
        return out
    }

    /// Did a saved morning moment answer anything from the opt-in "more" tier?
    static func hasMoreTierAnswers(_ moment: CheckinMoment?) -> Bool {
        guard let moment else { return false }
        let markers: [Int?] = [moment.energyBody, moment.energyMind, moment.energyStability, moment.energyOverall, moment.moodScore, moment.stressScore]
        if markers.contains(where: { $0 != nil }) { return true }
        return ["fuelled", "drained"].contains { !(moment.pills[$0] ?? []).isEmpty }
    }

    // MARK: Day roll-up

    static func inSlotOrder(_ moments: [CheckinMoment]) -> [CheckinMoment] {
        moments.sorted { $0.slot.rank < $1.slot.rank }
    }

    static func moment(for slot: MomentSlot, in moments: [CheckinMoment]) -> CheckinMoment? {
        moments.first { $0.slot == slot }
    }

    static func slotIsDone(_ moments: [CheckinMoment], _ slot: MomentSlot) -> Bool {
        moment(for: slot, in: moments) != nil
    }

    /// MEDIAN of the non-null values, rounded — robust to one rough hour.
    static func median(_ vals: [Int?]) -> Int? {
        let present = vals.compactMap { $0 }.sorted()
        guard !present.isEmpty else { return nil }
        let mid = present.count / 2
        let raw: Double = present.count % 2 == 1 ? Double(present[mid]) : Double(present[mid - 1] + present[mid]) / 2
        return jsRound(raw)
    }

    static func mean(_ vals: [Int?]) -> Int? {
        let present = vals.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return jsRound(Double(present.reduce(0, +)) / Double(present.count))
    }

    /// Markers = median across the moments; ALL sleep fields come from ONE moment — the morning
    /// whenever it exists, else the earliest moment that carries sleep.
    static func summarizeDay(_ moments: [CheckinMoment]) -> DaySummary {
        guard !moments.isEmpty else { return DaySummary() }
        let ordered = inSlotOrder(moments)
        let sleepSource = moment(for: .morning, in: ordered) ?? ordered.first { $0.hasSleep }
        return DaySummary(
            energyOverall: median(ordered.map(\.energyOverall)),
            energyBody: median(ordered.map(\.energyBody)),
            energyMind: median(ordered.map(\.energyMind)),
            moodScore: median(ordered.map(\.moodScore)),
            stressScore: median(ordered.map(\.stressScore)),
            sleepOverall: sleepSource?.sleepOverall,
            sleepRefreshed: sleepSource?.sleepRefreshed,
            sleepDurationMin: sleepSource?.sleepDurationMin,
            sleepLatencyBand: sleepSource?.sleepLatencyBand,
            sleepWakeCount: sleepSource?.sleepWakeCount,
            momentCount: ordered.count
        )
    }

    /// The `patient_daily_checkins` patch: felt prefill (rule 1), `computed ?? existing` for every
    /// other column (rule 2), sleep columns only when the day has a sleep answer (rule 3),
    /// legacy 1–5 columns (rule 4), `functional_detail` untouched (rule 5).
    static func daySummaryPatch(_ moments: [CheckinMoment], existing: DailyCheckinCarry?, completedAt: Date) -> DaySummaryPatch {
        let s = summarizeDay(moments)
        let prev = existing ?? DailyCheckinCarry()
        let stability = mean(moments.map(\.energyStability))
        var patch = DaySummaryPatch(
            energyBody: s.energyBody ?? prev.energyBody,
            energyMind: s.energyMind ?? prev.energyMind,
            energyStability: stability ?? prev.energyStability,
            energyOverall: s.energyOverall ?? prev.energyOverall,
            moodScore: s.moodScore ?? prev.moodScore,
            stressScore: s.stressScore ?? prev.stressScore,
            legacyEnergy: toLegacy(s.energyOverall) ?? prev.energy,
            legacyMood: toLegacy(s.moodScore) ?? prev.mood,
            legacyStress: toLegacy(s.stressScore) ?? prev.stress,
            recovery: prev.recovery,
            soreness: prev.soreness,
            recentLoad: prev.recentLoad,
            recentMentalLoad: prev.recentMentalLoad,
            completedAt: completedAt
        )
        if s.hasSleep {
            patch.sleep = DaySummaryPatch.Sleep(
                sleepOverall: s.sleepOverall ?? prev.sleepOverall,
                sleepRefreshed: s.sleepRefreshed ?? prev.sleepRefreshed,
                sleepDurationMin: s.sleepDurationMin ?? prev.sleepDurationMin,
                sleepLatencyBand: s.sleepLatencyBand ?? prev.sleepLatencyBand,
                sleepWakeCount: s.sleepWakeCount ?? prev.sleepWakeCount,
                legacySleep: toLegacy(s.sleepOverall) ?? prev.sleep
            )
        }
        return patch
    }

    /// The per-dimension `nb_checkin_events` rows for ONE moment save (appended once per save).
    static func momentEvents(_ m: CheckinMoment) -> [CheckinEvent] {
        let overalls: [(String, Int?)] = [("energy", m.energyOverall), ("mood", m.moodScore), ("sleep", m.sleepOverall), ("stress", m.stressScore)]
        return overalls.compactMap { dimension, value in value.map { CheckinEvent(dimension: dimension, value: $0, ts: m.submittedAt) } }
    }

    // MARK: Presentation helpers (pure)

    struct MomentRead: Sendable, Equatable, Identifiable {
        let slot: MomentSlot
        let summary: String
        var id: MomentSlot { slot }
    }

    /// "E 72 · M 60" per checked-in moment, in day order; "Checked in" when neither read exists.
    static func momentReads(_ moments: [CheckinMoment]) -> [MomentRead] {
        inSlotOrder(moments).map { m in
            var parts: [String] = []
            if let e = m.energyOverall { parts.append("E \(e)") }
            if let d = m.moodScore { parts.append("M \(d)") }
            return MomentRead(slot: m.slot, summary: parts.isEmpty ? String(localized: "checkin.checkedIn", defaultValue: "Checked in") : parts.joined(separator: " · "))
        }
    }

    /// The 5-step state ramp index (0 = green … 4 = red) for a 0–100 value, higher = better.
    static func stateRampIndex(_ v: Double) -> Int {
        4 - jsRound(clamp(v) / 100 * 4)
    }
}
