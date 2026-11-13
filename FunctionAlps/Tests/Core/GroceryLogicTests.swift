import Foundation
import Testing
@testable import FunctionAlps

private let en = Locale(identifier: "en_US")

private func item(_ id: String, _ name: String, qty: Double? = nil, unit: String? = nil, buy: (Int, String)? = nil,
                  pieces: Int? = nil, toTaste: Bool = false, approx: Bool = false, checked: Bool = false, have: Bool = false,
                  instead: [String] = [], recipes: [String] = [], excluded: Bool = false) -> GroceryItem {
    GroceryItem(foodItemId: id, name: name, qty: qty, unit: unit, buyCount: buy?.0, buyUnit: nil, buyLabel: buy?.1,
                approxPieces: pieces, staple: false, toTaste: toTaste, approx: approx, excluded: excluded,
                uses: recipes.map { GroceryUse(date: nil, meal: nil, recipe: $0) }, insteadOf: instead, checked: checked, have: have)
}

private let list = GroceryList(
    planId: "p1", periodStart: "2026-11-16", periodEnd: "2026-11-22",
    aisles: [
        GroceryAisle(code: "produce", label: "Fruit & vegetables", items: [
            item("tom", "Cherry tomatoes", qty: 400, unit: "g"),
            item("cuc", "Cucumber", qty: 2, unit: nil, checked: true),
            item("pot", "Small potatoes", qty: 800, unit: "g"),
        ]),
        GroceryAisle(code: "fish", label: "Fish, meat & eggs", items: [item("sal", "Salmon fillet", qty: 1100, unit: "g")]),
        GroceryAisle(code: "oils", label: "Oils & sauces", items: [item("tam", "Tamari", buy: (1, "bottle"), have: true)]),
    ],
    custom: [GroceryCustomItem(id: "c1", label: "Dish soap", qtyText: nil, aisleCode: nil, checked: false)]
)

@Suite("Grocery logic")
struct GroceryLogicTests {
    @Test func quantitiesReadLikeShopping() {
        #expect(GroceryLogic.quantityLabel(item("a", "A", qty: 400, unit: "g"), locale: en) == "400 g")
        #expect(GroceryLogic.quantityLabel(item("a", "A", qty: 1100, unit: "g"), locale: en) == "1.1 kg")
        #expect(GroceryLogic.quantityLabel(item("a", "A", qty: 1500, unit: "ml"), locale: en) == "1.5 l")
        #expect(GroceryLogic.quantityLabel(item("a", "A", qty: 2, unit: nil), locale: en) == "2")
        #expect(GroceryLogic.quantityLabel(item("a", "A", buy: (2, "tin (400 g)")), locale: en) == "2 × tin (400 g)")
        #expect(GroceryLogic.quantityLabel(item("a", "A", qty: 300, unit: "g", approx: true), locale: en) == "≈ 300 g")
        #expect(GroceryLogic.quantityLabel(item("a", "A", qty: 400, unit: "g", pieces: 3), locale: en) == "400 g (≈ 3 pieces)")
        #expect(GroceryLogic.quantityLabel(item("a", "Salt", toTaste: true), locale: en) == "to taste")
        #expect(GroceryLogic.quantityLabel(item("a", "A"), locale: en) == "")
    }

    @Test func countsTreatTickedAndAlreadyHaveAsInTheBasket() {
        let c = GroceryLogic.counts(list)
        #expect(c.total == 6)
        #expect(c.inBasket == 2)
        #expect(c.toBuy == 4)
    }

    @Test func stillToBuyLeavesOutTickedAndOwnedAndEmptyAisles() {
        let s = GroceryLogic.sections(list, scope: .stillToBuy, locale: en)
        #expect(s.map(\.title) == ["Fruit & vegetables", "Fish, meat & eggs", "Your own items"])
        #expect(s[0].lines == ["Cherry tomatoes, 400 g", "Small potatoes, 800 g"])
        #expect(GroceryLogic.lineCount(list, scope: .stillToBuy) == 4)
        #expect(GroceryLogic.lineCount(list, scope: .whole) == 6)
    }

