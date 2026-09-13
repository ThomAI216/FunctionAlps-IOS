import Foundation

/// `JSONDecoder.convertFromSnakeCase` rewrites DICTIONARY keys too, so a `micronutrient_totals` jsonb
/// (`vitamin_c_mg`, `saturated_fat_g`) comes off the wire as `vitaminCMg` / `saturatedFatG` — and every lookup by
/// column name misses. Decoders run their `[String: Double]` maps through here, so the app always holds the
/// backend's own keys whatever the decoder did to them. Idempotent: a key already in snake_case is untouched.
enum SnakeKeys {
    static func snake(_ key: String) -> String {
        var out = ""
        out.reserveCapacity(key.count + 4)
        for ch in key {
            if ch.isUppercase {
                if !out.isEmpty, out.last != "_" { out.append("_") }
                out.append(contentsOf: ch.lowercased())
            } else {
                out.append(ch)
            }
        }
        return out
    }

    static func normalise(_ map: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        out.reserveCapacity(map.count)
        for (k, v) in map { out[snake(k)] = v }
        return out
    }
}
