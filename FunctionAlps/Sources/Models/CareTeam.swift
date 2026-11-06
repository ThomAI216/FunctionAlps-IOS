import Foundation

/// One person on the member's care team (`member_care_team()`, CM OS migration 288): the practice's real people,
/// shown with their photo, name and title. Decoded straight from the RPC rows.
struct CareMember: Sendable, Equatable, Identifiable, Decodable {
    let userId: String
    let name: String
    let firstName: String?
    let title: String?
    let titleFr: String?
    /// A path such as `/booking/thomas.webp` (relative to the dashboard site) or an absolute URL.
    let photoPath: String?
    let assignmentType: String?
    let isPrimary: Bool?

    var id: String { userId }

    init(userId: String, name: String, firstName: String? = nil, title: String? = nil, titleFr: String? = nil,
         photoPath: String? = nil, assignmentType: String? = nil, isPrimary: Bool? = nil) {
        self.userId = userId
        self.name = name
        self.firstName = firstName
        self.title = title
        self.titleFr = titleFr
        self.photoPath = photoPath
        self.assignmentType = assignmentType
        self.isPrimary = isPrimary
    }
}

/// The member's care team, in the order the server returns it (the first member is who to show first).
/// Empty until migration 288 is applied or when the read fails: every screen then keeps today's wording.
struct CareTeam: Sendable, Equatable {
    var members: [CareMember]

    static let empty = CareTeam(members: [])

    var first: CareMember? { members.first }
    var isEmpty: Bool { members.isEmpty }
    /// The first member's first name, or nil while the team is unknown (callers fall back to "your nutritionist").
    var firstName: String? { first.map(CareTeamLogic.firstName) }
}

/// Pure presentation logic for the care team, kept out of the views so it can be tested.
enum CareTeamLogic {
    static let photoHost = "https://dashboard.functionalps.ch"

    private static func clean(_ text: String?) -> String? {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The first name: the server's `first_name`, else the first word of the full name.
    static func firstName(_ member: CareMember) -> String {
        if let first = clean(member.firstName) { return first }
        let name = clean(member.name) ?? ""
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// The title in the app's language: `title_fr` for French when there is one, else `title`; nil when neither.
    static func title(_ member: CareMember, french: Bool) -> String? {
        if french, let fr = clean(member.titleFr) { return fr }
        return clean(member.title) ?? (french ? nil : clean(member.titleFr))
    }

    /// True when the app is showing French.
    static func isFrench(_ preferredLocalization: String?) -> Bool {
        (preferredLocalization ?? "").lowercased().hasPrefix("fr")
    }

    /// The app's current language (the localization the bundle actually resolves, not the device region).
    static var appIsFrench: Bool { isFrench(Bundle.main.preferredLocalizations.first) }

    /// An absolute photo URL: a path is prefixed with the dashboard host, an absolute URL is left alone.
    static func photoURL(_ path: String?) -> URL? {
        guard let path = clean(path) else { return nil }
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") { return URL(string: path) }
        return URL(string: photoHost + (path.hasPrefix("/") ? path : "/" + path))
    }

    /// "TC" for "Thomas Convent"; one letter for a single name; empty for nothing.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { !$0.isEmpty }
        guard let first = words.first else { return "" }
        guard words.count > 1, let last = words.last else { return String(first.prefix(1)).uppercased() }
        return (String(first.prefix(1)) + String(last.prefix(1))).uppercased()
    }

    /// "2 hr. ago" / "yesterday" for the last-message line.
    static func whenLabel(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
