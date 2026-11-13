import SwiftUI

/// Today's focus on Home: the practice's offer for this morning, then what the member said the day is for.
/// Loading · error · no check-in yet · nothing to add · the offers — every state rendered (rule 5).
/// The headline, the line, the practitioner line and the habit chips are the server's own words (the matrix cell of
/// `member-daily-focus`, `habit_bank`); this card adds none. Tapping a chip opens the "pick one" sheet.
struct TodayFocusCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    /// The habit-choice sheet: which chip was tapped.
    @State private var sheet: FocusSheetRef?

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
            switch FocusCardLogic.state(today) {
            case .needsCheckin:
                checkinPrompt
            case .cell(let cell, let chips):
                cellCard(cell, chips: chips)
                    .sheet(item: $sheet) { ref in
                        FocusHabitSheet(chips: chips, firstId: ref.offerId)
                    }
                    #if DEBUG
                    .task {
                        // The showcase opens the habit-choice sheet over Home, as tapping the first chip would.
                        guard Showcase.screen == .focusSheet, let first = chips.first else { return }
                        try? await Task.sleep(for: .seconds(2.5))
                        sheet = FocusSheetRef(offerId: first.id)
                    }
                    #endif
            case .offersOnly(let lead, _):
                offers(today, lead: lead)
            case .nothing:
                FACard {
                    FAEmptyState(title: String(localized: "focus.empty.title", defaultValue: "Nothing to add today"),
                                 message: String(localized: "focus.empty.message", defaultValue: "Nothing in your morning called for a change. Carry on as you are."),
                                 systemImage: "sun.max")
                }
            }
        }
    }

    /// The matrix cell: headline and line in the card's tone, the practitioner line when it applies, the habit chips, and the
    /// kickoff routine on a hard morning.
    private func cellCard(_ cell: FocusCell, chips: [FocusOffer]) -> some View {
        let tone = cell.toneKind.accent
        return FACard {
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(tone).frame(width: 4).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "focus.title", defaultValue: "Today's focus").uppercased())
                        .font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cell.headline)
                            .font(FATypography.display(23, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(cell.line)
                            .font(FATypography.callout).foregroundStyle(FAColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let practitioner = cell.practitionerLine {
                            Text(practitioner)
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !chips.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(chips) { chip in
                                FocusChipRow(offer: chip, tone: tone) { sheet = FocusSheetRef(offerId: chip.id) }
                            }
                        }
                    }
                    if let kickoff = FocusCardLogic.kickoff(cell) {
                        FAButton(title: String(localized: "focus.kickoff.start", defaultValue: "Start the kickoff morning routine"), style: .secondary) {
                            router.push(.kickoff)
                        }
                        .accessibilityHint(kickoff.title)
                    }
                }
            }
        }
        .id("showcase.focus")
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
                        Text(String(localized: "focus.checkin.message", defaultValue: "A minute on last night and how you feel, and your focus appears here."))
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
            return String(localized: "focus.reason.readinessLow", defaultValue: "Your recovery is below your usual, so today's version is easier.")
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

// MARK: - The habit chips

/// Which chip opened the sheet (`habit_offers.id`) — `sheet(item:)` needs an identifiable value.
struct FocusSheetRef: Identifiable, Equatable {
    let offerId: String
    var id: String { offerId }
}

extension FocusTone {
    /// The card's accent: go with it · a step further · steady · pace yourself · hold steady.
    var accent: Color {
        switch self {
        case .go: FAColor.forestSoft
        case .peak: FAColor.streak
        case .soft: Color(hex: 0x8FA894)
        case .care: Color(hex: 0xC9A36A)
        case .rest: Color(hex: 0xB98C86)
        }
    }
}

/// One habit chip: its title in the practice's words; a tap opens the sheet. Done says so with a mark, not colour alone (rule 10).
private struct FocusChipRow: View {
    let offer: FocusOffer
    let tone: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: offer.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15)).foregroundStyle(offer.completed ? FAColor.brand : tone)
                    .accessibilityHidden(true)
                Text(offer.title)
                    .font(FATypography.sans(14, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous).strokeBorder(tone.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "focus.chip.hint", defaultValue: "Choose what to do now"))
    }
}

/// "Choose one" — the three (or fewer) habits of the focus, one picked, then "Do it now": the action opens the way every action does
/// (its card, with the two focus buttons under it).
struct FocusHabitSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let chips: [FocusOffer]
    @State private var selected: String

    init(chips: [FocusOffer], firstId: String) {
        self.chips = chips
        _selected = State(initialValue: firstId)
    }

    private var chosen: FocusOffer? { chips.first { $0.id == selected } ?? chips.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "focus.sheet.title", defaultValue: "Choose one for now"))
                .font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
            Text(String(localized: "focus.sheet.subtitle", defaultValue: "One small thing is enough."))
                .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
            VStack(spacing: 8) {
                ForEach(chips) { chip in option(chip) }
            }
            FAButton(title: String(localized: "focus.sheet.doNow", defaultValue: "Do it now")) {
                guard let cardId = chosen?.bankCardId else { return }
                dismiss()
                router.push(.focusCard(cardId))
            }
            .padding(.top, 4)
            if let chosen, !chosen.completed {
                FAButton(title: String(localized: "focus.sheet.alreadyDone", defaultValue: "I've already done this"), style: .tertiary) {
                    let focus = dependencies.focus
                    Task { await focus.setCompleted(chosen, true) }
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func option(_ chip: FocusOffer) -> some View {
        let on = chip.id == selected
        return Button { selected = chip.id } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18)).foregroundStyle(on ? FAColor.brand : FAColor.inkMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chip.title).font(FATypography.headline).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let detail = chip.description, !detail.isEmpty {
                        Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            .multilineTextAlignment(.leading).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? FAColor.forestGlow : Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous).strokeBorder(on ? FAColor.brand : FAColor.separator, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
