import Foundation
import Testing
@testable import FunctionAlps

/// The Expo `intake-baseline` / `baseline-prefill` / `prefill-copy` tests, ported case for case.
@Suite("IntakeBaseline")
struct IntakeBaselineTests {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private static let gb = Locale(identifier: "en_GB")
    private static let june = "2026-06-12T09:14:16.985Z"
    private static let now = ISO8601.parse("2026-08-19T10:00:00Z")!

    private func profile(sex: MemberProfile.Sex? = nil, age: Int? = nil, height: Double? = nil, weight: Double? = nil, activity: String? = nil) -> MemberProfile {
        MemberProfile(sex: sex, age: age, heightCm: height, weightKg: weight, activityLevel: activity, healthGoals: [], currentComplaints: [], dietaryPattern: nil,
                      targetCalories: nil, targetProteinG: nil, targetCarbsG: nil, targetFatG: nil, goalMode: nil, onboardingCompletedAt: nil, locale: nil)
    }

    // The shape of a REAL row on CM OS (submitted 2026-06-12): three of five present.
    private let real = IntakeBaselineRead(gender: "Female", heightCm: nil, weightNow: "68", activity: "Intense", capturedOn: Self.june, dateOfBirth: nil)

    // MARK: Mappers

    @Test func sexReadsTheLiveWordingsAndFrench() {
        #expect(IntakeBaselineLogic.sex(fromIntake: "Female") == .female)
        #expect(IntakeBaselineLogic.sex(fromIntake: "Male") == .male)
        #expect(IntakeBaselineLogic.sex(fromIntake: "Femme") == .female)
        #expect(IntakeBaselineLogic.sex(fromIntake: "Homme") == .male)
    }

    @Test func sexIsNilForAnythingTheFormulaCannotPlace() {
        // Not a judgement about the person — the formula has no third branch, so we ask rather than guess.
        #expect(IntakeBaselineLogic.sex(fromIntake: "Non-binary") == nil)
        #expect(IntakeBaselineLogic.sex(fromIntake: "Prefer not to say") == nil)
        #expect(IntakeBaselineLogic.sex(fromIntake: "") == nil)
        #expect(IntakeBaselineLogic.sex(fromIntake: nil) == nil)
    }

    @Test func activityMapsTheFourValuesOnCMOS() {
        #expect(IntakeBaselineLogic.activity(fromIntake: "Sedentary") == .sedentary)
        #expect(IntakeBaselineLogic.activity(fromIntake: "Light") == .lightlyActive)
        #expect(IntakeBaselineLogic.activity(fromIntake: "Moderate") == .moderatelyActive)
        #expect(IntakeBaselineLogic.activity(fromIntake: "Intense") == .veryActive)
    }

    @Test func activityNeverAutoSelectsExtremelyActive() {
        let produced = ["Sedentary", "Light", "Moderate", "Intense", "Very intense", "Extreme"].map { IntakeBaselineLogic.activity(fromIntake: $0) }
        #expect(!produced.contains(.extremelyActive))
        #expect(IntakeBaselineLogic.activity(fromIntake: "Athlete") == nil)
        #expect(IntakeBaselineLogic.activity(fromIntake: nil) == nil)
    }

    @Test func heightAndWeightParseWhatTheQuestionnaireStores() {
        #expect(IntakeBaselineLogic.weight(fromIntake: "68") == 68)
        #expect(IntakeBaselineLogic.height(fromIntake: "172") == 172)
        #expect(IntakeBaselineLogic.weight(fromIntake: "68,5") == 68.5)   // CH/FR keyboards
    }

    @Test func heightAndWeightRejectOutOfRangeAndJunk() {
        // A weight of 7 is a typo or a different unit; prefilling it would be nodded through far more easily than a blank.
        #expect(IntakeBaselineLogic.weight(fromIntake: "7") == nil)
        #expect(IntakeBaselineLogic.weight(fromIntake: "900") == nil)
        #expect(IntakeBaselineLogic.height(fromIntake: "17") == nil)
        #expect(IntakeBaselineLogic.height(fromIntake: "300") == nil)
        #expect(IntakeBaselineLogic.weight(fromIntake: "about 70kg") == nil)
        #expect(IntakeBaselineLogic.weight(fromIntake: "1e2") == nil)
        #expect(IntakeBaselineLogic.weight(fromIntake: nil) == nil)
    }

