import Foundation
import Testing
@testable import FunctionAlps

struct ProtocolLensTests {
    private let fodmap = ProtocolLens.PatientProtocol(protocolKey: "low_fodmap", strictness: .relaxed, visibility: .coached)
    private let oxalate = ProtocolLens.PatientProtocol(protocolKey: "low_oxalate", strictness: .strict, visibility: .soft)

    @Test func matchesAtWordStartsWithSeverity() {
        let flags = ProtocolLens.match(items: ["Garlic butter steak", "Green tea", "Pineapple"], protocols: [fodmap])
        #expect(flags.map(\.matchedTerm) == ["garlic"])
        #expect(flags.first?.severity == .high && flags.first?.item == "Garlic butter steak")
        // 'tea' / 'apple' are not FODMAP terms; and a word-start match never fires inside "steak" or "pineapple"
        #expect(ProtocolLens.match(items: ["Steak", "Pineapple"], protocols: [ProtocolLens.PatientProtocol(protocolKey: "low_salicylate", strictness: .strict, visibility: .coached)]).map(\.matchedTerm) == ["pineapple"])
    }

    @Test func mostSpecificTermWinsAndOverridesRunLast() {
        let sweet = ProtocolLens.match(items: ["Sweet potato mash"], protocols: [fodmap])
        #expect(sweet.map(\.matchedTerm) == ["sweet potato"])   // 'potato' is not a FODMAP term; the compound is moderate
        let allowed = ProtocolLens.match(items: ["Sweet potato mash"], protocols: [fodmap], overrides: [ProtocolLens.Override(protocolKey: "low_fodmap", foodTerm: "Sweet Potato", action: .allow)])
        #expect(allowed.isEmpty)
        let extra = ProtocolLens.match(items: ["Kombucha"], protocols: [fodmap], overrides: [ProtocolLens.Override(protocolKey: "low_fodmap", foodTerm: "kombucha", action: .flag)])
        #expect(extra.count == 1 && extra[0].severity == .high)
        #expect(ProtocolLens.match(items: ["Onion soup"], protocols: [ProtocolLens.PatientProtocol(protocolKey: "unknown", strictness: .strict, visibility: .coached)]).isEmpty)
    }

    @Test func strictnessAndVisibilityAreRenderTimeRules() {
        let moderate = ProtocolLens.Flag(item: "avocado toast", protocolKey: "low_fodmap", severity: .moderate, matchedTerm: "avocado")
        #expect(!ProtocolLens.isFlagged(moderate, strictness: .relaxed) && ProtocolLens.isFlagged(moderate, strictness: .strict))
        #expect(ProtocolLens.effectiveVisibility([oxalate, fodmap]) == .coached)
        #expect(ProtocolLens.effectiveVisibility([]) == .silent)
        #expect(ProtocolLens.visibility(of: "low_oxalate", in: [oxalate, fodmap]) == .soft)
        #expect(ProtocolLens.visibility(of: "nope", in: [fodmap]) == .silent)
        #expect(ProtocolLens.strictness(of: [oxalate, fodmap]) == .strict)
    }

    @Test func coachedFlagsNeverLeakASoftProtocol() async {
        let service = ProtocolService(backend: RecordingBackend())
        let data = ProtocolData(protocols: [oxalate, fodmap], overrides: [])
        let flags = service.coachedFlags(items: ["Spinach salad", "Onion rings"], data: data)
        #expect(flags?.map(\.matchedTerm) == ["onion"])          // spinach is oxalate (soft) → hidden
        #expect(service.coachedFlags(items: ["Rice"], data: ProtocolData(protocols: [oxalate], overrides: [])) == nil)
        #expect(service.coachedFlags(items: ["Rice"], data: data) == [])
    }

    @Test func theWeekCountsMealsNotFlagRows() {
        let onion = ProtocolLens.Flag(item: "onion", protocolKey: "low_fodmap", severity: .high, matchedTerm: "onion")
        let onion2 = ProtocolLens.Flag(item: "onion soup", protocolKey: "low_fodmap", severity: .high, matchedTerm: "onion")
        let avocado = ProtocolLens.Flag(item: "avocado", protocolKey: "low_fodmap", severity: .moderate, matchedTerm: "avocado")
        let week = ProtocolLens.summarizeWeek([nil, [], [onion, onion2, avocado], [onion]], strictness: .relaxed)
        #expect(week.totalMeals == 3 && week.fitMeals == 1)
        #expect(week.flaggedFoods.map { "\($0.name):\($0.count)" } == ["onion:2"])
        let strict = ProtocolLens.summarizeWeek([[onion, avocado]], strictness: .strict)
        #expect(strict.flaggedFoods.map(\.name) == ["avocado", "onion"])   // ties break alphabetically
    }

    @Test func storedFlagsDecodeFromTheRowShape() throws {
        let json = #"[{"item":"onion","protocol":"low_fodmap","severity":"high","matched_term":"onion"}]"#
        let flags = try JSON.decode([ProtocolLens.Flag].self, from: Data(json.utf8))
        #expect(flags == [ProtocolLens.Flag(item: "onion", protocolKey: "low_fodmap", severity: .high, matchedTerm: "onion")])
    }
}
