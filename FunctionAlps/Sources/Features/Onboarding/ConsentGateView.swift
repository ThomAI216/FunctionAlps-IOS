import SwiftUI

/// The blocking acceptance screen (the Expo `ConsentGate`): nothing in the app is reachable until every
/// `required` consent is ticked. Four properties, all legal rather than visual:
///   1. Nothing is pre-ticked — a pre-ticked mandatory box is not consent (`default_state` says so).
///   2. The full wording is on THIS screen, expandable in place.
///   3. A refusal of an optional item is RECORDED, so the ledger shows the member was asked and said no.
///   4. Age comes first: being an adult is what makes the agreement capable of binding.
struct ConsentGateView: View {
    let bundle: AccountService.ConsentsBundle
    let needsAge: Bool
    let onAccepted: () -> Void
    @Environment(AppDependencies.self) private var dependencies

    @State private var adultConfirmed = false
    @State private var ticks: [String: Bool] = [:]
    @State private var expanded: Set<String> = []
    @State private var working = false
    @State private var saveError: String?

    private var groups: ConsentLogic.Groups { bundle.groups }
    private var untickedRequired: Int { groups.core.filter { !(ticks[$0.consentKey] ?? false) }.count }
    private var allRequiredTicked: Bool { untickedRequired == 0 }

    var body: some View {
        Group {
            if needsAge, !adultConfirmed {
                AgeGateView { adultConfirmed = true }
            } else {
                list
            }
        }
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
                        Image(systemName: "checkmark.shield").font(.system(size: 24, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(width: 54, height: 54).padding(.bottom, 18)
                    Text(String(localized: "gate.consent.heading", defaultValue: "Before you start")).font(FATypography.display(27, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).padding(.bottom, 8)
                    Text(String(localized: "gate.consent.intro", defaultValue: "FunctionAlps handles your health data, so two things need your agreement — and two more are here for you to read. Tap any item to open it in full. Nothing is ticked for you."))
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
                        Text(row.title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
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
            let text = String(describing: error).lowercased()
            saveError = text.contains("not approved")
                ? String(localized: "gate.consent.saveErrorDraft", defaultValue: "These terms are still in review and cannot be accepted yet. Please try again later.")
                : String(localized: "gate.consent.saveError", defaultValue: "We couldn't save your choices. Check your connection and try again.")
        }
    }
}

/// The age step (the Expo `AgeGate`): shown once, before anything can be agreed to. An under-18 date
/// never leaves the device — `OnboardingLogic.checkBirthDate` decides locally. No skip, no dismiss:
/// the only exits are a confirmed adult date, or signing out.
struct AgeGateView: View {
    let onConfirmed: () -> Void
    @Environment(AppDependencies.self) private var dependencies
    @State private var day = ""
    @State private var month = ""
    @State private var year = ""
    @State private var working = false
    @State private var refused = false
    @State private var error: String?
    @FocusState private var focus: String?

    private var complete: Bool { !day.isEmpty && !month.isEmpty && !year.isEmpty }
    private var verdict: OnboardingLogic.AgeCheck { OnboardingLogic.checkBirthDate(day: day, month: month, year: year) }
    private var canContinue: Bool {
        if case .ok = verdict { return !working }
        return false
    }

    var body: some View {
        if refused {
            GateMessageView(
                symbol: "exclamationmark.triangle",
                title: String(localized: "gate.age.underAge", defaultValue: "FunctionAlps is only for people aged 18 and over."),
                message: String(localized: "gate.age.underAgeDetail", defaultValue: "We haven't kept the date you entered. If an account was created for someone under 18, write to data@functionalps.ch and we will delete it."),
                primary: String(localized: "profile.signOut", defaultValue: "Sign out"),
                onPrimary: { Task { await dependencies.auth.signOut() } }
            )
        } else {
            form
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ProfilePalette.accentSoft)
                        Image(systemName: "calendar").font(.system(size: 24, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(width: 54, height: 54).padding(.bottom, 18)
                    Text(String(localized: "gate.age.heading", defaultValue: "Your date of birth")).font(FATypography.display(27, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).padding(.bottom, 8)
                    Text(String(localized: "gate.age.intro", defaultValue: "FunctionAlps is for adults. We ask once, to confirm you are 18 or older and so the app's estimates fit your age."))
                        .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.bottom, 24)
                    HStack(spacing: 10) {
                        dateField(String(localized: "gate.age.day", defaultValue: "Day"), $day, id: "day", max: 2, placeholder: "DD").frame(maxWidth: .infinity)
                        dateField(String(localized: "gate.age.month", defaultValue: "Month"), $month, id: "month", max: 2, placeholder: "MM").frame(maxWidth: .infinity)
                        dateField(String(localized: "gate.age.year", defaultValue: "Year"), $year, id: "year", max: 4, placeholder: "YYYY").frame(maxWidth: .infinity).layoutPriority(1)
                    }
                    Text(String(localized: "gate.age.why", defaultValue: "Used only to confirm your age and to size the app's estimates. It is never shown to anyone else."))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 12)
                    // Recomputed as they type, but only SHOWN once the three fields are filled.
                    if complete, verdict == .invalid { fieldError(String(localized: "gate.age.invalid", defaultValue: "That date doesn't look right. Please check it.")) }
                    if complete, verdict == .underAge { fieldError(String(localized: "gate.age.underAge", defaultValue: "FunctionAlps is only for people aged 18 and over.")) }
                    if let error { fieldError(error) }
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack {
                ForestPillButton(title: String(localized: "action.continue", defaultValue: "Continue"), enabled: canContinue, busy: working) { Task { await confirm() } }
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
            .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
        }
        .faWall()
    }

    private func dateField(_ label: String, _ text: Binding<String>, id: String, max: Int, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(FATypography.sans(11, .semibold, relativeTo: .caption)).tracking(0.6).foregroundStyle(ProfilePalette.muted)
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .focused($focus, equals: id)
                .onChange(of: text.wrappedValue) { _, v in
                    let digits = String(v.filter(\.isNumber).prefix(max))
                    if digits != v { text.wrappedValue = digits }
                    if digits.count == max { focus = id == "day" ? "month" : (id == "month" ? "year" : nil) }
                }
                .font(FATypography.sans(17, relativeTo: .body)).foregroundStyle(FAColor.ink)
                .padding(.horizontal, 12).padding(.vertical, 13)
                .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focus == id ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 1.5) }
        }
    }

    private func fieldError(_ text: String) -> some View {
        Text(text).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 10)
    }

    /// The server decides (`confirm_member_adult`); false ⇒ refused and nothing else stored. Includes the
    /// RPC being absent: fail closed — an age check we could not run is not an age check that passed.
    private func confirm() async {
        guard case .ok(let iso) = verdict, !working else { return }
        error = nil
        working = true
        defer { working = false }
        do {
            if try await dependencies.account.confirmAdult(dateOfBirth: iso) { onConfirmed() } else { refused = true }
        } catch {
            self.error = String(localized: "gate.age.error", defaultValue: "We couldn't confirm your date of birth. Check your connection and try again.")
        }
    }
}
