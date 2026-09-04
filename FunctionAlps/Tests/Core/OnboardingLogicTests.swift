import Foundation
import Testing
@testable import FunctionAlps

@Suite("OnboardingLogic")
struct OnboardingLogicTests {
    private func profile(stamped: Bool, sex: MemberProfile.Sex? = .female, age: Int? = 40, height: Double? = 170, weight: Double? = 65, activity: String? = "sedentary") -> MemberProfile {
        MemberProfile(sex: sex, age: age, heightCm: height, weightKg: weight, activityLevel: activity, healthGoals: [], currentComplaints: [], dietaryPattern: nil,
                      targetCalories: nil, targetProteinG: nil, targetCarbsG: nil, targetFatG: nil, goalMode: nil,
                      onboardingCompletedAt: stamped ? Date() : nil, locale: nil)
    }

    // The gate rule is BOTH halves: the stamp AND the five baseline inputs.

    @Test func noProfileNeedsOnboarding() {
        #expect(OnboardingLogic.status(nil) == .needsOnboarding)
    }

    @Test func stampWithoutBaselineNeedsOnboarding() {
        // A Q1-only stamp (sex + age, no height/weight/activity) must not sail past the gate.
        #expect(OnboardingLogic.status(profile(stamped: true, height: nil)) == .needsOnboarding)
        #expect(OnboardingLogic.status(profile(stamped: true, activity: nil)) == .needsOnboarding)
    }

    @Test func baselineWithoutStampNeedsOnboarding() {
        // Screen 3 writes the baseline; a member who quit on screen 4 still has five screens to see.
        #expect(OnboardingLogic.status(profile(stamped: false)) == .needsOnboarding)
    }

    @Test func stampAndBaselineIsDone() {
        #expect(OnboardingLogic.status(profile(stamped: true)) == .done)
    }

    @Test func knownBaselineSkipsTheForm() {
        #expect(OnboardingLogic.baselineIsKnown(profile(stamped: false)))
        #expect(!OnboardingLogic.baselineIsKnown(profile(stamped: false, weight: nil)))
        // "other" cannot feed Harris-Benedict, so it is asked again.
        #expect(!OnboardingLogic.baselineIsKnown(profile(stamped: false, sex: .other)))
    }

    // Sign-up rules

    @Test func passwordRule() {
        #expect(OnboardingLogic.checkPassword("Abcdef1!").ok)
        #expect(!OnboardingLogic.checkPassword("abcdef1!").upper)
        #expect(!OnboardingLogic.checkPassword("Abcdefgh").special)
        #expect(!OnboardingLogic.checkPassword("Ab1!").length)
        #expect(OnboardingLogic.checkPassword("Été-2026").ok)   // accented capital counts as uppercase
    }

    @Test func emailShape() {
        #expect(OnboardingLogic.isEmailShaped("marie@email.com"))
        #expect(OnboardingLogic.isEmailShaped("  marie.d@sub.example.ch "))
        #expect(!OnboardingLogic.isEmailShaped("marie"))
        #expect(!OnboardingLogic.isEmailShaped("marie@"))
        #expect(!OnboardingLogic.isEmailShaped("@email.com"))
        #expect(!OnboardingLogic.isEmailShaped("marie@email"))
        #expect(!OnboardingLogic.isEmailShaped("ma rie@email.com"))
    }

    // Age gate — decided locally, before any network call

    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 4))!

    @Test func adultDateIsOk() {
        #expect(OnboardingLogic.checkBirthDate(day: "4", month: "9", year: "2008", now: now) == .ok("2008-09-04"))
        #expect(OnboardingLogic.checkBirthDate(day: "01", month: "01", year: "1960", now: now) == .ok("1960-01-01"))
    }

    @Test func birthdayNotYetReachedIsUnderAge() {
        #expect(OnboardingLogic.checkBirthDate(day: "5", month: "9", year: "2008", now: now) == .underAge)
        #expect(OnboardingLogic.checkBirthDate(day: "1", month: "1", year: "2015", now: now) == .underAge)
    }

    @Test func rollOverAndNonsenseDatesAreInvalid() {
        #expect(OnboardingLogic.checkBirthDate(day: "31", month: "2", year: "2000", now: now) == .invalid)   // 31/02 must not become 2 March
        #expect(OnboardingLogic.checkBirthDate(day: "1", month: "13", year: "2000", now: now) == .invalid)
        #expect(OnboardingLogic.checkBirthDate(day: "1", month: "1", year: "1890", now: now) == .invalid)    // over 120
        #expect(OnboardingLogic.checkBirthDate(day: "1", month: "1", year: "2030", now: now) == .invalid)    // future
        #expect(OnboardingLogic.checkBirthDate(day: "", month: "1", year: "2000", now: now) == .invalid)
        #expect(OnboardingLogic.checkBirthDate(day: "x", month: "1", year: "2000", now: now) == .invalid)
    }

    // Device-held progress

    @Test func draftRoundTripsAndClears() {
        let defaults = UserDefaults(suiteName: "OnboardingLogicTests-\(UUID().uuidString)")!
        var d = OnboardingDraft()
        d.step = 4; d.sex = "female"; d.age = "42"; d.height = "170"; d.weight = "65"; d.activity = "lightly_active"
        d.save(userId: "u1", defaults: defaults)
        #expect(OnboardingDraft.load(userId: "u1", defaults: defaults) == d)
        #expect(OnboardingDraft.load(userId: "u2", defaults: defaults) == OnboardingDraft())
        OnboardingDraft.clear(userId: "u1", defaults: defaults)
        #expect(OnboardingDraft.load(userId: "u1", defaults: defaults) == OnboardingDraft())
    }

    @Test func stepsAreEightInOrder() {
        #expect(OnboardingStep.allCases.count == OnboardingStep.total)
        #expect(OnboardingStep.welcome.next == .baseline)
        #expect(OnboardingStep.ready.next == nil)
    }
}
