import Foundation
import SwiftUI

/// The four body signals of the functional check-in, as the scores hub and its detail pages show them —
/// the Expo `health-details.ts` entries (energy / sleep / mood / stress) with their French overlay. Every
/// value on iOS is already 0–100, higher = better (`DailyCheckin`); "Stress" carries CALMNESS, exactly what
/// the Expo `mountain(value, invert)` produced.
enum BodySignal: String, CaseIterable, Sendable, Hashable, Identifiable {
    case energy, sleep, mood, stress
    var id: String { rawValue }

    struct Item: Sendable, Identifiable { let title: String; let body: String; var id: String { title } }

    var title: String {
        switch self {
        case .energy: String(localized: "signal.energy.title", defaultValue: "Energy")
        case .sleep: String(localized: "signal.sleep.title", defaultValue: "Sleep")
        case .mood: String(localized: "signal.mood.title", defaultValue: "Mood")
        case .stress: String(localized: "signal.stress.title", defaultValue: "Stress")
        }
    }
    var subtitle: String {
        switch self {
        case .energy: String(localized: "signal.energy.subtitle", defaultValue: "How steady and usable your output feels")
        case .sleep: String(localized: "signal.sleep.subtitle", defaultValue: "How rested and recovered you feel")
        case .mood: String(localized: "signal.mood.subtitle", defaultValue: "Emotional steadiness, resilience, and outlook")
        case .stress: String(localized: "signal.stress.subtitle", defaultValue: "Load, pressure, and recovery capacity")
        }
    }
    var tint: Color {
        switch self {
        case .energy: Color(hex: 0xD97706)
        case .sleep: Color(hex: 0x6366F1)
        case .mood: Color(hex: 0xDB2777)
        case .stress: Color(hex: 0xE11D48)
        }
    }
    var insight: String {
        switch self {
        case .energy: String(localized: "signal.energy.insight", defaultValue: "Energy is where nutrition becomes visible")
        case .sleep: String(localized: "signal.sleep.insight", defaultValue: "Sleep drives the rest of the dashboard")
        case .mood: String(localized: "signal.mood.insight", defaultValue: "Mood is where recovery becomes personal")
        case .stress: String(localized: "signal.stress.insight", defaultValue: "Stress is a multiplier, not an isolated score")
        }
    }
    var explanation: String {
        switch self {
        case .energy: String(localized: "signal.energy.explanation", defaultValue: "Energy reflects how usable your output feels, not just how awake you are. Stronger energy usually means food, recovery, and daily load are working together instead of competing.")
        case .sleep: String(localized: "signal.sleep.explanation", defaultValue: "Sleep is your recovery foundation. When sleep is deeper and more consistent, energy, stress resilience, digestion, and overall stability usually improve with it.")
        case .mood: String(localized: "signal.mood.explanation", defaultValue: "Mood reflects how emotionally steady, resilient, and flexible the day feels. It is often shaped by sleep, stress, digestion, and energy more than by one isolated event.")
        case .stress: String(localized: "signal.stress.explanation", defaultValue: "Stress is a load signal. When stress climbs, it tends to amplify digestive sensitivity, reduce emotional flexibility, and make energy less stable across the day.")
        }
    }
    /// "What influences it" — three levers.
    var focusAreas: [Item] {
        switch self {
        case .energy: [
            Item(title: String(localized: "signal.energy.focus0.title", defaultValue: "Protein first"), body: String(localized: "signal.energy.focus0.body", defaultValue: "A stronger protein anchor early in the day often smooths out hunger and energy swings.")),
            Item(title: String(localized: "signal.energy.focus1.title", defaultValue: "Stable blood sugar"), body: String(localized: "signal.energy.focus1.body", defaultValue: "Big peaks and crashes usually feel like low energy, even when calories are technically adequate.")),
            Item(title: String(localized: "signal.energy.focus2.title", defaultValue: "Recovery versus output"), body: String(localized: "signal.energy.focus2.body", defaultValue: "If output keeps climbing while recovery stays flat, energy debt accumulates fast.")),
        ]
        case .sleep: [
            Item(title: String(localized: "signal.sleep.focus0.title", defaultValue: "Wind-down consistency"), body: String(localized: "signal.sleep.focus0.body", defaultValue: "Keep the hour before bed quieter and dimmer so your nervous system can downshift properly.")),
            Item(title: String(localized: "signal.sleep.focus1.title", defaultValue: "Morning light"), body: String(localized: "signal.sleep.focus1.body", defaultValue: "Getting daylight early anchors circadian rhythm and makes evening sleep pressure stronger.")),
            Item(title: String(localized: "signal.sleep.focus2.title", defaultValue: "Late caffeine cutoff"), body: String(localized: "signal.sleep.focus2.body", defaultValue: "A firm cutoff earlier in the afternoon often improves sleep depth more than people expect.")),
        ]
        case .mood: [
            Item(title: String(localized: "signal.mood.focus0.title", defaultValue: "Recovery load"), body: String(localized: "signal.mood.focus0.body", defaultValue: "Mood usually gets more fragile when sleep debt and daily pressure pile up at the same time.")),
            Item(title: String(localized: "signal.mood.focus1.title", defaultValue: "Food stability"), body: String(localized: "signal.mood.focus1.body", defaultValue: "Regular meals with enough protein and fewer crashes often make mood feel steadier across the day.")),
            Item(title: String(localized: "signal.mood.focus2.title", defaultValue: "Small lifts"), body: String(localized: "signal.mood.focus2.body", defaultValue: "Light movement, daylight, and social contact can all shift mood more reliably than waiting to feel better first.")),
        ]
        case .stress: [
            Item(title: String(localized: "signal.stress.focus0.title", defaultValue: "Short resets"), body: String(localized: "signal.stress.focus0.body", defaultValue: "Two or three intentional breath or walking breaks often change the whole shape of a day.")),
            Item(title: String(localized: "signal.stress.focus1.title", defaultValue: "Calendar load"), body: String(localized: "signal.stress.focus1.body", defaultValue: "Back-to-back commitments can quietly keep your system in a higher-alert state for hours.")),
            Item(title: String(localized: "signal.stress.focus2.title", defaultValue: "Evening decompression"), body: String(localized: "signal.stress.focus2.body", defaultValue: "A calmer evening improves both stress recovery and the next night of sleep.")),
        ]
        }
    }
    /// "How it connects" — the other signals, in the Expo order.
    var connections: [Item] {
        switch self {
        case .energy: [
            Item(title: String(localized: "signal.ctx.digestion", defaultValue: "Digestion"), body: String(localized: "signal.energy.ctx0", defaultValue: "If digestion is unsettled, energy often feels less steady even before symptoms become obvious.")),
            Item(title: String(localized: "signal.ctx.inflammation", defaultValue: "Inflammation"), body: String(localized: "signal.energy.ctx1", defaultValue: "Higher inflammatory load can make energy feel heavier, slower, and less reliable.")),
            Item(title: String(localized: "signal.mood.title", defaultValue: "Mood"), body: String(localized: "signal.energy.ctx2", defaultValue: "Low or unstable energy often drags mood down because everything feels more effortful.")),
            Item(title: String(localized: "signal.sleep.title", defaultValue: "Sleep"), body: String(localized: "signal.energy.ctx3", defaultValue: "Sleep quality still shapes the ceiling of how strong and stable energy can feel.")),
            Item(title: String(localized: "signal.stress.title", defaultValue: "Stress"), body: String(localized: "signal.energy.ctx4", defaultValue: "Stress can burn through energy by pushing the system into output mode without enough recovery.")),
        ]
        case .sleep: [
            Item(title: String(localized: "signal.ctx.digestion", defaultValue: "Digestion"), body: String(localized: "signal.sleep.ctx0", defaultValue: "A restless night often makes digestion feel more reactive and less forgiving the next day.")),
            Item(title: String(localized: "signal.ctx.inflammation", defaultValue: "Inflammation"), body: String(localized: "signal.sleep.ctx1", defaultValue: "Poor sleep can amplify inflammatory noise even when food choices are reasonable.")),
            Item(title: String(localized: "signal.mood.title", defaultValue: "Mood"), body: String(localized: "signal.sleep.ctx2", defaultValue: "Mood usually becomes less resilient when recovery is shallow or inconsistent.")),
            Item(title: String(localized: "signal.energy.title", defaultValue: "Energy"), body: String(localized: "signal.sleep.ctx3", defaultValue: "Energy is often the first place poor sleep becomes visible in the day.")),
            Item(title: String(localized: "signal.stress.title", defaultValue: "Stress"), body: String(localized: "signal.sleep.ctx4", defaultValue: "When sleep drops, the same daily load often feels much heavier than usual.")),
        ]
        case .mood: [
            Item(title: String(localized: "signal.ctx.digestion", defaultValue: "Digestion"), body: String(localized: "signal.mood.ctx0", defaultValue: "A more irritated gut can quietly lower mood by making the day feel physically harder to move through.")),
            Item(title: String(localized: "signal.ctx.inflammation", defaultValue: "Inflammation"), body: String(localized: "signal.mood.ctx1", defaultValue: "Higher inflammatory load often makes mood feel flatter, heavier, or less resilient.")),
            Item(title: String(localized: "signal.energy.title", defaultValue: "Energy"), body: String(localized: "signal.mood.ctx2", defaultValue: "When energy is steady, mood usually feels more flexible and easier to protect.")),
            Item(title: String(localized: "signal.sleep.title", defaultValue: "Sleep"), body: String(localized: "signal.mood.ctx3", defaultValue: "Sleep is one of the strongest levers for emotional steadiness across the whole day.")),
            Item(title: String(localized: "signal.stress.title", defaultValue: "Stress"), body: String(localized: "signal.mood.ctx4", defaultValue: "Stress and mood move together quickly, especially when recovery is already stretched.")),
        ]
        case .stress: [
            Item(title: String(localized: "signal.ctx.digestion", defaultValue: "Digestion"), body: String(localized: "signal.stress.ctx0", defaultValue: "Stress often shows up in digestion quickly through tightness, discomfort, or symptom flares.")),
            Item(title: String(localized: "signal.ctx.inflammation", defaultValue: "Inflammation"), body: String(localized: "signal.stress.ctx1", defaultValue: "Higher stress can make the whole system feel more reactive, especially when recovery is already low.")),
            Item(title: String(localized: "signal.mood.title", defaultValue: "Mood"), body: String(localized: "signal.stress.ctx2", defaultValue: "When pressure stays high, mood usually gets flatter, more fragile, or less resilient.")),
            Item(title: String(localized: "signal.energy.title", defaultValue: "Energy"), body: String(localized: "signal.stress.ctx3", defaultValue: "Stress can make energy feel jagged by pulling attention and recovery in too many directions at once.")),
            Item(title: String(localized: "signal.sleep.title", defaultValue: "Sleep"), body: String(localized: "signal.stress.ctx4", defaultValue: "A busy nervous system at night often turns into lighter sleep and weaker recovery.")),
        ]
        }
    }

