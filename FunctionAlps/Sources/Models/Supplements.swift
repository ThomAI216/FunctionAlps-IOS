import Foundation

// The member's supplements: what the practice prescribed, how regularly they were taken, and today's ticks.
// One server read (`member_supplements`, CM OS migration 333) returns every figure — the phone only formats
// (rule 9). Decoded with the app's snake_case decoder, so the keys below are the RPC's, camelCased.

/// The four moments a supplement is taken at, plus "any time". The wire values are the RPC's `moments[]`.
enum SupplementMoment: String, Sendable, Hashable, CaseIterable, Codable {
    case morning, noon, evening, bedtime, day

    /// Day order; "any time" last.
    static let order: [SupplementMoment] = [.morning, .noon, .evening, .bedtime, .day]
    /// The four moments with a reminder time (a reminder has no "any time").
    static let timed: [SupplementMoment] = [.morning, .noon, .evening, .bedtime]

    var rank: Int { Self.order.firstIndex(of: self) ?? Self.order.count }

    var displayName: String {
        switch self {
        case .morning: String(localized: "supp.moment.morning", defaultValue: "Morning")
        case .noon: String(localized: "supp.moment.noon", defaultValue: "Midday")
        case .evening: String(localized: "supp.moment.evening", defaultValue: "Evening")
        case .bedtime: String(localized: "supp.moment.bedtime", defaultValue: "Night")
        case .day: String(localized: "supp.moment.day", defaultValue: "Any time")
        }
    }

    /// "Taken this morning" / "Taken tonight" — the switch's label on the supplement page.
    var takenLabel: String {
        switch self {
        case .morning: String(localized: "supp.taken.morning", defaultValue: "Taken this morning")
        case .noon: String(localized: "supp.taken.noon", defaultValue: "Taken at midday")
        case .evening: String(localized: "supp.taken.evening", defaultValue: "Taken this evening")
        case .bedtime: String(localized: "supp.taken.bedtime", defaultValue: "Taken tonight")
        case .day: String(localized: "supp.taken.day", defaultValue: "Taken today")
        }
    }

    /// The reminder time a member who never set one gets (`patient_notification_preferences.supplement_times`).
    var defaultTime: String {
        switch self {
        case .morning: "08:00"
        case .noon: "12:30"
        case .evening: "19:00"
        case .bedtime, .day: "22:00"
        }
    }
}

/// How a supplement repeats.
enum SupplementDaysRule: String, Sendable, Equatable {
    case daily, alternate, weekdays
}

/// One supplement of the member's plan.
struct Supplement: Codable, Sendable, Equatable, Identifiable {
    /// What the member shares with the practice about the product (the practitioner decides, per supplement).
    struct ClientShare: Codable, Sendable, Equatable {
        var brand = false
        var composition = false
        var price = false
        var learnMore = false

