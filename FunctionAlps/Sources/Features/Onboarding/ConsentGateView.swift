import SwiftUI

/// The blocking acceptance screen (the Expo `ConsentGate`): nothing in the app is reachable until every
/// `required` consent is ticked. Four properties, all legal rather than visual:
///   1. Nothing is pre-ticked — a pre-ticked mandatory box is not consent (`default_state` says so).
///   2. The full wording is on THIS screen, expandable in place.
///   3. A refusal of an optional item is RECORDED, so the ledger shows the member was asked and said no.
///   4. The 18+ declaration rides ON these terms rather than on a screen of its own (owner's call,
///      2026-09-18): accepting the Terms is the declaration. See the note above `AgeGateView`.
struct ConsentGateView: View {
    let bundle: AccountService.ConsentsBundle
    let onAccepted: () -> Void
    @Environment(AppDependencies.self) private var dependencies

    @State private var ticks: [String: Bool] = [:]
    @State private var expanded: Set<String> = []
    @State private var working = false
    @State private var saveError: String?

    private var groups: ConsentLogic.Groups { bundle.groups }
    /// A member who has agreed here before is not "starting" — the screen says what changed instead.
    private var isReAcceptance: Bool { ConsentLogic.isReAcceptance(bundle.consents) }
    private var untickedRequired: Int { groups.core.filter { !(ticks[$0.consentKey] ?? false) }.count }
    private var allRequiredTicked: Bool { untickedRequired == 0 }

