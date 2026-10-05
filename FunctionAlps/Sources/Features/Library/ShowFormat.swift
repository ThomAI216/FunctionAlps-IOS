import Foundation

/// Readable show text — labels from the members web's `show.*` strings, dates always in the show's zone (Zurich),
/// assembled from parts ("Saturday 10 October", "Tue 6 Oct") so English and French read the way the dashboard does.
enum ShowFormat {
    /// The app's UI language as the API spells it.
    static var lang: String { (Bundle.main.preferredLocalizations.first ?? "en").lowercased().hasPrefix("fr") ? "fr" : "en" }

    private static var locale: Locale { Locale(identifier: lang == "fr" ? "fr_CH" : "en_GB") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: ShowLogic.defaultTimeZone)
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "Sat" / "sam."
    static func weekdayShort(_ d: Date) -> String { format(d, "EEE") }
    /// "10"
    static func dayNumber(_ d: Date) -> String { format(d, "d") }
    /// "Saturday 10 October" / "samedi 10 octobre"
    static func weekdayLong(_ d: Date) -> String { "\(format(d, "EEEE")) \(format(d, "d")) \(format(d, "MMMM"))" }
    /// "Tue 6 Oct"
    static func weekdayDayShort(_ d: Date) -> String { "\(format(d, "EEE")) \(format(d, "d")) \(format(d, "MMM"))" }
    /// "12:30"
    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: ShowLogic.defaultTimeZone)
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func trackLabel(_ track: ShowTrack?) -> String {
        guard let track else { return String(localized: "show.navGroup", defaultValue: "The show") }
        return switch track {
        case .movement: String(localized: "show.track.movement", defaultValue: "Movement")
        case .nutrition: String(localized: "show.track.nutrition", defaultValue: "Nutrition")
        case .sleep: String(localized: "show.track.sleep", defaultValue: "Sleep & recovery")
        case .mental: String(localized: "show.track.mental", defaultValue: "Mental wellbeing")
        case .intelligence: String(localized: "show.track.intelligence", defaultValue: "Health intelligence")
        case .cross: String(localized: "show.track.cross", defaultValue: "Cross-pillar")
        }
    }

    /// "Movement · Ep. 1" on a card, "Movement · Episode 1" on the episode page ("Live" for a live's replay).
    static func eyebrow(kind: ShowKind, track: ShowTrack?, number: Int?, long: Bool = false) -> String {
        let head = kind == .live ? String(localized: "show.stripLive", defaultValue: "Live") : trackLabel(track)
        guard let number else { return head }
        let n = long ? String(localized: "show.episodeN", defaultValue: "Episode \(number)") : String(localized: "show.epShort", defaultValue: "Ep. \(number)")
        return "\(head) · \(n)"
    }

    static func minutes(_ n: Int) -> String { String(localized: "show.minutes", defaultValue: "\(n) min") }

    static func pieces(_ n: Int) -> String {
        n == 1 ? String(localized: "show.onePiece", defaultValue: "1 piece") : String(localized: "show.pieces", defaultValue: "\(n) pieces")
    }

    /// "31 min · 5 pieces".
    static func cardMeta(_ card: ShowEpisodeCard) -> String {
        let count = ShowLogic.pieces(card.has, hasAudio: card.audioURL != nil).count
        var parts: [String] = []
        if let m = ShowLogic.durationMinutes(card.durationSeconds) { parts.append(minutes(m)) }
        if count > 0 { parts.append(pieces(count)) }
        return parts.joined(separator: " · ")
    }

    /// "Live tomorrow · 12:30" / "Live Saturday 10 October · 12:30".
    static func liveLabel(_ live: ShowSnapshot.Live) -> String {
        let time = clock(live.start)
        switch live.when {
        case .now: return String(localized: "show.liveNow", defaultValue: "Live now · \(time)")
        case .today: return String(localized: "show.liveToday", defaultValue: "Live today · \(time)")
        case .tomorrow: return String(localized: "show.liveTomorrow", defaultValue: "Live tomorrow · \(time)")
        case .later:
            let day = weekdayLong(live.start)
            return String(localized: "show.liveOn", defaultValue: "Live \(day) · \(time)")
        }
    }
}
