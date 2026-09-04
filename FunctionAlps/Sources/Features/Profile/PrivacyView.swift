import SwiftUI
import UIKit

/// Privacy & data (the Expo `profile-privacy.tsx`): the Swiss banner, what we collect & why, retention,
/// your rights (view · export · consents · DPO · delete), the legal links.
struct PrivacyView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var showDelete = false
    @State private var exportURL: URL?
    @State private var exporting = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: String(localized: "settings.privacy", defaultValue: "Privacy & data"))

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "privacy.banner.title", defaultValue: "Swiss Data Protection (nFADP)")).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "privacy.banner.body", defaultValue: "FunctionAlps is based in Switzerland and complies with the Federal Act on Data Protection (nFADP, revised 2023) and GDPR. Your health data never leaves Swiss or EU-compliant servers."))
                            .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                    }
                }
                .padding(16)
                .background(Color(hex: 0x4A8A5C, opacity: 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.3), lineWidth: 1) }
                .padding(.top, 6).padding(.bottom, 20)

                section(String(localized: "privacy.collect", defaultValue: "What we collect & why")) {
                    infoCard("eye", 0x3F7FC4, String(localized: "privacy.collect.health.title", defaultValue: "Health & nutrition data"), String(localized: "privacy.collect.health.body", defaultValue: "Meals, check-ins and the symptoms you log. Used only to mirror how your body responds to food · observations, never medical advice."))
                    infoCard("brain", 0xA98FD0, String(localized: "privacy.collect.ai.title", defaultValue: "AI analysis"), String(localized: "privacy.collect.ai.body", defaultValue: "Your data is sent · de-identified, with your name never attached · to Infomaniak's Swiss AI for analysis. It produces observations, not medical advice or diagnosis. AI is required for the app to work · you can manage your consent below."))
                    infoCard("person.2", 0x4A8A5C, String(localized: "privacy.collect.who.title", defaultValue: "Who sees your data"), String(localized: "privacy.collect.who.body", defaultValue: "Analysis is de-identified · your name is never attached. A wellness reviewer may see anonymised flags; your identity is revealed only with your explicit consent, and every access is logged. Never shared with advertisers or insurers. Ever."))
                    infoCard("server.rack", 0x4A8A5C, String(localized: "privacy.collect.storage.title", defaultValue: "Storage"), String(localized: "privacy.collect.storage.body", defaultValue: "Your data is stored encrypted on Supabase (EU data centre). You can request deletion at any time · all your data is erased within 30 days."))
                }

                section(String(localized: "privacy.retention", defaultValue: "Retention")) {
                    SurfaceCard {
                        VStack(spacing: 0) {
                            retentionRow(String(localized: "privacy.retention.logs", defaultValue: "Your logs"), String(localized: "privacy.retention.logs.value", defaultValue: "Kept while your account is active"), last: false)
                            retentionRow(String(localized: "privacy.retention.ai", defaultValue: "AI analysis outputs"), String(localized: "privacy.retention.ai.value", defaultValue: "12 months or until you delete"), last: false)
                            retentionRow(String(localized: "privacy.retention.after", defaultValue: "After account deletion"), String(localized: "privacy.retention.after.value", defaultValue: "All data erased within 30 days"), last: true)
                        }
                    }
                    .padding(.bottom, 8)
                }

                section(String(localized: "privacy.rights", defaultValue: "Your rights")) {
                    actionRow("eye", 0x3F7FC4, String(localized: "privacy.view", defaultValue: "View my data"), String(localized: "privacy.view.sub", defaultValue: "See everything we have stored about you")) { router.profilePath.append(.viewData) }
                    actionRow("arrow.down.circle", 0x4A8A5C, String(localized: "privacy.export", defaultValue: "Export my data"), exporting ? String(localized: "privacy.export.busy", defaultValue: "Preparing your file…") : String(localized: "privacy.export.sub", defaultValue: "Download a complete copy of your health data as JSON")) { Task { await export() } }
                    // GDPR Art. 7(3): withdrawal as easy as giving — the documents promise this row by name.
                    actionRow("lock", 0xA98FD0, String(localized: "privacy.consents", defaultValue: "Your consents"), String(localized: "privacy.consents.sub", defaultValue: "Review what you agreed to, and withdraw any of it")) { router.profilePath.append(.consents) }
                    actionRow("exclamationmark.circle", 0x4A8A5C, String(localized: "privacy.dpo", defaultValue: "Contact Data Protection Officer"), "data@functionalps.ch") {
                        if let url = URL(string: "mailto:data@functionalps.ch?subject=Data%20request") { openURL(url) }
                    }
                    actionRow("trash", 0xC0453A, String(localized: "privacy.delete", defaultValue: "Delete my account"), String(localized: "privacy.delete.sub", defaultValue: "Permanently erase all your data. This cannot be undone."), destructive: true) { showDelete = true }
                }

                VStack(spacing: 4) {
                    Text(String(localized: "privacy.footer.address", defaultValue: "FunctionAlps · Crans-Montana, Valais, Switzerland"))
                    HStack(spacing: 0) {
                        legalLink(String(localized: "legal.privacy", defaultValue: "Privacy Policy"), key: "privacy_policy")
                        Text("   ·   ")
                        legalLink(String(localized: "legal.terms", defaultValue: "Terms"), key: "terms_of_use")
                        Text("   ·   ")
                        legalLink(String(localized: "legal.notice", defaultValue: "Legal Notice"), key: "legal_notice")
                    }
                    Text(String(localized: "privacy.footer.compliant", defaultValue: "nFADP compliant · GDPR compliant"))
                }
                .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
                .presentationDetents([.medium, .large])
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted)
                .padding(.horizontal, 2).padding(.bottom, 10)
            content()
        }
        .padding(.bottom, 16)
    }

    private func infoCard(_ symbol: String, _ tint: UInt32, _ title: String, _ text: String) -> some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: tint, opacity: 0.13))
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: tint))
                }
                .frame(width: 32, height: 32).padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    Text(text).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func retentionRow(_ label: String, _ value: String, last: Bool) -> some View {
        HStack(alignment: .top) {
            Text(label).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
    }

    private func actionRow(_ symbol: String, _ tint: UInt32, _ title: String, _ subtitle: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SurfaceCard {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(destructive ? ProfilePalette.red.opacity(0.15) : Color(hex: tint, opacity: 0.13))
                        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(destructive ? ProfilePalette.red : Color(hex: tint))
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(destructive ? ProfilePalette.red : FAColor.ink)
                        Text(subtitle).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(3)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(destructive ? ProfilePalette.red.opacity(0.5) : ProfilePalette.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private func legalLink(_ title: String, key: String) -> some View {
        Button { router.profilePath.append(.legal(key)) } label: {
            Text(title).foregroundStyle(ProfilePalette.gold)
        }
        .buttonStyle(.plain)
    }

    /// The whole bundle as one JSON file, handed to the share sheet (Files, Mail, AirDrop…).
    private func export() async {
        guard !exporting, let member = try? await dependencies.members.currentMember() else { return }
        exporting = true
        let data = await dependencies.account.exportBundle(patientId: member.patientId)
        let name = "functionalps-data-\(Date().formatted(.iso8601.year().month().day())).json"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try? data.write(to: url, options: .atomic)
        exportURL = url
        exporting = false
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// `UIActivityViewController` for the data export.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
