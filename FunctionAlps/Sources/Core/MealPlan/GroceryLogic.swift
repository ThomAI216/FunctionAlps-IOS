import Foundation

/// What a shared copy of the list holds.
enum GroceryShareScope: String, Sendable, CaseIterable, Identifiable {
    case stillToBuy, whole
    var id: String { rawValue }
}

/// One aisle's lines, ready to print: the text share, the copy and the PDF all read these.
struct GroceryShareSection: Sendable, Equatable {
    let title: String
    let lines: [String]
}

/// Pure grocery rules: how a quantity reads, what is still to buy, the text and the sections for export.
enum GroceryLogic {
    // MARK: Quantity

    /// "400 g", "1.1 kg", "2 × tin (400 g)", "to taste". Amounts come from the server already rounded to something
    /// one can buy; this only formats them.
    static func quantityLabel(_ item: GroceryItem, locale: Locale = .current) -> String {
        if item.toTaste { return String(localized: "grocery.toTaste", defaultValue: "to taste") }
        var text: String
        if let count = item.buyCount, count > 0, let label = (item.buyLabel ?? item.buyUnit)?.nilIfEmpty {
            text = "\(count) × \(label)"
        } else if let qty = item.qty {
            text = amount(qty, unit: item.unit, locale: locale)
        } else {
            return ""
        }
        if let pieces = item.approxPieces, pieces > 0, item.buyCount == nil {
            text += " " + String(localized: "grocery.pieces", defaultValue: "(≈ \(pieces) pieces)")
        }
        if item.approx, item.buyCount == nil { text = "≈ " + text }
        return text
    }

    /// 1100 g reads "1.1 kg", 1500 ml "1.5 l"; other units are printed as they come.
    static func amount(_ qty: Double, unit: String?, locale: Locale = .current) -> String {
        var value = qty
        var unitText = unit ?? ""
        if unitText == "g", value >= 1000 { value /= 1000; unitText = "kg" }
        if unitText == "ml", value >= 1000 { value /= 1000; unitText = "l" }
        let number = number(value, locale: locale)
        return unitText.isEmpty ? number : "\(number) \(unitText)"
    }

