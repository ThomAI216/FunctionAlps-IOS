import Foundation

/// One day's gut columns on `patient_daily_checkins` (v2 `gut_*` + the legacy stool markers).
struct GutDay: Sendable, Equatable {
    let day: String
    let comfort: Int?
    let stool: Int?
    let reactions: Int?
    let overall: Int?
    let stoolQuality: Int?
    let stoolFrequency: Int?
    let completedAt: Date?
}

/// Today's saved gut check-in, read back for editing (`gut_detail.answers` + `.notes`).
struct GutTodayRead: Sendable, Equatable {
    let answers: GutAnswerSet
    let notes: String?
    let completedAt: Date
    let day: GutDay
}

/// The gut save — the Expo `saveGutCheckinV2` row, every column explicit.
struct GutCheckinWrite: Sendable, Equatable {
    let comfort: Int?
    let stool: Int?
    let reactions: Int?
    let overall: Int?
    let answers: GutAnswerSet
    let notes: String?
    let stoolType: Int?
    let stoolQuality: Int?
    let stoolFrequency: Int?
    let completedAt: Date
}

/// A JSON value encoded with its keys VERBATIM (the request must be sent with `snakeCase: false`) —
/// `gut_detail` carries `reactionsScore` and `stool_off` side by side, and both must survive the trip.
indirect enum JSONValue: Sendable, Equatable, Encodable {
    case string(String), number(Double), int(Int), bool(Bool), null
    case array([JSONValue])
    case object([String: JSONValue])

    private struct RawKey: CodingKey {
        var stringValue: String; var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let s): var c = encoder.singleValueContainer(); try c.encode(s)
        case .number(let d): var c = encoder.singleValueContainer(); try c.encode(d)
        case .int(let i): var c = encoder.singleValueContainer(); try c.encode(i)
        case .bool(let b): var c = encoder.singleValueContainer(); try c.encode(b)
        case .null: var c = encoder.singleValueContainer(); try c.encodeNil()
        case .array(let a): var c = encoder.unkeyedContainer(); for v in a { try c.encode(v) }
        case .object(let o):
            var c = encoder.container(keyedBy: RawKey.self)
            for (k, v) in o.sorted(by: { $0.key < $1.key }) { try c.encode(v, forKey: RawKey(stringValue: k)) }
        }
    }

    /// From `JSONSerialization` output.
    static func from(_ any: Any?) -> JSONValue {
        switch any {
        case nil, is NSNull: return .null
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? .int(Int(d)) : .number(d)
        case let a as [Any]: return .array(a.map(from))
        case let o as [String: Any]: return .object(o.mapValues(from))
        default: return .null
        }
    }
}

enum GutDetailCodec {
    /// `{ answers: { comfort: {sliders, pills, specials}, … }, notes }` — the wrapped shape (functional_detail is flat).
    static func encode(answers: GutAnswerSet, notes: String?) -> JSONValue {
        var dims: [String: JSONValue] = [:]
        for key in GutDimKey.order {
            let a = answers[key] ?? .empty
            var specials: [String: JSONValue] = [:]
            if let b = a.specials.bristol { specials["bristol"] = .int(b) }
            if let f = a.specials.frequency { specials["frequency"] = .int(f) }
            if let r = a.specials.reactionsScore { specials["reactionsScore"] = .int(r) }
            dims[key.rawValue] = .object([
                "sliders": .object(a.sliders.mapValues { .number($0) }),
                "pills": .object(a.pills.mapValues { .array($0.map(JSONValue.string)) }),
                "specials": .object(specials),
            ])
        }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .object(["answers": .object(dims), "notes": (trimmed?.isEmpty ?? true) ? .null : .string(trimmed!)])
    }

    static func decode(_ detail: Any?) -> (answers: GutAnswerSet, notes: String?)? {
        guard let obj = detail as? [String: Any], let dims = obj["answers"] as? [String: Any] else { return nil }
        var out = GutAnswerSet.blank
        for key in GutDimKey.order {
            guard let d = dims[key.rawValue] as? [String: Any] else { continue }
            var a = GutAnswers()
            for (k, v) in (d["sliders"] as? [String: Any]) ?? [:] { if let n = v as? NSNumber { a.sliders[k] = n.doubleValue } }
            for (k, v) in (d["pills"] as? [String: Any]) ?? [:] { if let arr = v as? [String] { a.pills[k] = arr } }
            let sp = (d["specials"] as? [String: Any]) ?? [:]
            a.specials.bristol = (sp["bristol"] as? NSNumber)?.intValue
            a.specials.frequency = (sp["frequency"] as? NSNumber)?.intValue
            a.specials.reactionsScore = (sp["reactionsScore"] as? NSNumber)?.intValue
            out[key] = a
        }
        return (out, obj["notes"] as? String)
    }
}
