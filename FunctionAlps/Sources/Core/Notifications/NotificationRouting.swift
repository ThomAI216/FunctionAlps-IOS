import Foundation

/// Where a tapped notification belongs when its push carries no `route`. CM OS's own pushes set
/// `data_json.route` (`notify_member_push`); CLINICAL's `notifyPatient` writes content-free pointers instead
/// (`data_json.items[{kind, …}]`), so the kind decides. Pure and tested.
enum NotificationRouting {
    /// The day-7 summary of the Foundation Track.
    static let trackSummary = "functionalps://foundation/summary"

    /// The row's own app route wins; else the first item kind the app has a page for; else nil (the tap just opens
    /// the app, as before).
    static func route(data: JSONValue?) -> URL? {
        guard case .object(let o)? = data else { return nil }
        if let raw = o["route"]?.stringValue, let url = URL(string: raw), url.scheme == "functionalps" { return url }
        if case .array(let items)? = o["items"] {
            for item in items {
                guard case .object(let i) = item else { continue }
                if i["kind"]?.stringValue == "track_summary" { return URL(string: trackSummary) }
                // A bank resource shared with the member: its kb_nodes slug opens the library reader (`library/<slug>`,
                // NOT `library/show/<slug>`, which is a show episode). Older rows carry no `route`; this covers them.
                if i["kind"]?.stringValue == "bank_resource", let slug = i["slug"]?.stringValue, let url = libraryRoute(slug: slug) { return url }
            }
        }
        return nil
    }

    /// `functionalps://library/<slug>` for a kb_nodes slug (content words, digits, `-` and `_`); nil for anything else.
    static func libraryRoute(slug: String) -> URL? {
        let slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard slug.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "functionalps://library/\(slug)")
    }
}