    func value(in checkin: DailyCheckin) -> Int? {
        switch self {
        case .energy: checkin.energy
        case .sleep: checkin.sleep
        case .mood: checkin.mood
        case .stress: checkin.calmness
        }
    }
}

/// The three gut sub-scores (the Expo `GUT_EDUCATION`): what it is, what raises it, what lowers it.
enum GutSignal: String, CaseIterable, Sendable, Hashable, Identifiable {
    case comfort, stool, reactions
    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfort: String(localized: "gutSignal.comfort.title", defaultValue: "Digestion comfort")
        case .stool: String(localized: "gutSignal.stool.title", defaultValue: "Stool quality & regularity")
        case .reactions: String(localized: "gutSignal.reactions.title", defaultValue: "Post-meal reactions")
        }
    }
    var short: String {
        switch self {
        case .comfort: String(localized: "gutSignal.comfort.short", defaultValue: "Comfort")
        case .stool: String(localized: "gutSignal.stool.short", defaultValue: "Stool")
        case .reactions: String(localized: "gutSignal.reactions.short", defaultValue: "Reactions")
        }
    }
    var subtitle: String {
        switch self {
        case .comfort: String(localized: "gutSignal.comfort.subtitle", defaultValue: "How easy your gut feels through the day")
        case .stool: String(localized: "gutSignal.stool.subtitle", defaultValue: "Form and rhythm · a window on transit")
        case .reactions: String(localized: "gutSignal.reactions.subtitle", defaultValue: "How meals sit in the hours after")
        }
    }
    var tint: Color {
        switch self {
        case .comfort: Color(hex: 0x14B8A6)
        case .stool: Color(hex: 0xA78BFA)
        case .reactions: Color(hex: 0xF59E0B)
        }
    }
    var whatItIs: String {
        switch self {
        case .comfort: String(localized: "gutSignal.comfort.what", defaultValue: "Your lived experience of gut ease · little bloating, pain, or heaviness. It is the headline of your gut check-in, the subjective read of how settled your digestion feels.")
        case .stool: String(localized: "gutSignal.stool.what", defaultValue: "Stool form (Bristol type, ideal 3-4) and regularity (around 1-3 a day). Together they reflect transit time and gut motility · how smoothly things move through.")
        case .reactions: String(localized: "gutSignal.reactions.what", defaultValue: "How your meals feel afterwards · felt comfort minus any bloating, gas, or fullness in the hours after eating. It is your fastest food-sensitivity signal.")
        }
    }
    var raises: [String] {
        switch self {
        case .comfort: [
            String(localized: "gutSignal.comfort.up0", defaultValue: "Foods you tolerate well"), String(localized: "gutSignal.comfort.up1", defaultValue: "Steady meal timing"),
            String(localized: "gutSignal.comfort.up2", defaultValue: "Hydration"), String(localized: "gutSignal.comfort.up3", defaultValue: "Gentle movement"),
            String(localized: "gutSignal.comfort.up4", defaultValue: "Lower mealtime stress"),
        ]
        case .stool: [
            String(localized: "gutSignal.stool.up0", defaultValue: "Fibre from plants"), String(localized: "gutSignal.stool.up1", defaultValue: "Hydration"),
            String(localized: "gutSignal.stool.up2", defaultValue: "Regular meals"), String(localized: "gutSignal.stool.up3", defaultValue: "Daily movement"),
        ]
        case .reactions: [
            String(localized: "gutSignal.reactions.up0", defaultValue: "Foods you tolerate"), String(localized: "gutSignal.reactions.up1", defaultValue: "Right-sized portions"),
            String(localized: "gutSignal.reactions.up2", defaultValue: "Slow, calm eating"), String(localized: "gutSignal.reactions.up3", defaultValue: "Chewing well"),
        ]
        }
    }
    var lowers: [String] {
        switch self {
        case .comfort: [
            String(localized: "gutSignal.comfort.down0", defaultValue: "Trigger or FODMAP foods"), String(localized: "gutSignal.comfort.down1", defaultValue: "Large or late meals"),
            String(localized: "gutSignal.comfort.down2", defaultValue: "Stress & poor sleep"), String(localized: "gutSignal.comfort.down3", defaultValue: "Eating in a rush"),
        ]
        case .stool: [
            String(localized: "gutSignal.stool.down0", defaultValue: "Low fibre"), String(localized: "gutSignal.stool.down1", defaultValue: "Dehydration"),
            String(localized: "gutSignal.stool.down2", defaultValue: "Very high-fat meals"), String(localized: "gutSignal.stool.down3", defaultValue: "Stress & travel"),
        ]
        case .reactions: [
            String(localized: "gutSignal.reactions.down0", defaultValue: "Trigger / FODMAP foods"), String(localized: "gutSignal.reactions.down1", defaultValue: "Oversized portions"),
            String(localized: "gutSignal.reactions.down2", defaultValue: "Rushed or stressed meals"), String(localized: "gutSignal.reactions.down3", defaultValue: "Very fatty or fried food"),
        ]
        }
    }

    func value(in day: GutDay) -> Int? {
        switch self {
        case .comfort: day.comfort
        case .stool: day.stool
        case .reactions: day.reactions
        }
    }
}

