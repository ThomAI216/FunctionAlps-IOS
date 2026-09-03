import SwiftUI

/// Semantic colour tokens. Hex values come from the Expo app's single source of
/// truth `lib/theme/tokens.ts` (see docs/audit/app-screens.md §4). Change values
/// only here; views use the semantic names.
enum FAColor {
    // Brand family (forest / cream / gold / charcoal / stone)
    static let forest = Color(hex: 0x2E5438)
    static let forestSoft = Color(hex: 0x4A8A5C)     // tokens.forestS — the working accent
    static let forestMist = Color(hex: 0xC8D9CC)     // tokens.forestM
    static let forestGlow = Color(hex: 0xEDF4EF)     // tokens.forestG
    static let forestDark = Color(hex: 0x16301F)
    static let cream = Color(hex: 0xF5F0E8)
    static let cream2 = Color(hex: 0xEDE8DE)
    static let warm = Color(hex: 0xFAF7F2)           // opaque reading surface (light)
    static let gold = Color(hex: 0xC48B35)           // retired in-app; PDF only
    static let goldSoft = Color(hex: 0xD4A84E)
    static let charcoal = Color(hex: 0x1A1A16)
    static let charcoal2 = Color(hex: 0x14140F)
    static let ink2 = Color(hex: 0x252521)
    static let stone = Color(hex: 0x7A796F)
    static let stoneLight = Color(hex: 0xA8A79E)

    // Semantic aliases used by components
    static let brand = forest
    static let accent = forestSoft
    static let background = cream                    // default "Sage" wall reads as cream/sage
    static let surface = Color.white.opacity(0.72)   // glass-card fill on light walls
    static let surfaceOpaque = warm
    static let surfaceMuted = cream2
    static let separator = Color(hex: 0x1A1A16, opacity: 0.08)
    static let ink = charcoal
    static let inkSecondary = stone
    static let inkMuted = stoneLight

    // Locked macro palette (app-wide)
    static let kcal = Color(hex: 0x2A3B34)
    static let protein = Color(hex: 0xE0654F)
    static let carbs = Color(hex: 0xE8A23D)
    static let fat = Color(hex: 0x6C8AE4)

    // Per-meal food-score colours
    static let scoreInflammation = Color(hex: 0xD98A2B)
    static let scoreGlycemic = Color(hex: 0x3F7FC4)
    static let scoreDigestion = Color(hex: 0x4A8A5C)

    // 5-level functional scale, low → high
    static let scale: [Color] = [
        Color(hex: 0xC0453A), Color(hex: 0xD98A2B), Color(hex: 0xD4A84E), Color(hex: 0x3F7FC4), Color(hex: 0x4A8A5C),
    ]

    // Signals (never the only carrier of status — pair with text/icon, PRD §50)
    static let success = forestSoft
    static let warning = Color(hex: 0xD98A2B)
    static let danger = Color(hex: 0xC0453A)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
