import Foundation
import Testing
@testable import FunctionAlps

@Suite("MealScoring (the shared rules engine)")
struct MealScoringTests {
    @Test func classifiesByWordBoundaryNotSubstring() {
        // v1 matched substrings: "g-OAT cheese" → oat, "dough-NUT" → nut, "SUGAR snap peas" → sugar.
        #expect(MealScoring.classify(name: "goat cheese") == .dairy)
        #expect(MealScoring.classify(name: "doughnut") == .sweet)
        #expect(MealScoring.classify(name: "sugar snap peas") == .legume)
        #expect(MealScoring.classify(name: "strawberry jam") == .sweet)
        #expect(MealScoring.classify(name: "banana bread") == .refinedGrain)
        #expect(MealScoring.classify(name: "peanut butter") == .nutSeed)
        #expect(MealScoring.classify(name: "oat milk") == .wholeGrain)
        #expect(MealScoring.classify(name: "butternut squash") == .vegetable)
    }

    @Test func categoryBeatsTheName() {
        #expect(MealScoring.classify(name: "fillet", category: "Finfish and Shellfish Products") == .fishLean)
        #expect(MealScoring.classify(name: "salmon fillet", category: "Finfish and Shellfish Products") == .fishOily)
        #expect(MealScoring.classify(name: "cornflakes", category: "Breakfast Cereals") == .refinedGrain)
    }

    @Test func preparationBeatsProvenance() {
        #expect(MealScoring.classify(name: "fried potatoes") == .friedFast)
        #expect(MealScoring.classify(name: "jambon cru") == .processedMeat)
    }

    @Test func scoresAreInRangeAndNeutralWhenEmpty() {
        let empty = MealScoring.score([])
        #expect(empty == MealScores(inflammation: 60, glycemic: 60, digestion: 60))
        let meal = [
            MealItem(name: "lentils", estimatedGrams: 180, kcal: 210, proteinG: 16, carbsG: 36, fatG: 0.7, fiberG: 14),
            MealItem(name: "spinach", estimatedGrams: 60, kcal: 14, proteinG: 1.7, carbsG: 2, fatG: 0.2, fiberG: 1.3),
            MealItem(name: "olive oil", estimatedGrams: 14, kcal: 124, proteinG: 0, carbsG: 0, fatG: 14, fiberG: 0),
        ]
        let s = MealScoring.composition(of: meal)
        #expect((0...100).contains(s.plantsFibre.value))
        #expect(s.plantsFibre.value >= 60)          // 15 g of fibre from two plants and oil
        #expect(s.fatQuality.value >= 80)           // the fat is olive oil
        #expect(s.carbQuality.value >= 60)          // legume carbohydrate with its fibre
        #expect(s.legacy.digestion == s.plantsFibre.value)
    }

    @Test func fatQualityIgnoresQuantity() {
        let walnuts = [MealItem(name: "walnuts", estimatedGrams: 30, kcal: 196, proteinG: 4.5, carbsG: 4, fatG: 19.5, fiberG: 2)]
        let fries = [MealItem(name: "french fries", estimatedGrams: 150, kcal: 470, proteinG: 5, carbsG: 60, fatG: 22, fiberG: 4)]
        #expect(MealScoring.composition(of: walnuts).fatQuality.value > MealScoring.composition(of: fries).fatQuality.value)
    }
}

@Suite("MealEdit (portions rescale locally, corrections re-price by row)")
struct MealEditTests {
    private let chicken = MealItem(name: "chicken", estimatedGrams: 100, kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6, fiberG: 0)
    private let rice = MealItem(name: "rice", estimatedGrams: 150, kcal: 195, proteinG: 4, carbsG: 42, fatG: 0.4, fiberG: 0.6)

