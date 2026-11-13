import Foundation

/// One approved row of `signal_explanations` (migration `20261111090000_signal_explanations.sql`): the practice's own
/// explanation of a check-in signal, in one language. Practice-curated and clinician-reviewed content — the app renders
/// it and NEVER writes or invents any of it (CLAUDE.md rule 6). `signal` is `sleep · energy · focus · mood · stress ·
/// digestion · score`.
///
/// Decoded with `JSON.decode` (snake_case keys → camelCase). Decoding is tolerant: a missing optional field is nil or
/// empty, and a malformed element of an array is dropped, never the whole page — a block with nothing in it is hidden.
struct SignalExplanation: Decodable, Sendable, Equatable, Identifiable {
    let signal: String
    let locale: String
    let version: Int
    let content: Content

    var id: String { signal }

    /// The columns the app reads — Core/API only (rule 2).
    static let columns = "signal,locale,version,content"

    init(signal: String, locale: String, version: Int, content: Content) {
        self.signal = signal; self.locale = locale; self.version = version; self.content = content
    }

    /// The newest version per signal (rows may hold several versions of the same signal and language).
    static func newestPerSignal(_ rows: [SignalExplanation]) -> [String: SignalExplanation] {
        var newest: [String: SignalExplanation] = [:]
        for row in rows {
            if let held = newest[row.signal], held.version >= row.version { continue }
            newest[row.signal] = row
        }
        return newest
    }

    // MARK: The content

    struct Content: Decodable, Sendable, Equatable {
        var title = ""
        var whatItIs = ""
        var feelsHigh = ""
        var feelsLow = ""
        /// The chip word for each end (default High / Low): Stress says Calm / High stress, Digestion Good / Poor.
        var feelsHighLabel: String?
        var feelsLowLabel: String?
        /// The short text on the Trends row's "What influences it".
        var cardText = ""
        var influencesIntro: String?
        var influences: [Influence] = []
        var connectionsIntro: String?
        var connections: [Connection] = []
        var actions: [Action] = []
        /// Energy only: "What's on your plate".
        var plateIntro: String?
        var plate: [PlateItem] = []
        var plateRule: PlateRule?
        var safetyLine: String?
        var sources: [String] = []

        init() {}

        private enum CodingKeys: String, CodingKey {
            case title, whatItIs, feelsHigh, feelsLow, feelsHighLabel, feelsLowLabel, cardText, influencesIntro, influences
            case connectionsIntro, connections, actions, plateIntro, plate, plateRule, safetyLine, sources
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = c.text(.title) ?? ""
            whatItIs = c.text(.whatItIs) ?? ""
            feelsHigh = c.text(.feelsHigh) ?? ""
            feelsLow = c.text(.feelsLow) ?? ""
            feelsHighLabel = c.text(.feelsHighLabel)
            feelsLowLabel = c.text(.feelsLowLabel)
            cardText = c.text(.cardText) ?? ""
            influencesIntro = c.text(.influencesIntro)
            influences = c.lossy(Influence.self, .influences)
            connectionsIntro = c.text(.connectionsIntro)
            connections = c.lossy(Connection.self, .connections)
            actions = c.lossy(Action.self, .actions)
            plateIntro = c.text(.plateIntro)
            plate = c.lossy(PlateItem.self, .plate)
            plateRule = try? c.decodeIfPresent(PlateRule.self, forKey: .plateRule)
            safetyLine = c.text(.safetyLine)
            sources = c.lossy(String.self, .sources).compactMap { $0.nilIfBlank }
        }

        /// A row with no explanation in it is not worth a page: the app shows nothing rather than an empty one.
        var isUsable: Bool { !whatItIs.isEmpty || !influences.isEmpty }
    }

    /// One thing that moves the signal. `icon` names a glyph the app knows; an unknown name shows a neutral one.
    struct Influence: Decodable, Sendable, Equatable {
        var icon: String
        var line: String
        var why: String
        var evidence: String

        init(icon: String = "", line: String, why: String = "", evidence: String = "") {
            self.icon = icon; self.line = line; self.why = why; self.evidence = evidence
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            line = try c.decode(String.self, forKey: .line)
            icon = c.text(.icon) ?? ""
            why = c.text(.why) ?? ""
            evidence = c.text(.evidence) ?? ""
        }

        private enum Keys: String, CodingKey { case icon, line, why, evidence }
    }

    /// One arrow of the mini map: `direction` is read from THIS signal's side (`out` = it moves `to`, `in` = `to`
    /// moves it, `both` = each moves the other).
    struct Connection: Decodable, Sendable, Equatable {
        var to: String
        var direction: String
        var label: String
        var evidence: String

        init(to: String, direction: String = "out", label: String = "", evidence: String = "") {
            self.to = to; self.direction = direction; self.label = label; self.evidence = evidence
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            to = try c.decode(String.self, forKey: .to)
            direction = c.text(.direction) ?? "out"
            label = c.text(.label) ?? ""
            evidence = c.text(.evidence) ?? ""
        }

        private enum Keys: String, CodingKey { case to, direction, label, evidence }
    }

    /// One easy way to influence the signal. `habitHint` is matched to a card of the action bank, never to a habit
    /// the app makes up.
    struct Action: Decodable, Sendable, Equatable {
        var text: String
        var habitHint: String?

        init(text: String, habitHint: String? = nil) { self.text = text; self.habitHint = habitHint }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            text = try c.decode(String.self, forKey: .text)
            habitHint = c.text(.habitHint)
        }

        private enum Keys: String, CodingKey { case text, habitHint }
    }

    /// Energy only: carbs · protein · fat · fibre.
    struct PlateItem: Decodable, Sendable, Equatable {
        var key: String
        var title: String
        var line: String
        var evidence: String

        init(key: String, title: String, line: String, evidence: String = "") {
            self.key = key; self.title = title; self.line = line; self.evidence = evidence
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            title = try c.decode(String.self, forKey: .title)
            line = try c.decode(String.self, forKey: .line)
            key = c.text(.key) ?? ""
            evidence = c.text(.evidence) ?? ""
        }

        private enum Keys: String, CodingKey { case key, title, line, evidence }
    }

    struct PlateRule: Decodable, Sendable, Equatable {
        var title: String
        var line: String
        var evidence: String

        init(title: String, line: String, evidence: String = "") { self.title = title; self.line = line; self.evidence = evidence }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            title = c.text(.title) ?? ""
            line = try c.decode(String.self, forKey: .line)
            evidence = c.text(.evidence) ?? ""
        }

        private enum Keys: String, CodingKey { case title, line, evidence }
    }
}

// MARK: Tolerant decoding helpers

/// An array element that fails to decode becomes nil instead of failing the array.
private struct Lossy<Element: Decodable>: Decodable {
    let value: Element?
    init(from decoder: any Decoder) throws { value = try? Element(from: decoder) }
}

private extension KeyedDecodingContainer {
    /// A trimmed, non-empty string, or nil (missing, null, the wrong type, or blank).
    func text(_ key: Key) -> String? {
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return raw.nilIfBlank
    }

    /// The array under `key`, minus any element that does not decode; missing or malformed → empty.
    func lossy<Element: Decodable>(_ type: Element.Type, _ key: Key) -> [Element] {
        ((try? decode([Lossy<Element>].self, forKey: key)) ?? []).compactMap(\.value)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