        static let none = ClientShare()

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            brand = try c.decodeIfPresent(Bool.self, forKey: .brand) ?? false
            composition = try c.decodeIfPresent(Bool.self, forKey: .composition) ?? false
            price = try c.decodeIfPresent(Bool.self, forKey: .price) ?? false
            learnMore = try c.decodeIfPresent(Bool.self, forKey: .learnMore) ?? false
        }
        private enum Keys: String, CodingKey { case brand, composition, price, learnMore }
    }

    /// One moment of today: taken or not (and when).
    struct TodayEntry: Codable, Sendable, Equatable {
        var moment: String
        var taken: Bool
        var takenAt: Date?
    }

    /// One day of the observance strip (oldest first).
    struct StripDay: Codable, Sendable, Equatable, Identifiable {
        struct Entry: Codable, Sendable, Equatable {
            var moment: String
            var taken: Bool
        }
        var date: String
        var due: Bool
        var today: Bool
        var moments: [Entry]
        var id: String { date }

        init(date: String, due: Bool, today: Bool, moments: [Entry]) {
            self.date = date; self.due = due; self.today = today; self.moments = moments
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            date = try c.decode(String.self, forKey: .date)
            due = try c.decodeIfPresent(Bool.self, forKey: .due) ?? false
            today = try c.decodeIfPresent(Bool.self, forKey: .today) ?? false
            moments = try c.decodeIfPresent([Entry].self, forKey: .moments) ?? []
        }
        private enum Keys: String, CodingKey { case date, due, today, moments }
    }

    /// How regularly it was taken over the window the server counts (14 days). Numbers are the server's.
    struct Observance: Codable, Sendable, Equatable {
        var days: Int
        var due: Int
        var taken: Int
        /// 0…1, nil while nothing has been due yet.
        var pct: Double?
        /// `red` · `orange` · `blue` · `green` — an accent only; the words carry the meaning.
        var band: String?
        var strip: [StripDay]

        init(days: Int, due: Int, taken: Int, pct: Double?, band: String?, strip: [StripDay]) {
            self.days = days; self.due = due; self.taken = taken; self.pct = pct; self.band = band; self.strip = strip
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 0
            due = try c.decodeIfPresent(Int.self, forKey: .due) ?? 0
            taken = try c.decodeIfPresent(Int.self, forKey: .taken) ?? 0
            pct = try c.decodeIfPresent(Double.self, forKey: .pct)
            band = try c.decodeIfPresent(String.self, forKey: .band)
            strip = try c.decodeIfPresent([StripDay].self, forKey: .strip) ?? []
        }
        private enum Keys: String, CodingKey { case days, due, taken, pct, band, strip }
    }

    let id: String
    var carePlanItemId: String?
    var name: String
    var doseText: String?
    var unitsPerMoment: Double?
    var unit: String?
    /// The RPC's `moments[]` as sent; `slots` is the typed, ordered view.
    var moments: [String]
    var daysRule: String?
    var daysOfWeek: [Int]?
    var dueToday: Bool
    var howToTake: [String]?
    var why: String?
    /// `active` · `paused`.
    var status: String
    /// `YYYY-MM-DD`.
    var since: String?
    var prescriberName: String?
    var clientShare: ClientShare
    var brandLabel: String?
    var productUrl: String?
    var linkCheckedAt: Date?
    var today: [TodayEntry]
    var observance: Observance?

    // Not returned by the RPC yet — the page shows each block only when its value arrives, so they light up on
    // their own once the server sends them (owner, 2026-11-12: hidden when absent).
    /// "What it does in your body".
    var whatItDoes: String?
    /// The body areas it touches ("Nervous system", "Muscles"…), shown as chips under `whatItDoes`.
    var bodyAreas: [String]?
    /// "What's inside".
    var composition: String?
    /// "CHF 39.90".
    var priceText: String?
    /// "90 capsules · about 45 days".
    var packText: String?
    var imageUrl: String?
    var learnMoreUrl: String?

    init(id: String, carePlanItemId: String? = nil, name: String, doseText: String? = nil, unitsPerMoment: Double? = nil, unit: String? = nil,
         moments: [String] = [], daysRule: String? = "daily", daysOfWeek: [Int]? = nil, dueToday: Bool = true, howToTake: [String]? = nil,
         why: String? = nil, status: String = "active", since: String? = nil, prescriberName: String? = nil, clientShare: ClientShare = .none,
         brandLabel: String? = nil, productUrl: String? = nil, linkCheckedAt: Date? = nil, today: [TodayEntry] = [], observance: Observance? = nil) {
        self.id = id; self.carePlanItemId = carePlanItemId; self.name = name; self.doseText = doseText; self.unitsPerMoment = unitsPerMoment
        self.unit = unit; self.moments = moments; self.daysRule = daysRule; self.daysOfWeek = daysOfWeek; self.dueToday = dueToday
        self.howToTake = howToTake; self.why = why; self.status = status; self.since = since; self.prescriberName = prescriberName
        self.clientShare = clientShare; self.brandLabel = brandLabel; self.productUrl = productUrl; self.linkCheckedAt = linkCheckedAt
        self.today = today; self.observance = observance
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        carePlanItemId = try c.decodeIfPresent(String.self, forKey: .carePlanItemId)
        name = try c.decode(String.self, forKey: .name)
        doseText = try c.decodeIfPresent(String.self, forKey: .doseText)
        unitsPerMoment = try c.decodeIfPresent(Double.self, forKey: .unitsPerMoment)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        moments = try c.decodeIfPresent([String].self, forKey: .moments) ?? []
        daysRule = try c.decodeIfPresent(String.self, forKey: .daysRule)
        daysOfWeek = try c.decodeIfPresent([Int].self, forKey: .daysOfWeek)
        dueToday = try c.decodeIfPresent(Bool.self, forKey: .dueToday) ?? false
        howToTake = try c.decodeIfPresent([String].self, forKey: .howToTake)
        why = try c.decodeIfPresent(String.self, forKey: .why)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        since = try c.decodeIfPresent(String.self, forKey: .since)
        prescriberName = try c.decodeIfPresent(String.self, forKey: .prescriberName)
        clientShare = try c.decodeIfPresent(ClientShare.self, forKey: .clientShare) ?? .none
        brandLabel = try c.decodeIfPresent(String.self, forKey: .brandLabel)
        productUrl = try c.decodeIfPresent(String.self, forKey: .productUrl)
        linkCheckedAt = try c.decodeIfPresent(Date.self, forKey: .linkCheckedAt)
        today = try c.decodeIfPresent([TodayEntry].self, forKey: .today) ?? []
        observance = try c.decodeIfPresent(Observance.self, forKey: .observance)
        whatItDoes = try c.decodeIfPresent(String.self, forKey: .whatItDoes)
        bodyAreas = try c.decodeIfPresent([String].self, forKey: .bodyAreas)
        composition = try c.decodeIfPresent(String.self, forKey: .composition)
        priceText = try c.decodeIfPresent(String.self, forKey: .priceText)
        packText = try c.decodeIfPresent(String.self, forKey: .packText)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        learnMoreUrl = try c.decodeIfPresent(String.self, forKey: .learnMoreUrl)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(carePlanItemId, forKey: .carePlanItemId)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(doseText, forKey: .doseText)
        try c.encodeIfPresent(unitsPerMoment, forKey: .unitsPerMoment)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encode(moments, forKey: .moments)
        try c.encodeIfPresent(daysRule, forKey: .daysRule)
        try c.encodeIfPresent(daysOfWeek, forKey: .daysOfWeek)
        try c.encode(dueToday, forKey: .dueToday)
        try c.encodeIfPresent(howToTake, forKey: .howToTake)
        try c.encodeIfPresent(why, forKey: .why)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(since, forKey: .since)
        try c.encodeIfPresent(prescriberName, forKey: .prescriberName)
        try c.encode(clientShare, forKey: .clientShare)
        try c.encodeIfPresent(brandLabel, forKey: .brandLabel)
        try c.encodeIfPresent(productUrl, forKey: .productUrl)
        try c.encodeIfPresent(linkCheckedAt, forKey: .linkCheckedAt)
        try c.encode(today, forKey: .today)
        try c.encodeIfPresent(observance, forKey: .observance)
    }

    private enum Keys: String, CodingKey {
        case id, carePlanItemId, name, doseText, unitsPerMoment, unit, moments, daysRule, daysOfWeek, dueToday, howToTake, why, status, since
        case prescriberName, clientShare, brandLabel, productUrl, linkCheckedAt, today, observance
        case whatItDoes, bodyAreas, composition, priceText, packText, imageUrl, learnMoreUrl
    }

    // MARK: Derived

    var isActive: Bool { status != "paused" }
    var rule: SupplementDaysRule { daysRule.flatMap(SupplementDaysRule.init(rawValue:)) ?? .daily }

    /// The moments it is taken at, in day order; a supplement with none listed is taken "any time".
    var slots: [SupplementMoment] {
        let typed = Set(moments.compactMap(SupplementMoment.init(rawValue:)))
        return typed.isEmpty ? [.day] : typed.sorted { $0.rank < $1.rank }
    }

    func isTaken(_ moment: SupplementMoment) -> Bool {
        today.first { $0.moment == moment.rawValue }?.taken ?? false
    }

    func takenAt(_ moment: SupplementMoment) -> Date? {
        today.first { $0.moment == moment.rawValue }?.takenAt
    }

    /// A copy with one moment of today set (the optimistic update; the server's answer replaces it on the next read).
    func setting(_ moment: SupplementMoment, taken: Bool, at date: Date? = nil) -> Supplement {
        var copy = self
        if let i = copy.today.firstIndex(where: { $0.moment == moment.rawValue }) {
            copy.today[i].taken = taken
            copy.today[i].takenAt = taken ? date : nil
        } else {
            copy.today.append(TodayEntry(moment: moment.rawValue, taken: taken, takenAt: taken ? date : nil))
        }
        return copy
    }
}