    @Test func scalingIsLinearOffTheRowsOwnDensity() {
        let doubled = MealEdit.scale(chicken, toGrams: 200)
        #expect(doubled.estimatedGrams == 200)
        #expect(doubled.kcal == 330)
        #expect(doubled.proteinG == 62)
        // Unknown base grams: only the weight changes; the macros wait for a re-price.
        let blank = MealEdit.scale(MealItem(name: "x", kcal: 100), toGrams: 50)
        #expect(blank.estimatedGrams == 50 && blank.kcal == 100)
    }

    @Test func totalsAndScoresRecompute() {
        let draft = MealDraft(dishName: "Bowl", items: [chicken, rice], totals: MealEdit.totals(of: [chicken, rice]), micros: [:], scores: MealScoring.score([chicken, rice]))
        #expect(draft.totals.kcal == 360)
        let edited = MealEdit.recompute(draft, items: [chicken])
        #expect(edited.totals.kcal == 165)
        #expect(edited.scores == MealScoring.score([chicken]))
    }

    @Test func renameStripsPricingOnlyOnSameLengthLists() {
        let renamed = MealEdit.withRenamesUnpriced(prev: [chicken, rice], next: [MealItem(name: "chicken thigh", estimatedGrams: 100, kcal: 165), rice])
        #expect(MealEdit.isUnpriced(renamed[0]) && renamed[0].name == "chicken thigh" && renamed[0].estimatedGrams == 100)
        #expect(!MealEdit.isUnpriced(renamed[1]))
        // An add shifts positions without renaming anything — nothing is stripped.
        let added = MealEdit.withRenamesUnpriced(prev: [chicken], next: [rice, chicken])
        #expect(added.allSatisfy { !MealEdit.isUnpriced($0) })
    }

    @Test func aPortionChangeOnAnUnpricedRowIsARepricingEvent() {
        let blank = MealItem(name: "quark", estimatedGrams: 100)
        var moved = blank; moved.estimatedGrams = 150
        #expect(MealEdit.hasUnpricedPortionChange(prev: [blank], next: [moved]))
        var pricedMoved = chicken; pricedMoved.estimatedGrams = 150
        #expect(!MealEdit.hasUnpricedPortionChange(prev: [chicken], next: [pricedMoved]))
    }

    @Test func mergeFindsRowsByNameNeverByPosition() {
        let items = [MealItem(name: "carrot", estimatedGrams: 80), chicken]
        let requests = MealEdit.pricingRequests(for: items)
        #expect(requests == [MealEdit.PricingRequest(name: "carrot", grams: 80)])
        // The list shifted while the round trip was in flight: the carrot moved and was nudged to 100 g.
        var nudged = items[0]; nudged.estimatedGrams = 100
        let shifted = [chicken, nudged]
        let resolved = [MealEdit.ResolvedPricing(name: "Carrot, raw", kcal: 33, proteinG: 0.7, carbsG: 7.7, fatG: 0.2, fiberG: 2.2, basis: "matched")]
        let merged = MealEdit.mergeResolvedPricing(items: shifted, requests: requests, resolved: resolved)
        #expect(merged.unresolved.isEmpty)
        #expect(merged.items[1].name == "carrot")          // display keeps the member's name
        #expect(merged.items[1].estimatedGrams == 100)      // their grams, scaled from the 80 g answer
        #expect(merged.items[1].kcal == 41.3)
        #expect(merged.items[0] == chicken)                 // untouched rows stay byte-identical
    }

    @Test func aZeroIsNotAPrice() {
        let items = [MealItem(name: "mystery", estimatedGrams: 100)]
        let requests = MealEdit.pricingRequests(for: items)
        let terminal = [MealEdit.ResolvedPricing(name: "mystery", kcal: 0, basis: "estimated", needsReview: true)]
        let merged = MealEdit.mergeResolvedPricing(items: items, requests: requests, resolved: terminal)
        #expect(merged.unresolved == ["mystery"])
        #expect(MealEdit.isUnpriced(merged.items[0]))
        let short = MealEdit.mergeResolvedPricing(items: items, requests: requests, resolved: [])
        #expect(short.unresolved == ["mystery"])
    }

