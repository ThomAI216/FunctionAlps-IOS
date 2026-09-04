import SwiftUI

/// "Privacy & data → Your consents" (the Expo `privacy-consents.tsx`): what the member agreed to and
/// what they can change. NOTHING is optimistic — a control moves only after CM OS confirmed the write,
/// and a failed change changes nothing.
struct ConsentsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var bundle: AccountService.ConsentsBundle?
    @State private var loadError = false
    @State private var saveError = false
    @State private var busyKey: String?
    @State private var expanded: Set<String> = []
    @State private var confirming: ConsentItem?
    @State private var showDelete = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: String(localized: "consents.heading", defaultValue: "Your consents"))
                Text(String(localized: "consents.heading", defaultValue: "Your consents")).font(FATypography.display(27, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).padding(.top, 6).padding(.bottom, 8)
                Text(String(localized: "consents.intro", defaultValue: "What you agreed to, and what you can change. Turning something off takes effect immediately and never affects what was lawful while it was on."))
                    .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.bottom, 18)

                if let bundle, bundle.preview { banner(String(localized: "consents.preview", defaultValue: "Preview build: this wording is still in legal review, so changes here are not recorded.")) }
                if saveError { banner(String(localized: "consents.saveError", defaultValue: "We couldn’t save that change. Nothing was altered — check your connection and try again.")) }

                if bundle == nil, !loadError {
                    ProgressView().tint(FAColor.forestSoft).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                if loadError {
                    VStack(spacing: 18) {
                        Text(String(localized: "consents.loadError", defaultValue: "We couldn’t load your consents. Check your connection and try again."))
                            .font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(5)
                        Button { Task { await load() } } label: {
                            Text(String(localized: "action.retry", defaultValue: "Try again")).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                                .padding(.horizontal, 28).padding(.vertical, 13).background(FAColor.forestSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }

                if let bundle {
                    let groups = bundle.groups
                    if groups.core.isEmpty, groups.optional.isEmpty {
                        SurfaceCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "consents.empty.title", defaultValue: "Nothing to manage yet")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Text(String(localized: "consents.empty.body", defaultValue: "These documents are still with our lawyers, so nothing has been recorded against your account. This page will list your consents once they are live."))
                                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                            }
                        }
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
                    }
                    if !groups.core.isEmpty { label(String(localized: "consents.core", defaultValue: "Required to use the app")) }
                    ForEach(groups.core) { row in consentCard(row) }
                    if !groups.optional.isEmpty { label(String(localized: "consents.optional", defaultValue: "Optional — change these freely")) }
                    ForEach(groups.optional) { row in consentCard(row) }
                    if !bundle.notices.isEmpty { label(String(localized: "consents.notices", defaultValue: "For information — nothing to agree to")) }
                    ForEach(bundle.notices) { n in noticeCard(n) }
                }

                Text(String(localized: "consents.footnote", defaultValue: "Every change is recorded with the date and the exact wording in force, so both of us can establish later what was agreed. Questions: data@functionalps.ch"))
                    .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(5)
                    .frame(maxWidth: .infinity).padding(.top, 20)
            }
            .padding(20)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        .confirmationDialog(
            String(localized: "consents.confirm.title", defaultValue: "Withdraw this consent?"),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "consents.confirm.cta", defaultValue: "Withdraw and disable the app"), role: .destructive) {
                if let row = confirming { confirming = nil; Task { await withdraw(row) } }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) { confirming = nil }
        } message: {
            Text(String(localized: "consents.confirm.body", defaultValue: "Processing your health data is what FunctionAlps is, so withdrawing switches the app off until you give it again. That is a consequence, not a penalty.\n\nYour data is not deleted by withdrawing. You can consent again and pick up where you left off, or delete your account to erase everything. If you want a copy first, export your data before you do either."))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted)
            .padding(.horizontal, 2).padding(.top, 16).padding(.bottom, 10)
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 14)).foregroundStyle(ProfilePalette.red).padding(.top, 1)
            Text(text).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProfilePalette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ProfilePalette.red.opacity(0.2), lineWidth: 1) }
        .padding(.bottom, 12)
    }

    private func toggleOpen(_ key: String) {
        withAnimation(.easeInOut(duration: 0.2)) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }
    }

    private func consentCard(_ row: ConsentItem) -> some View {
        let kind = ConsentLogic.manageKind(row)
        let open = expanded.contains(row.consentKey)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(row.accepted ? FAColor.forestSoft : .clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(row.accepted ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 2)
                    if row.accepted { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: 22, height: 22).padding(.top, 1)
                Button { toggleOpen(row.consentKey) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text((row.accepted ? String(localized: "consents.accepted", defaultValue: "Accepted") : String(localized: "consents.notAccepted", defaultValue: "Not accepted")) + " · " + row.version)
                            .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button { toggleOpen(row.consentKey) } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            VStack(alignment: .leading, spacing: 10) {
                if kind == .lockedCore {
                    Text(String(localized: "consents.locked", defaultValue: "The Terms are an agreement, not a consent, so there is nothing here to withdraw. If you no longer accept them, stop using the app and delete your account."))
                        .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                    Button { showDelete = true } label: {
                        Text(String(localized: "privacy.delete", defaultValue: "Delete my account")).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.red)
                    }
                    .buttonStyle(.plain)
                } else if busyKey == row.consentKey {
                    ProgressView().tint(FAColor.forestSoft)
                } else {
                    Button {
                        if row.accepted {
                            if ConsentLogic.withdrawalBlocksApp(row) { confirming = row } else { Task { await withdraw(row) } }
                        } else {
                            Task { await grant(row) }
                        }
                    } label: {
                        Text(row.accepted ? String(localized: "consents.withdraw", defaultValue: "Withdraw") : String(localized: "consents.grant", defaultValue: "Turn on"))
                            .font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                            .foregroundStyle(row.accepted ? ProfilePalette.red : FAColor.charcoal)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(row.accepted ? Color.clear : FAColor.forestSoft, in: Capsule())
                            .overlay { Capsule().strokeBorder(row.accepted ? ProfilePalette.red.opacity(0.35) : FAColor.forestSoft, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)

            if open {
                LegalMarkdownView(markdown: row.bodyMd, hideTitle: true)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
                    .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
            }
        }
        .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(row.accepted ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 1) }
        .padding(.bottom, 8)
    }

    private func noticeCard(_ n: LegalDocument) -> some View {
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
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                }
                .padding(14)
                .contentShape(Rectangle())
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

    // MARK: Data

    private func load() async {
        loadError = false
        do { bundle = try await dependencies.account.consents() } catch { bundle = nil; loadError = true }
    }

    /// Every write re-reads afterwards rather than patching local state.
    private func grant(_ row: ConsentItem) async {
        guard let bundle else { return }
        saveError = false
        busyKey = row.consentKey
        do { try await dependencies.account.grant(row, in: bundle); await load() } catch { saveError = true }
        busyKey = nil
    }

    private func withdraw(_ row: ConsentItem) async {
        saveError = false
        busyKey = row.consentKey
        do { try await dependencies.account.withdraw(row); await load() } catch { saveError = true }
        busyKey = nil
    }
}