    @Test func ageGivesWholeYearsNotRoundedOnes() {
        let on = Self.utc.date(from: DateComponents(year: 2026, month: 8, day: 19))!
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "1990-08-20", on: on, calendar: Self.utc) == 35)
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "1990-08-19", on: on, calendar: Self.utc) == 36)
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "1990-08-18", on: on, calendar: Self.utc) == 36)
    }

    @Test func ageIsNilOutsideTheRangeSoAPlaceholderDOBCannotPrefill() {
        let on = Self.utc.date(from: DateComponents(year: 2026, month: 8, day: 19))!
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "1900-01-01", on: on, calendar: Self.utc) == nil)
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "2020-01-01", on: on, calendar: Self.utc) == nil)
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: nil) == nil)
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "") == nil)
        #expect(IntakeBaselineLogic.age(fromDateOfBirth: "not a date") == nil)
    }

    @Test func realRowYieldsExactlyThreeOfFiveAndInventsNothing() {
        #expect(IntakeBaselineLogic.baseline(from: real) == PartialBaseline(sex: .female, age: nil, heightCm: nil, weightKg: 68, activity: .veryActive))
        #expect(IntakeBaselineLogic.baseline(from: nil) == .empty)
    }

    // MARK: The member's own row

    @Test func partialFromProfileIsNotAllOrNothing() {
        #expect(IntakeBaselineLogic.partial(fromProfile: profile(sex: .female, height: 165)) == PartialBaseline(sex: .female, age: nil, heightCm: 165, weightKg: nil, activity: nil))
    }

    @Test func partialFromProfileDropsWhatTheFormWouldReject() {
        #expect(IntakeBaselineLogic.partial(fromProfile: profile(sex: .other, age: 4, height: 12, weight: 5000, activity: "athlete")) == .empty)
        #expect(IntakeBaselineLogic.partial(fromProfile: nil) == .empty)
    }

    // MARK: Merge

    private var herIntake: PartialBaseline { PartialBaseline(sex: .female, age: nil, heightCm: nil, weightKg: 68, activity: .veryActive) }

    @Test func mergeFillsTheGapsFromTheRecordAndLabelsOnlyThose() {
        let out = IntakeBaselineLogic.merge(profile: .empty, intake: herIntake, capturedOn: Self.june)
        #expect(out.values == herIntake)
        #expect(Set(out.fromRecord) == [.activity, .sex, .weightKg])
        #expect(Set(out.missing) == [.age, .heightCm])
        #expect(out.capturedOn == Self.june)
        #expect(out.showsBanner)
    }

    @Test func theMembersOwnValueBeatsTheRecordAndIsNotLabelled() {
        // She weighed 68 at intake and saved 71 in the app since. 71 wins, and no chip claims we got it from her record.
        let out = IntakeBaselineLogic.merge(profile: PartialBaseline(weightKg: 71), intake: herIntake, capturedOn: Self.june)
        #expect(out.values.weightKg == 71)
        #expect(out.origins[.weightKg] == .member)
        #expect(!out.fromRecord.contains(.weightKg))
    }

    @Test func mergeMarksEachFieldWithWhereItCameFrom() {
        let out = IntakeBaselineLogic.merge(profile: PartialBaseline(age: 41), intake: herIntake, capturedOn: Self.june)
        #expect(out.origins == [.age: .member, .sex: .record, .weightKg: .record, .activity: .record])
    }

    @Test func mergeReportsNoCaptureDateWhenNothingCameFromTheRecord() {
        // Otherwise the screen could print "Recorded 12 June" against a value the member typed themselves.
        let mine = PartialBaseline(sex: .female, age: 41, heightCm: 165, weightKg: 71, activity: .veryActive)
        let out = IntakeBaselineLogic.merge(profile: mine, intake: herIntake, capturedOn: Self.june)
        #expect(out.fromRecord.isEmpty)
        #expect(out.capturedOn == nil)
        #expect(!out.showsBanner)
    }

    @Test func mergeWithNoSourcesClaimsNothing() {
        let out = IntakeBaselineLogic.merge(profile: .empty, intake: .empty, capturedOn: nil)
        #expect(out.values == .empty)
        #expect(out.fromRecord.isEmpty)
        #expect(Set(out.missing) == Set(BaselineField.allCases))
        #expect(!out.showsBanner)
    }

    // MARK: Copy

    @Test func joinNaturallyReadsAsASentenceAtEveryLength() {
        #expect(PrefillCopy.joinNaturally([]) == "")
        #expect(PrefillCopy.joinNaturally(["weight"]) == "weight")
        #expect(PrefillCopy.joinNaturally(["age", "height"]) == "age and height")
        #expect(PrefillCopy.joinNaturally(["sex", "weight", "activity level"]) == "sex, weight and activity level")
    }

    @Test func nameFieldsUsesScreenOrderNeverArgumentOrder() {
        #expect(PrefillCopy.nameFields([.activity, .sex, .age]) == "age, sex and activity level")
        #expect(PrefillCopy.nameFields([.weightKg, .heightCm]) == "height and weight")
    }

    @Test func capturedOnOmitsTheYearInTheCurrentYearAndKeepsItOtherwise() {
        #expect(PrefillCopy.formatCapturedOn(Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc) == "12 June")
        #expect(PrefillCopy.formatCapturedOn("2024-06-12T00:00:00Z", now: Self.now, locale: Self.gb, calendar: Self.utc) == "12 June 2024")
        #expect(PrefillCopy.formatCapturedOn(nil) == nil)
        #expect(PrefillCopy.formatCapturedOn("nonsense") == nil)
    }

    @Test func bannerIsTheSentenceThatWasSignedOff() {
        let copy = PrefillCopy.banner(known: [.sex, .weightKg, .activity], missing: [.age, .heightCm], capturedOn: Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc)
        #expect(copy.title == "Let’s fill in the gaps.")
        #expect(copy.sentence == "We've brought over your sex, weight and activity level from the questionnaire you completed on 12 June. We still need your age and height · just those two.")
    }

    @Test func bannerSurvivesTheShapesThatBreakTemplatedCopy() {
        let one = PrefillCopy.banner(known: [.sex, .weightKg], missing: [.heightCm], capturedOn: Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc)
        #expect(one.sentence.contains("We still need your height."))
        #expect(!one.sentence.contains("just those"))

        let three = PrefillCopy.banner(known: [.weightKg], missing: [.age, .sex, .heightCm], capturedOn: Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc)
        #expect(three.sentence.contains("We still need your age, sex and height."))
        #expect(!three.sentence.contains("just those"))

        let oneKnown = PrefillCopy.banner(known: [.weightKg], missing: [.age, .heightCm], capturedOn: Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc)
        #expect(oneKnown.sentence.contains("We've brought over your weight from"))
        #expect(!oneKnown.sentence.contains("your weight and"))

        let undated = PrefillCopy.banner(known: [.weightKg], missing: [.age], capturedOn: nil, now: Self.now, locale: Self.gb, calendar: Self.utc)
        #expect(undated.sentence.contains("from your FunctionAlps record."))
        #expect(!undated.sentence.contains("nil"))

        #expect(PrefillCopy.banner(known: [], missing: [.age], capturedOn: Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc).sentence == "We still need your age.")
        #expect(PrefillCopy.banner(known: [.age], missing: [], capturedOn: Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc).sentence
                == "We've brought over your age from the questionnaire you completed on 12 June.")
    }

    @Test func weightNoteDatesTheValueAndInvitesACorrection() {
        #expect(PrefillCopy.weightRecordedNote(Self.june, now: Self.now, locale: Self.gb, calendar: Self.utc) == "Recorded 12 June · change it if it’s moved.")
        #expect(PrefillCopy.weightRecordedNote(nil) == nil)
    }
}
