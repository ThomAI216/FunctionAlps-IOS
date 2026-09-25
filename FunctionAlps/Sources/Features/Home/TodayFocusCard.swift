import SwiftUI

/// Today's focus on Home: the practice's offer for this morning, then what the member said the day is for.
/// Loading · error · no check-in yet · nothing to add · the offers — every state rendered (rule 5).
/// The titles and descriptions are the practice's own words (`state_responses`, `habit_bank`); the only sentence
/// this card adds on its own is the owner-approved readiness line.
struct TodayFocusCard: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let focus = dependencies.focus
        switch focus.phase {
        case .idle, .loading:
            FACard {
                FALoadingState(message: String(localized: "focus.loading", defaultValue: "Finding today's focus…"))
                    .frame(minHeight: 110)
            }
        case .failed(let message):
            FACard {
                FAErrorState(title: String(localized: "focus.error.title", defaultValue: "Couldn't load today's focus"),
                             message: message) { Task { await focus.load() } }
            }
        case .loaded(let today):
            if today.needsCheckin {
                checkinPrompt
            } else if let lead = today.focus {
                offers(today, lead: lead)
            } else {
                FACard {
                    FAEmptyState(title: String(localized: "focus.empty.title", defaultValue: "Nothing to add today"),
                                 message: String(localized: "focus.empty.message", defaultValue: "Nothing in your morning called for a change — carry on as you are."),
                                 systemImage: "sun.max")
                }
            }
        }
    }

    /// No morning check-in yet: the focus is built from it, so the card is the way in.
    private var checkinPrompt: some View {
        NavigationLink(value: Route.checkin(.morning)) {
            FACard {
                HStack(spacing: 12) {
                    Image(systemName: "sun.horizon").font(.system(size: 22)).foregroundStyle(FAColor.brand)
                        .frame(width: 40, height: 40)
                        .background(FAColor.brand.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "focus.checkin.title", defaultValue: "Check in to get today's focus"))
                            .font(FATypography.headline).foregroundStyle(FAColor.ink)
                        Text(String(localized: "focus.checkin.message", defaultValue: "A minute on last night and what today is for — your focus appears here."))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(FAColor.inkSecondary).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func offers(_ today: TodayFocus, lead: FocusOffer) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "focus.title", defaultValue: "Today's focus").uppercased())
                        .font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4)
                    if let heading = lead.stateTitle {
                        Text(heading).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                OfferRow(offer: lead, prominent: true)
                if !today.alsoToday.isEmpty {
                    Divider().overlay(FAColor.separator)
                    Text(String(localized: "focus.also", defaultValue: "Also today").uppercased())
                        .font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4)
                    ForEach(today.alsoToday) { OfferRow(offer: $0, prominent: false) }
                }
            }
        }
    }
}

/// One offer: the practice's words, why it is here (when the reason is worth a sentence), and a done mark.
private struct OfferRow: View {
    @Environment(AppDependencies.self) private var dependencies
    let offer: FocusOffer
    let prominent: Bool

    private var accent: Color { offer.pillarValue.map { Color(hex: $0.hueHex) } ?? FAColor.brand }

    /// The one sentence the card writes itself — only for the owner-approved case (2026-09-25): made gentler
    /// because readiness is below the member's own baseline. A priority says what it serves; nothing else talks.
    private var because: String? {
        switch offer.reasonKind {
        case .readinessLow:
            return String(localized: "focus.reason.readinessLow", defaultValue: "Your recovery is below your usual — an easier version today.")
        case .priority:
            return offer.priority.map { String(localized: "focus.for", defaultValue: "For: \($0.label)") }
        default:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(accent).frame(width: 4).frame(maxHeight: .infinity).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(offer.title)
                    .font(prominent ? FATypography.title : FATypography.headline)
                    .foregroundStyle(offer.completed ? FAColor.inkSecondary : FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if prominent, let detail = offer.description, !detail.isEmpty {
                    Text(detail).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let because {
                    Text(because).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if offer.completed {
                    // Done says so in words, not only in colour (rule 10).
                    Label(String(localized: "focus.done", defaultValue: "Done"), systemImage: "checkmark")
                        .font(FATypography.caption).foregroundStyle(FAColor.brand)
                }
            }
            Spacer(minLength: 0)
            Button {
                let focus = dependencies.focus
                Task { await focus.setCompleted(offer, !offer.completed) }
            } label: {
                Image(systemName: offer.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: prominent ? 28 : 24))
                    .foregroundStyle(offer.completed ? FAColor.brand : FAColor.inkMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(offer.completed
                ? String(localized: "focus.a11y.done", defaultValue: "Done: \(offer.title)")
                : String(localized: "focus.a11y.markDone", defaultValue: "Mark as done: \(offer.title)"))
            .accessibilityAddTraits(offer.completed ? .isSelected : [])
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