/// The tile status (the Expo `statusFor`): ≥ 67 strong, ≥ 34 steady, else a weak spot; no value reads as steady.
enum ScoreStatus: Sendable, Equatable {
    case good, watch, bad

    static func of(_ value: Int?) -> ScoreStatus {
        guard let value else { return .watch }
        if value >= 67 { return .good }
        if value >= 34 { return .watch }
        return .bad
    }
    var label: String {
        switch self {
        case .good: String(localized: "score.status.good", defaultValue: "Strong")
        case .watch: String(localized: "score.status.watch", defaultValue: "Steady")
        case .bad: String(localized: "score.status.bad", defaultValue: "Weak spot")
        }
    }
    var color: Color {
        switch self {
        case .good: Color(hex: 0x4A8A5C)
        case .watch: Color(hex: 0xC2A24A)
        case .bad: Color(hex: 0xDB5A4B)
        }
    }
}

/// "Reading the bands" — the five bands every 0–100 score shares.
enum ScoreBands {
    struct Band: Sendable, Identifiable { let color: Color; let label: String; let range: String; var id: String { range } }
    static var all: [Band] {
        [
            Band(color: Color(hex: 0x4A8A5C), label: String(localized: "score.band.thriving", defaultValue: "Thriving"), range: "80–100"),
            Band(color: Color(hex: 0x4F86C6), label: String(localized: "score.band.good", defaultValue: "Good baseline"), range: "60–80"),
            Band(color: Color(hex: 0xE2BE3A), label: String(localized: "score.band.mixed", defaultValue: "Mixed"), range: "40–60"),
            Band(color: Color(hex: 0xE08A3C), label: String(localized: "score.band.sub", defaultValue: "Sub-optimal"), range: "20–40"),
            Band(color: Color(hex: 0xDB5A4B), label: String(localized: "score.band.attention", defaultValue: "Needs attention"), range: "0–20"),
        ]
    }
}
