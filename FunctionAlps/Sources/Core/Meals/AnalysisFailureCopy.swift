import Foundation

/// The human sentence for a stalled meal (the Expo `analysisFailureCopy`). `analysis_last_error` is an upstream
/// diagnostic — a Deno stack, a 502 from a Geneva GPU — read ONLY to pick which sentence to show, never rendered.
/// Calm on purpose: at `needs_input` the pipeline has not failed the member, it has run out of guesses and is
/// asking a question they can answer in four seconds.
enum AnalysisFailureCopy {
    enum Kind: Sendable, Equatable { case busy, unreadable, offline, unknown }

    private static let busy = try! NSRegularExpression(pattern: #"\b(429|503|504|rate.?limit|too many requests|timed? ?out|timeout|overload|capacity|hang)\b"#, options: [.caseInsensitive])
    private static let unreadable = try! NSRegularExpression(pattern: #"\b(unreadable|not a food|no food|invalid image|decode|corrupt|unsupported)\b"#, options: [.caseInsensitive])
    private static let offline = try! NSRegularExpression(pattern: #"\b(network|econnreset|enotfound|fetch failed|connection (refused|reset|closed)|socket)\b"#, options: [.caseInsensitive])

    private static func test(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Bucket the upstream error so the copy can be specific without quoting it. Order matters: a hang reports
    /// as both a timeout and a socket error, and "we were busy" is the truer, less alarming of the two.
    static func classify(_ raw: String?) -> Kind {
        guard let raw, !raw.isEmpty else { return .unknown }
        if test(busy, raw) { return .busy }
        if test(offline, raw) { return .offline }
        if test(unreadable, raw) { return .unreadable }
        return .unknown
    }

    struct Copy: Sendable, Equatable { let title: String; let body: String }

    static func copy(status: MealLog.AnalysisStatus, rawError: String?) -> Copy {
        let kind = classify(rawError)
        if status != .failed {
            return Copy(
                title: String(localized: "capture.needsInput.title", defaultValue: "We couldn’t read this one · what did you eat?"),
                body: kind == .busy
                    ? String(localized: "capture.needsInput.busy", defaultValue: "Our nutrition service was busy just now. Say or type the meal and we’ll take it from there · this is faster anyway.")
                    : String(localized: "capture.needsInput.body", defaultValue: "Say it or type it, however you’d describe it to a friend. We’ll do the rest.")
            )
        }
        return Copy(
            title: String(localized: "capture.failed.title2", defaultValue: "We couldn’t read this photo."),
            body: kind == .unreadable
                ? String(localized: "capture.failed.unreadable", defaultValue: "The picture didn’t give us enough to go on. Tell us what was on the plate and the meal is logged just the same.")
                : String(localized: "capture.failed.body", defaultValue: "Tell us what was on the plate and the meal is logged just the same.")
        )
    }
}
