import Foundation

/// The four states every network-backed screen renders (PRD §43).
enum Loadable<Value: Sendable & Equatable>: Sendable, Equatable {
    case loading
    case loaded(Value)
    case empty
    case failed(AppError)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
}

extension MealLog.MealType {
    var localizedName: String {
        switch self {
        case .breakfast: String(localized: "meal.type.breakfast", defaultValue: "Breakfast")
        case .lunch: String(localized: "meal.type.lunch", defaultValue: "Lunch")
        case .dinner: String(localized: "meal.type.dinner", defaultValue: "Dinner")
        case .snack: String(localized: "meal.type.snack", defaultValue: "Snack")
        case .other: String(localized: "meal.type.other", defaultValue: "Meal")
        }
    }
}

enum Format {
    static func kcal(_ value: Double) -> String {
        String(localized: "macros.kcal", defaultValue: "\(Int(value.rounded())) kcal")
    }
    static func grams(_ value: Double) -> String { "\(Int(value.rounded())) g" }
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