    @Test func portionStepsAreAppropriateMeasures() {
        #expect(MealEdit.portionStep(20) == 5 && MealEdit.portionStep(100) == 10 && MealEdit.portionStep(300) == 25 && MealEdit.portionStep(800) == 50)
        #expect(MealEdit.nudged(30, direction: 1) == 35)
        #expect(MealEdit.nudged(35, direction: -1) == 25)
        #expect(MealEdit.nudged(5, direction: -1) == 5)
    }
}

@Suite("ClarificationLogic (what was asked decides where the answer goes)")
struct ClarificationTests {
    @Test func aPortionOpensWithACountAndCarriesAMeasure() {
        #expect(ClarificationLogic.looksLikeQuantity("30 g (2 tbsp)"))
        #expect(ClarificationLogic.looksLikeQuantity("a handful"))
        #expect(ClarificationLogic.looksLikeQuantity("2 cuillères à soupe"))
        #expect(!ClarificationLogic.looksLikeQuantity("goat cheese slice"))
        #expect(!ClarificationLogic.looksLikeQuantity("parmigiano"))
    }

    @Test func theLabelWinsAndTheOptionsDecideWithoutIt() {
        #expect(ClarificationLogic.classify(kind: "quantity", options: ["cow", "goat"]) == .quantity)
        #expect(ClarificationLogic.classify(kind: nil, options: ["30 g", "60 g"]) == .quantity)
        #expect(ClarificationLogic.classify(kind: nil, options: ["30 g", "goat cheese"]) == .identity)
        #expect(ClarificationLogic.classify(kind: "nonsense", options: []) == .identity)
    }

    @Test func quantityAnswersParseGramsAndMeasures() {
        let a = ClarificationLogic.parseQuantityAnswer("30 g (2 tbsp)")
        #expect(a.estimatedG == 30 && a.volumeMeasure == "2 tbsp" && a.quantity == "30 g (2 tbsp)")
        let b = ClarificationLogic.parseQuantityAnswer("1,5 kg")
        #expect(b.estimatedG == 1500 && b.volumeMeasure == nil)
        let c = ClarificationLogic.parseQuantityAnswer("2 tbsp")
        #expect(c.estimatedG == nil && c.volumeMeasure == "2 tbsp")
    }

    @Test func theNameIsNeverTouchedByAQuantityAnswer() {
        let item = MealPreprocess.Item(name: "parmigiano", quantity: nil, estimatedG: 100, volumeMeasure: nil, confidence: "medium")
        let quantity = ClarificationLogic.apply("30 g (2 tbsp)", kind: .quantity, to: item)
        #expect(quantity.name == "parmigiano" && quantity.estimatedG == 30 && quantity.volumeMeasure == "2 tbsp" && quantity.confidence == "high")
        let identity = ClarificationLogic.apply("goat cheese", kind: .identity, to: item)
        #expect(identity.name == "goat cheese" && identity.estimatedG == 100)
    }

    @Test func frenchMembersNeverReadAnEnglishUnit() {
        #expect(ClarificationLogic.localiseQuantityOption("30 g (2 tbsp)", locale: "fr") == "30 g (2 c. à soupe)")
        #expect(ClarificationLogic.localiseQuantityOption("half a cup", locale: "fr") == "une demi-tasse")
        #expect(ClarificationLogic.localiseQuantityOption("a handful", locale: "fr") == "une poignée")
        #expect(ClarificationLogic.localiseQuantityOption("2 glasses", locale: "fr") == "2 verres")
        #expect(ClarificationLogic.localiseQuantityOption("1 slice", locale: "fr") == "1 tranche")
        #expect(ClarificationLogic.localiseQuantityOption("30 g (2 tbsp)", locale: "en") == "30 g (2 tbsp)")
        #expect(ClarificationLogic.localiseQuantityOption("une poignée", locale: "fr") == "une poignée")
    }
}

