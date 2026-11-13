import Foundation

/// The plan screens' pure rules: slot mapping, which day is shown, which meal is next. No IO, no UI.
enum PlanLogic {
    /// The app groups planned meals by `MealLog.MealType`. The clinician's moments ("mid-morning snack",
    /// "afternoon_snack") fold into the five types; anything unknown is `.other`.
    static func mealType(_ raw: String?) -> MealLog.MealType {
        guard let text = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .other }
        if let exact = MealLog.MealType(rawValue: text) { return exact }
        if text.contains("breakfast") { return .breakfast }
        if text.contains("lunch") { return .lunch }
        if text.contains("dinner") || text.contains("supper") { return .dinner }
        if text.contains("snack") { return .snack }
        return .other
    }

    /// `yyyy-MM-dd` in the given calendar's zone.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The date a `yyyy-MM-dd` string names, at noon in the calendar's zone (noon survives DST shifts).
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return calendar.date(from: c)
    }

    /// Which day the Plan view opens on: the one the member picked if it still exists, else today, else the
    /// first day after today, else the first day there is. `today` is the SERVER's today (`MealPlanRange.from`).
    static func selectedDate(days: [PlanDay], today: String, preferred: String?) -> String? {
        let dates = days.map(\.date)
        if let preferred, dates.contains(preferred) { return preferred }
        if dates.contains(today) { return today }
        if let next = dates.sorted().first(where: { $0 >= today }) { return next }
        return dates.first
    }

    /// The meal "From your plan" offers: the first one of the day not yet eaten and still fitting the member.
    static func nextMeal(in day: PlanDay?) -> PlannedMeal? {
        day?.meals.first { !$0.isLogged && !$0.excluded }
    }

    /// Today's day in the range, if the plan covers it.
    static func todayDay(in range: MealPlanRange) -> PlanDay? {
        range.days.first { $0.date == range.from }
    }

    /// ("Tue", "17") for the day strip.
    static func stripLabel(for key: String, calendar: Calendar = .current, locale: Locale = .current) -> (weekday: String, number: String) {
        guard let date = date(from: key, calendar: calendar) else { return ("", key) }
        var cal = calendar
        cal.locale = locale
        let weekday = date.formatted(Date.FormatStyle(locale: locale, calendar: cal).weekday(.abbreviated))
        let number = String(cal.component(.day, from: date))
        return (weekday, number)
    }

    /// "Tue 17 Nov" for the day heading.
    static func dayHeading(for key: String, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date = date(from: key, calendar: calendar) else { return key }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "25 min" or nil.
    static func minutesLabel(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return String(localized: "plan.minutes", defaultValue: "\(minutes) min")
    }

    /// Portions ONE person eats, as a short label ("1 portion", "1.5 portions"); nil for the ordinary single portion.
    static func portionsLabel(_ portions: Double?) -> String? {
        guard let portions, abs(portions - 1) > 0.001 else { return nil }
        let text = portions == portions.rounded() ? String(Int(portions)) : String(format: "%.2g", portions)
        return String(localized: "plan.portions", defaultValue: "\(text) portions")
    }
}