    @Test func wholeListKeepsEverythingInStoreOrder() {
        let s = GroceryLogic.sections(list, scope: .whole, locale: en)
        #expect(s.map(\.title) == ["Fruit & vegetables", "Fish, meat & eggs", "Oils & sauces", "Your own items"])
        #expect(s[2].lines == ["Tamari, 1 × bottle"])
    }

    @Test func textShareIsPlainAndGroupedByAisle() {
        let text = GroceryLogic.text(list, scope: .stillToBuy, title: "Groceries · 16–22 Nov", locale: en)
        #expect(text == """
        Groceries · 16–22 Nov

        FRUIT & VEGETABLES
        - Cherry tomatoes, 400 g
        - Small potatoes, 800 g

        FISH, MEAT & EGGS
        - Salmon fillet, 1.1 kg

        YOUR OWN ITEMS
        - Dish soap
        """)
    }

    @Test func tickingOneLineChangesOnlyThatLine() {
        let next = GroceryLogic.setting(.food("tom"), checked: true, in: list)
        #expect(next.aisles[0].items[0].checked)
        #expect(next.aisles[0].items[2].checked == false)
        #expect(GroceryLogic.counts(next).inBasket == 3)
        let own = GroceryLogic.setting(.custom("c1"), checked: true, in: next)
        #expect(own.custom[0].checked)
        #expect(GroceryLogic.setting(.food("tom"), checked: false, in: next) == list)
    }

    @Test func contextNamesWhatASwapReplaced() {
        let i = item("a", "Tamari", instead: ["soy sauce"], recipes: ["Rainbow bowl", "Rainbow bowl", "Salmon plate", "Third"])
        #expect(GroceryLogic.context(i) == "instead of soy sauce · Rainbow bowl, Salmon plate")
        #expect(GroceryLogic.context(item("a", "A")) == nil)
        #expect(GroceryLogic.context(item("a", "A", excluded: true)) == "no longer fits your plan")
    }

    @Test func periodLabelsCollapseTheMonth() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        #expect(GroceryLogic.periodLabel(start: "2026-11-16", end: "2026-11-22", calendar: cal, locale: en) == "16–22 Nov")
        #expect(GroceryLogic.periodLabel(start: "2026-11-28", end: "2026-12-04", calendar: cal, locale: en) == "28 Nov – 4 Dec")
        #expect(GroceryLogic.periodLabel(start: nil, end: nil, calendar: cal, locale: en) == nil)
    }
}

@Suite("Grocery PDF")
struct GroceryPDFTests {
    private func sections(_ aisles: Int, lines: Int) -> [GroceryShareSection] {
        (0..<aisles).map { a in GroceryShareSection(title: "Aisle \(a)", lines: (0..<lines).map { "Item \(a)-\($0)" }) }
    }

    @Test func aShortListIsOnePage() {
        let pages = GroceryPDF.paginate(sections(3, lines: 4))
        #expect(pages.count == 1)
        #expect(pages[0].count == 3 + 12)
    }

    @Test func aLongListFlowsOntoMorePages() {
        let pages = GroceryPDF.paginate(sections(8, lines: 14))
        #expect(pages.count > 1)
        let lines = pages.flatMap { $0 }.filter { if case .line = $0 { true } else { false } }
        #expect(lines.count == 8 * 14)
    }

    @Test func aHeadingIsNeverLeftAloneAtTheBottomOfAPage() {
        for aisles in 1...12 {
            for page in GroceryPDF.paginate(sections(aisles, lines: 9)) {
                if case .heading = page.last { Issue.record("page ends on a heading with \(aisles) aisles") }
            }
        }
    }

    @Test func anEmptyListStillMakesOnePage() {
        #expect(GroceryPDF.paginate([]).count == 1)
    }

    #if canImport(UIKit)
    @Test func renderProducesARealPDFWithTheRightPageCount() throws {
        let secs = sections(8, lines: 14)
        let data = GroceryPDF.render(sections: secs, title: "Groceries", subtitle: "16–22 Nov")
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
        let doc = try #require(CGPDFDocument(try #require(CGDataProvider(data: data as CFData))))
        #expect(doc.numberOfPages == GroceryPDF.paginate(secs).count)
        let url = try GroceryPDF.writeTemporaryFile(data, name: "test-groceries.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }
    #endif
}
