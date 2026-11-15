import Foundation

/// The Foundational week's pure rules: where it shows, which photo URLs are safe, how a day's meals group, how a nominal day is named.
enum FoundationalWeek {
    /// Where the example week shows for a member.
    enum Placement: Equatable, Sendable {
        /// No delivered plan: Plan and Groceries show the example under the "an example of how your plan will look" banner.
        case replacesPlan
        /// A delivered plan: their own plan stays on Plan and Groceries; the example opens from its own entry.
        case entryOnly
    }

    /// `hasDeliveredPlan` is `member_plan_recipe_ids()` returning at least one id (delivered, approved, not hidden, any dates).
    /// nil = the check failed: the member's own screens stay as they were, with the entry still available.
    static func placement(hasDeliveredPlan: Bool?) -> Placement { hasDeliveredPlan == false ? .replacesPlan : .entryOnly }

    /// Only `https://` photos are ever loaded.
    static func imageURL(_ raw: String?) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// A day's meals in order, with the snack options folded into one "one or the other" group.
    enum Group: Equatable, Sendable {
        case single(PlannedMeal)
        case snackChoice([PlannedMeal])
    }

    static func groups(_ meals: [PlannedMeal]) -> [Group] {
        let options = meals.filter { $0.mealType == .snack && $0.optionLabel != nil }
        var out: [Group] = []
        var placed = false
        for meal in meals {
            if meal.mealType == .snack, meal.optionLabel != nil, options.count > 1 {
                if !placed { out.append(.snackChoice(options)); placed = true }
            } else {
                out.append(.single(meal))
            }
        }
        return out
    }

    /// "Monday" for the nominal date 2001-01-01. nil when the key is not a date.
    static func weekday(for key: String, abbreviated: Bool = false, locale: Locale = .current) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        guard let date = PlanLogic.date(from: key, calendar: cal) else { return nil }
        let style = Date.FormatStyle(locale: locale, calendar: cal)
        return date.formatted(abbreviated ? style.weekday(.abbreviated) : style.weekday(.wide))
    }
}
