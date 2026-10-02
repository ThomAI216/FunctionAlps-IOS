import Foundation

// What the member can do before — and around — the plan the clinician writes (owner, 2026-10-02):
// until a care plan is published, the plan's areas stay blurred behind "Book your call" (or the date of the call
// already booked); meanwhile the member may add foundation actions from the practice's bank.

/// The member's own habit, added from the action bank: `self_initiated`, pointing at the card it came from.
/// Exactly the row RLS `habits_member_self_insert` allows (own patient, self_initiated).
struct OwnHabitInsert: Encodable, Sendable, Equatable {
    let patientId: String
    let title: String
    let description: String?
    let frequencyRule: String
    let slot: String?
    let pillar: String?
    let habitBankId: String
    var source = "self_initiated"
    var status = "active"
}

/// One `appointments` row the member may read (RLS: own, patient-visible).
struct AppointmentRow: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String?
    let startsAt: String
    let endsAt: String?
    let location: String?
    let meetingLink: String?
    let status: String?

    var start: Date? { ISO8601.parse(startsAt) }
    /// A video call (a meeting link) rather than at the practice.
    var isVideo: Bool { !(meetingLink ?? "").isEmpty }
}

enum PlanAccess {
    /// Where "Book your call" goes: the practice's welcome call, open to the whole team (owner's pick, 2026-10-02).
    static let bookingURL = URL(string: "https://www.functionalps.ch/book/onboarding")!

    /// The habit a member's own plan gets from a bank card, in the app's language.
    static func ownHabit(from card: ActionCardRow, patientId: String, locale: String, slot: HabitSlot?) -> OwnHabitInsert {
        OwnHabitInsert(
            patientId: patientId,
            title: ActionCardLogic.pick(card.title, card.titleFr, locale: locale) ?? card.title,
            description: ActionCardLogic.pick(card.description, card.descriptionFr, locale: locale),
            frequencyRule: card.frequencyRule?.trimmingCharacters(in: .whitespaces).isEmpty == false ? card.frequencyRule! : "FREQ=DAILY",
            slot: slot?.rawValue,
            pillar: card.pillar,
            habitBankId: card.id
        )
    }

    /// The member's active habit that came from this card, if they already have one.
    static func habit(for cardId: String, in plan: HabitPlan?) -> HabitRow? {
        plan?.habits.first { $0.habitBankId == cardId && $0.status != "cancelled" }
    }

    /// The bank by pillar, in the bank's own order, pillars in a stable order.
    static func bankByPillar(_ cards: [ActionCardRow]) -> [(pillar: String, cards: [ActionCardRow])] {
        var order: [String] = [], groups: [String: [ActionCardRow]] = [:]
        for card in cards {
            let pillar = card.pillar ?? "other"
            if groups[pillar] == nil { order.append(pillar) }
            groups[pillar, default: []].append(card)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// The bank's pillar names, in the app's language.
    static func pillarLabel(_ pillar: String) -> String {
        switch pillar {
        case "nutrition": String(localized: "bank.pillar.nutrition", defaultValue: "Nutrition")
        case "exercise": String(localized: "bank.pillar.exercise", defaultValue: "Movement")
        case "mind": String(localized: "bank.pillar.mind", defaultValue: "Mind")
        case "emotion": String(localized: "bank.pillar.emotion", defaultValue: "Emotions")
        case "recovery": String(localized: "bank.pillar.recovery", defaultValue: "Recovery")
        case "sleep": String(localized: "bank.pillar.sleep", defaultValue: "Sleep")
        default: String(localized: "bank.pillar.other", defaultValue: "Foundations")
        }
    }
}