    static func number(_ value: Double, locale: Locale = .current, maxFraction: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxFraction
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Counts and filters

    /// Not ticked and not "I have this": what is left to buy.
    static func isToBuy(_ item: GroceryItem) -> Bool { !item.checked && !item.have }

    struct Counts: Sendable, Equatable {
        let total: Int
        let inBasket: Int
        var toBuy: Int { total - inBasket }
    }

    /// Items "in the basket" are the ticked ones and the ones the member already has.
    static func counts(_ list: GroceryList) -> Counts {
        let items = list.aisles.flatMap(\.items)
        let inBasket = items.filter { !isToBuy($0) }.count + list.custom.filter(\.checked).count
        return Counts(total: items.count + list.custom.count, inBasket: inBasket)
    }

    /// A list with one line's tick changed (optimistic; the server write follows).
    static func setting(_ target: GroceryTarget, checked: Bool, in list: GroceryList) -> GroceryList {
        switch target {
        case .food(let id):
            let aisles = list.aisles.map { aisle in
                GroceryAisle(code: aisle.code, label: aisle.label, items: aisle.items.map { item in
                    guard item.foodItemId == id else { return item }
                    return GroceryItem(
                        foodItemId: item.foodItemId, name: item.name, qty: item.qty, unit: item.unit, buyCount: item.buyCount,
                        buyUnit: item.buyUnit, buyLabel: item.buyLabel, approxPieces: item.approxPieces, staple: item.staple,
                        toTaste: item.toTaste, approx: item.approx, excluded: item.excluded, uses: item.uses,
                        insteadOf: item.insteadOf, checked: checked, have: item.have
                    )
                })
            }
            return GroceryList(planId: list.planId, periodStart: list.periodStart, periodEnd: list.periodEnd, aisles: aisles, custom: list.custom)
        case .custom(let id):
            let custom = list.custom.map { item in
                item.id == id ? GroceryCustomItem(id: item.id, label: item.label, qtyText: item.qtyText, aisleCode: item.aisleCode, checked: checked) : item
            }
            return GroceryList(planId: list.planId, periodStart: list.periodStart, periodEnd: list.periodEnd, aisles: list.aisles, custom: custom)
        }
    }

    // MARK: Row text

    /// "Cherry tomatoes, 400 g". A line with no amount is just its name.
    static func line(_ item: GroceryItem, locale: Locale = .current) -> String {
        let qty = quantityLabel(item, locale: locale)
        return qty.isEmpty ? item.name : "\(item.name), \(qty)"
    }

    static func line(_ item: GroceryCustomItem) -> String {
        if let qty = item.qtyText?.nilIfEmpty { return "\(item.label), \(qty)" }
        return item.label
    }

    /// The small second line under a grocery row: "Mon, Thu lunch" is the server's context, we print the recipes
    /// it is for and, after a swap, what it replaces.
    static func context(_ item: GroceryItem) -> String? {
        var parts: [String] = []
        if let instead = item.insteadOf.first?.nilIfEmpty {
            parts.append(String(localized: "grocery.insteadOf", defaultValue: "instead of \(instead)"))
        }
        var seen = Set<String>()
        let recipes = item.uses.compactMap { $0.recipe?.nilIfEmpty }.filter { seen.insert($0).inserted }
        if !recipes.isEmpty { parts.append(recipes.prefix(2).joined(separator: ", ")) }
        if item.excluded { parts.append(String(localized: "grocery.excluded", defaultValue: "no longer fits your plan")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Export

    /// The sections of a shared copy: aisle by aisle in store order, then the member's own lines.
    /// `.stillToBuy` leaves out what is ticked or already at home, and any aisle that ends up empty.
    static func sections(_ list: GroceryList, scope: GroceryShareScope, locale: Locale = .current) -> [GroceryShareSection] {
        var out: [GroceryShareSection] = []
        for aisle in list.aisles {
            let items = scope == .whole ? aisle.items : aisle.items.filter(isToBuy)
            if items.isEmpty { continue }
            out.append(GroceryShareSection(title: aisle.label, lines: items.map { line($0, locale: locale) }))
        }
        let own = scope == .whole ? list.custom : list.custom.filter { !$0.checked }
        if !own.isEmpty {
            out.append(GroceryShareSection(title: String(localized: "grocery.own", defaultValue: "Your own items"), lines: own.map(line)))
        }
        return out
    }

    /// Number of lines a scope would share.
    static func lineCount(_ list: GroceryList, scope: GroceryShareScope) -> Int {
        sections(list, scope: scope).reduce(0) { $0 + $1.lines.count }
    }

    /// The plain-text list: a title, then each aisle in capitals with its lines. Reads well in Notes, Messages and Mail.
    static func text(_ list: GroceryList, scope: GroceryShareScope, title: String, locale: Locale = .current) -> String {
        var blocks: [String] = [title]
        for section in sections(list, scope: scope, locale: locale) {
            blocks.append(([section.title.uppercased(locale: locale)] + section.lines.map { "- \($0)" }).joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// "16–22 Nov" or "28 Nov – 4 Dec", from two `yyyy-MM-dd` keys.
    static func periodLabel(start: String?, end: String?, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let start, let s = PlanLogic.date(from: start, calendar: calendar) else { return nil }
        let day = Date.FormatStyle(locale: locale, calendar: calendar).day()
        let month = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated)
        guard let end, let e = PlanLogic.date(from: end, calendar: calendar), e != s else {
            return "\(s.formatted(day)) \(s.formatted(month))"
        }
        if calendar.component(.month, from: s) == calendar.component(.month, from: e) {
            return "\(s.formatted(day))–\(e.formatted(day)) \(e.formatted(month))"
        }
        return "\(s.formatted(day)) \(s.formatted(month)) – \(e.formatted(day)) \(e.formatted(month))"
    }
}

private extension String {
    func uppercased(locale: Locale) -> String { uppercased(with: locale) }
}