/// `patient_notification_preferences.supplement_times` — the four reminder times, `HH:mm`.
struct SupplementTimes: Codable, Sendable, Equatable {
    var morning = SupplementMoment.morning.defaultTime
    var noon = SupplementMoment.noon.defaultTime
    var evening = SupplementMoment.evening.defaultTime
    var bedtime = SupplementMoment.bedtime.defaultTime

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func time(_ key: Keys, _ moment: SupplementMoment) throws -> String {
            NotificationPrefs.hhmm(try c.decodeIfPresent(String.self, forKey: key), fallback: moment.defaultTime)
        }
        morning = try time(.morning, .morning)
        noon = try time(.noon, .noon)
        evening = try time(.evening, .evening)
        bedtime = try time(.bedtime, .bedtime)
    }

    private enum Keys: String, CodingKey { case morning, noon, evening, bedtime }

    func time(for moment: SupplementMoment) -> String {
        switch moment {
        case .morning: morning
        case .noon: noon
        case .evening: evening
        case .bedtime, .day: bedtime
        }
    }

    mutating func set(_ time: String, for moment: SupplementMoment) {
        switch moment {
        case .morning: morning = time
        case .noon: noon = time
        case .evening: evening = time
        case .bedtime, .day: bedtime = time
        }
    }
}