@Suite("PortionReference (household measures, the owner's table)")
struct PortionReferenceTests {
    @Test func theOrderResolvesEveryKnownCollision() {
        #expect(PortionReference.family(for: "almond butter") == "nut-butter")
        #expect(PortionReference.family(for: "pommes de terre") == "potato")
        #expect(PortionReference.family(for: "huile d'olive") == "fat")
        #expect(PortionReference.family(for: "jus d'orange") == "drink")
        #expect(PortionReference.family(for: "raisins secs") == "fruit-dried")
        #expect(PortionReference.family(for: "thon en boîte") == "canned-fish")
        #expect(PortionReference.family(for: "jambon") == "charcuterie")
        #expect(PortionReference.family(for: "glace vanille") == "ice-cream")
        #expect(PortionReference.family(for: "grilled chicken") == "protein")
    }

    @Test func aRecognisedFoodGetsAbsoluteMeasures() {
        let opts = PortionReference.options(for: "olive oil", estimatedGrams: 400)
        #expect(opts.map(\.grams) == [5, 14, 28])
        #expect(opts.map(\.label) == ["1 tsp", "1 tbsp", "2 tbsp"])
    }

    @Test func anUnknownFoodFallsBackToAMultiplierInFiveGramSteps() {
        let opts = PortionReference.options(for: "zorblat", estimatedGrams: 112)
        #expect(opts.map(\.grams) == [65, 110, 170])
        #expect(PortionReference.options(for: "zorblat", estimatedGrams: 0).map(\.grams) == [60, 100, 150])
    }

    @Test func onlyAnExactChipGramsReadsAsSelected() {
        let opts = PortionReference.options(for: "cheese", estimatedGrams: 100)
        #expect(PortionReference.selectedLabel(opts, grams: 30) == "1 slice")
        #expect(PortionReference.selectedLabel(opts, grams: 31) == nil)
    }
}

@Suite("FoodNameNormaliser + CorrectionOrigins (the learning loop)")
struct FoodAliasTests {
    @Test func theKeyIsTheResolversKey() {
        #expect(FoodNameNormaliser.aliasKey("Grilled chicken breast") == "chicken breast")
        #expect(FoodNameNormaliser.aliasKey("Eggs") == "egg")
        #expect(FoodNameNormaliser.aliasKey("Cherry tomatoes") == "cherry tomato")
        #expect(FoodNameNormaliser.aliasKey("Roast beef") == "beef")
        #expect(FoodNameNormaliser.normalise("Roast beef").alternatives.contains("roast beef"))
        #expect(FoodNameNormaliser.aliasKey("Pommes de terre (rôties)") == "pomme de terre")
        #expect(FoodNameNormaliser.aliasKey("...") == "")
    }

    @Test func onlyRowsThePipelineNamedMayLearn() {
        let origins = CorrectionOrigins()
        origins.seed([MealItem(name: "sweet potato cubes"), MealItem(name: "rice")])
        origins.rename(from: "sweet potato cubes", to: "sweet potato cube")   // mid-typing
        origins.rename(from: "sweet potato cube", to: "carrots")
        origins.rename(from: "s", to: "cottage cheese")                       // a hand-added row: never learned
        let taken = origins.take([MealItem(name: "carrots", estimatedGrams: 80), MealItem(name: "rice"), MealItem(name: "cottage cheese")])
        #expect(taken == [CorrectionOrigins.Correction(fromName: "sweet potato cubes", toName: "carrots", grams: 80)])
        // Each pair at most once, and a case/plural tweak is not a correction.
        #expect(origins.take([MealItem(name: "carrots")]).isEmpty)
        let plural = CorrectionOrigins()
        plural.seed([MealItem(name: "egg")])
        plural.rename(from: "egg", to: "Eggs")
        #expect(plural.take([MealItem(name: "Eggs")]).isEmpty)
    }
}