    var body: some View {
        list
        .onAppear {
            // Required items start OFF, always; an optional one starts in the member's standing state.
            if ticks.isEmpty {
                for c in bundle.consents { ticks[c.consentKey] = c.required ? false : c.accepted }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ProfilePalette.accentSoft)
                        Image(systemName: isReAcceptance ? "arrow.triangle.2.circlepath" : "checkmark.shield").font(.system(size: 24, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(width: 54, height: 54).padding(.bottom, 18)
                    Text(isReAcceptance
                        ? String(localized: "gate.consent.updated.heading", defaultValue: "We have updated our terms")
                        : String(localized: "gate.consent.heading", defaultValue: "Before you start"))
                        .font(FATypography.display(27, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).padding(.bottom, 8)
                    Text(isReAcceptance
                        ? String(localized: "gate.consent.updated.intro", defaultValue: "The wording below has changed since you last agreed. The items marked as updated carry a new version — please read what is new and accept again to carry on. Nothing is ticked for you.")
                        : String(localized: "gate.consent.intro", defaultValue: "FunctionAlps handles your health data, so two things need your agreement — and two more are here for you to read. Tap any item to open it in full. Nothing is ticked for you."))
                        .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.bottom, 20)

                    if bundle.preview {
                        banner(String(localized: "consents.preview", defaultValue: "Preview build: this wording is still in legal review, so changes here are not recorded."))
                    }

                    label(String(localized: "gate.consent.required", defaultValue: "Required to use the app"))
                    ForEach(groups.core) { row in consentRow(row) }

                    if !bundle.notices.isEmpty {
                        label(String(localized: "gate.consent.notices", defaultValue: "Please read — nothing to agree to here"))
                        ForEach(bundle.notices) { n in noticeRow(n) }
                    }
                    if !groups.optional.isEmpty {
                        label(String(localized: "gate.consent.optional", defaultValue: "Optional — declining changes nothing"))
                        ForEach(groups.optional) { row in consentRow(row) }
                    }

                    Text(String(localized: "gate.consent.footnote", defaultValue: "You can review or withdraw these at any time in Privacy & Data."))
                        .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(5)
                        .frame(maxWidth: .infinity).padding(.top, 18)
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 24)
            }
            VStack(spacing: 6) {
                if let saveError {
                    Text(saveError).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).multilineTextAlignment(.center).lineSpacing(4)
                }
                ForestPillButton(
                    title: bundle.preview
                        ? String(localized: "gate.consent.ctaPreview", defaultValue: "Continue (preview)")
                        : String(localized: "gate.consent.cta", defaultValue: "Agree and continue"),
                    enabled: allRequiredTicked, busy: working
                ) { Task { await submit() } }
                if !allRequiredTicked {
                    Text(untickedRequired == 1
                        ? String(localized: "gate.consent.leftOne", defaultValue: "1 required item left to accept")
                        : String(localized: "gate.consent.leftMany", defaultValue: "\(untickedRequired) required items left to accept"))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                }
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
            .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
        }
        .faWall()
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted)
            .padding(.horizontal, 2).padding(.top, 14).padding(.bottom, 10)
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 14)).foregroundStyle(ProfilePalette.red).padding(.top, 1)
            Text(text).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(ProfilePalette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ProfilePalette.red.opacity(0.2), lineWidth: 1) }
        .padding(.bottom, 12)
    }

    private func toggleOpen(_ key: String) {
        withAnimation(.easeInOut(duration: 0.2)) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }
    }

    /// Hit the box (or its label) to decide; hit the chevron to read — two targets, so "I opened it
    /// to read" is never mistaken for "I agreed to it".
    private func consentRow(_ row: ConsentItem) -> some View {
        let checked = ticks[row.consentKey] ?? false
        let open = expanded.contains(row.consentKey)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button { ticks[row.consentKey] = !checked } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(checked ? FAColor.forestSoft : .clear)
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(checked ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 2)
                        if checked { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                    }
                    .frame(width: 22, height: 22).padding(.top, 1).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
                .accessibilityAddTraits(checked ? [.isSelected] : [])
                Button { ticks[row.consentKey] = !checked } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(row.title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            if ConsentLogic.isUpdate(row) { updatedChip(row.version) }
                        }
                        Text(row.summary).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    }
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { toggleOpen(row.consentKey) } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open
                    ? String(localized: "gate.consent.collapse", defaultValue: "Collapse \(row.title)")
                    : String(localized: "gate.consent.readFull", defaultValue: "Read \(row.title) in full"))
            }
            .padding(14)
            if open {
                LegalMarkdownView(markdown: row.bodyMd, hideTitle: true)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
                    .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
            }
        }
        .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(checked ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 1) }
        .padding(.bottom, 8)
    }

    /// Says in WORDS which items moved, and to which version — never colour alone, and never a bare
    /// unticked box that a returning member would read as the app having lost their answer.
    private func updatedChip(_ version: String) -> some View {
        (Text(String(localized: "gate.consent.updatedChip", defaultValue: "Updated")) + Text(" · " + version))
            .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.4).foregroundStyle(FAColor.forestSoft)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(ProfilePalette.accentSoft, in: Capsule())
            .fixedSize()
    }

    /// A notice is SHOWN, never ticked — still evidenced through `presented_keys`.
    private func noticeRow(_ n: LegalDocument) -> some View {
        let open = expanded.contains(n.consentKey)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggleOpen(n.consentKey) } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(ProfilePalette.accentSoft)
                        Image(systemName: "info").font(.system(size: 11, weight: .bold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(width: 22, height: 22).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        if let summary = n.summary {
                            Text(summary).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                        }
                    }
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                }
                .padding(14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                LegalMarkdownView(markdown: n.bodyMd, hideTitle: true)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
                    .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
            }
        }
        .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
        .padding(.bottom, 8)
    }

    /// One transaction: either the whole sitting lands or none of it does. Each decision carries the
    /// state its control ACTUALLY started in. Drafts are refused server-side, so preview records nothing.
    private func submit() async {
        guard allRequiredTicked, !working else { return }
        saveError = nil
        if bundle.preview { onAccepted(); return }
        working = true
        defer { working = false }
        let decisions = bundle.consents.map { c in
            ConsentDecision(key: c.consentKey, version: c.version, granted: ticks[c.consentKey] ?? false, defaultState: c.required ? false : c.accepted)
        }
        do {
            try await dependencies.account.recordGate(decisions, in: bundle)
            onAccepted()
        } catch {
            switch ConsentLogic.saveFailure(error) {
            case .draft:
                saveError = String(localized: "gate.consent.saveErrorDraft", defaultValue: "These terms are still in review and cannot be accepted yet. Please try again later.")
            case .connection:
                saveError = String(localized: "gate.consent.saveError", defaultValue: "We couldn't save your choices. Check your connection and try again.")
            case .notLinked:
                saveError = String(localized: "gate.consent.saveErrorNotLinked", defaultValue: "This sign-in isn't linked to your member record, so nothing could be saved. Sign out and sign in the way you first registered, or write to data@functionalps.ch.")
            case .other:
                saveError = String(localized: "gate.consent.saveErrorOther", defaultValue: "We couldn't save your choices just now. Please try again in a moment, or write to data@functionalps.ch.")
            }
        }
    }
}

// The age step is GONE from the app (owner's call, 2026-09-18). `AgeGateView` is deleted, not
// disabled: accepting the Terms is now the 18+ declaration, so a screen that asks the same question
// again is a second door on the same wall — and it was the door that locked two members out this week.
//
// Nothing else was torn out, so reinstating it is small and deliberate:
//   · `OnboardingLogic.checkBirthDate` (pure, tested) still holds the 18…120 rule;
//   · `AccountService.confirmAdult` / `.confirmAdultFromRecord` and their RPCs are still wired;
//   · the `gate.age.*` strings are still in the catalogue, in both languages;
//   · `MemberGateView` no longer has a `needsAge` step to pass in.
// It is NOT relocated into onboarding. The `age` field on the baseline screen is a different thing:
// a number Harris-Benedict needs, not a date of birth and not a gate.
//
// ⚠ Worth knowing while this stands: the English Terms v8 do not state the 18+ requirement (the French
// ones do, and both privacy notices do). The tick that records agreement is the Terms, so the English
// wording should carry it the next time that document is versioned.
