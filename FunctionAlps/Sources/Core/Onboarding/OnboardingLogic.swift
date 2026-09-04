import Foundation

/// The onboarding gate and the sign-up rules — pure, from the Expo `lib/onboarding/gate.ts`,
/// `login.tsx` and `lib/legal/age-gate.ts`.
enum OnboardingLogic {
    enum Status: Sendable, Equatable { case needsOnboarding, done }

    /// Done only when the stamp AND all five baseline fields exist (a Q1-only stamp is still "needs onboarding").
    static func status(_ profile: MemberProfile?) -> Status {
        guard let profile, profile.onboardingCompletedAt != nil, hasEnergyBaseline(profile) else { return .needsOnboarding }
        return .done
    }

    static func hasEnergyBaseline(_ p: MemberProfile) -> Bool {
        p.sex != nil && p.age != nil && p.heightCm != nil && p.weightKg != nil && p.activityLevel != nil
    }

    /// The five known → welcome skips straight to the energy screen.
    static func baselineIsKnown(_ p: MemberProfile?) -> Bool {
        guard let p, hasEnergyBaseline(p), p.sex != .other else { return false }
        return true
    }

    // MARK: Sign-up

    struct PasswordCheck: Sendable, Equatable {
        let length: Bool, upper: Bool, special: Bool
        var ok: Bool { length && upper && special }
    }

    static func checkPassword(_ pw: String) -> PasswordCheck {
        PasswordCheck(length: pw.count >= 8, upper: pw.contains { $0.isUppercase }, special: pw.contains { !$0.isLetter && !$0.isNumber })
    }

    static func isEmailShaped(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let at = t.lastIndex(of: "@"), at != t.startIndex, t.index(after: at) != t.endIndex else { return false }
        let domain = t[t.index(after: at)...]
        return !t.contains(" ") && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    // MARK: Age gate (18+, decided locally before any network call)

    static let minimumAge = 18
    static let maximumAge = 120

    enum AgeCheck: Sendable, Equatable { case ok(String), invalid, underAge }

    /// Day / month / year as typed → `YYYY-MM-DD`, rejecting roll-over dates (31/02) and ages outside 18…120.
    static func checkBirthDate(day: String, month: String, year: String, now: Date = Date(), calendar: Calendar = .current) -> AgeCheck {
        guard let d = Int(day.trimmingCharacters(in: .whitespaces)), let m = Int(month.trimmingCharacters(in: .whitespaces)), let y = Int(year.trimmingCharacters(in: .whitespaces)),
              (1...31).contains(d), (1...12).contains(m), y >= 1900 else { return .invalid }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return .invalid }
        let back = utc.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return .invalid }
        // Whole years elapsed as of the member's local calendar day (the Expo `ageOn`), compared in UTC
        // so the answer does not shift with the device's time zone.
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let todayUTC = utc.date(from: DateComponents(year: today.year, month: today.month, day: today.day)) else { return .invalid }
        let age = utc.dateComponents([.year], from: date, to: todayUTC).year ?? 0
        if age > maximumAge || date > todayUTC { return .invalid }
        if age < minimumAge { return .underAge }
        return .ok(String(format: "%04d-%02d-%02d", y, m, d))
    }
}

/// The eight mandatory screens — `lib/onboarding/steps.ts`.
enum OnboardingStep: Int, Sendable, Hashable, CaseIterable {
    case welcome = 1, baseline, activity, energy, nutrition, meals, checkins, ready
    static let total = 8
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// Progress lives on the device by design (closing the app on screen 4 must land on screen 4);
/// only completion is server-side. Keyed by auth user.
struct OnboardingDraft: Codable, Sendable, Equatable {
    var step = 1                 // high-water mark
    var sex: String? = nil
    var age = ""
    var height = ""
    var weight = ""
    var activity: String? = nil
    var knownBaseline = false    // welcome found the five on the profile

    private static func key(_ userId: String) -> String { "fa.onboarding.\(userId)" }

    static func load(userId: String, defaults: UserDefaults = .standard) -> OnboardingDraft {
        guard let data = defaults.data(forKey: key(userId)), let d = try? JSONDecoder().decode(OnboardingDraft.self, from: data) else { return OnboardingDraft() }
        return d
    }

    func save(userId: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(userId)) }
    }

    static func clear(userId: String, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key(userId)) }
}
