import SwiftUI

/// Settings → Devices → Apple Health & Apple Watch. The phone is the connection: Apple Health already
/// holds what the Watch (and any device that syncs into Health) recorded, so one permission sheet
/// covers them all. Other wearables (Garmin, Oura, Fitbit…) link through the web app for now.
struct WearablesView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var days: [WearableDay] = []
    @State private var connections: [WearableConnectionRow] = []
    @State private var member: Member?
    /// nil while the current Privacy Notice is being read; false = the approved notice predates wearable data.
    @State private var disclosed: Bool?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmDisconnect = false

    private var service: WearableService { dependencies.wearables }

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "wearables.title", defaultValue: "Wearables"))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "wearables.intro", defaultValue: "Connect a wearable to bring your steps, sleep, heart rate and recovery into FunctionAlps automatically."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5).padding(.bottom, 18)

                    appleHealthCard

                    if service.isConnected {
                        SettingsSectionLabel(title: String(localized: "wearables.recent", defaultValue: "Last 14 days"))
                        recentCard
                    }

                    SettingsSectionLabel(title: String(localized: "wearables.reads", defaultValue: "What we read"))
                    FACard {
                        VStack(alignment: .leading, spacing: 9) {
                            readRow("figure.walk", String(localized: "wearables.read.activity", defaultValue: "Steps, distance, active energy, exercise minutes and workouts"))
                            readRow("bed.double", String(localized: "wearables.read.sleep", defaultValue: "Sleep: in bed, asleep, deep, REM, awake and interruptions"))
                            readRow("heart", String(localized: "wearables.read.heart", defaultValue: "Heart rate, resting heart rate, heart-rate variability (SDNN)"))
                            readRow("lungs", String(localized: "wearables.read.breath", defaultValue: "Breathing rate, blood oxygen, VO₂ max and weight"))
                            Text(String(localized: "wearables.read.note", defaultValue: "Read-only. Nothing is written back to Health, and you can turn any type off in Settings → Health → Data Access & Devices → FunctionAlps."))
                                .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 4)
                        }
                    }

                    SettingsSectionLabel(title: String(localized: "wearables.others", defaultValue: "Other devices"))
                    FACard {
                        VStack(alignment: .leading, spacing: 6) {
                            if otherConnections.isEmpty {
                                Text(String(localized: "wearables.others.title", defaultValue: "Garmin, Oura, Fitbit, Withings, Strava, Polar")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Text(String(localized: "wearables.others.body", defaultValue: "These link through the FunctionAlps web app for now. Once linked there, their data shows up here too."))
                                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                            } else {
                                ForEach(otherConnections, id: \.dataSourceId) { c in
                                    HStack {
                                        Text(c.dataSourceName ?? "#\(c.dataSourceId)").font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                        Spacer()
                                        Text(c.status == "connected" ? String(localized: "wearables.connected", defaultValue: "Connected") : (c.status ?? "")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(c.status == "connected" ? FAColor.forestSoft : ProfilePalette.muted)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .confirmationDialog(String(localized: "wearables.disconnect.confirm", defaultValue: "Stop syncing Apple Health?"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(String(localized: "wearables.disconnect", defaultValue: "Disconnect"), role: .destructive) { Task { await service.disconnect() } }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "wearables.disconnect.body", defaultValue: "This phone stops sending new readings. What was already synced stays in your record; to revoke Health access itself, use Settings → Health."))
        }
    }

    // MARK: Apple Health card

    private var appleHealthCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xFF2D55, opacity: 0.14))
                        Image(systemName: "heart.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: 0xFF2D55))
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "wearables.apple.title", defaultValue: "Apple Health & Apple Watch")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        Text(statusLine).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(service.isConnected ? FAColor.forestSoft : ProfilePalette.muted)
                    }
                    Spacer(minLength: 0)
                }
                if !WearableService.isAvailable {
                    Text(String(localized: "wearables.unavailable", defaultValue: "Apple Health isn't available on this device."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).padding(.top, 12)
                } else if service.isConnected {
                    HStack(spacing: 8) {
                        Button { Task { await service.sync(); await load() } } label: {
                            HStack(spacing: 6) {
                                if service.state == .syncing { ProgressView().tint(FAColor.charcoal).scaleEffect(0.8) } else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .bold)) }
                                Text(service.state == .syncing ? String(localized: "wearables.syncing", defaultValue: "Syncing…") : String(localized: "wearables.syncNow", defaultValue: "Sync now"))
                                    .font(FATypography.sans(12.5, .bold, relativeTo: .caption))
                            }
                            .foregroundStyle(FAColor.charcoal)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(FAColor.forestSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(service.state == .syncing)
                        Button { confirmDisconnect = true } label: {
                            Text(String(localized: "wearables.disconnect", defaultValue: "Disconnect"))
                                .font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(ProfilePalette.red)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .overlay { Capsule().strokeBorder(ProfilePalette.red.opacity(0.35), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 14)
                } else {
                    Text(String(localized: "wearables.apple.body", defaultValue: "Your Apple Watch already writes into Apple Health on this iPhone. Allow FunctionAlps to read it and your nights, steps and heart data arrive on their own, including while the app is closed."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5).padding(.top, 12)
                    if disclosed == true {
                        ForestPillButton(title: busy ? String(localized: "wearables.connecting", defaultValue: "Opening Apple Health…") : String(localized: "wearables.connect", defaultValue: "Connect Apple Health"), busy: busy) {
                            Task { await connect() }
                        }
                        .padding(.top, 14)
                    } else if disclosed == false {
                        // Disclosure follows the code: no data leaves the phone under a notice that does not describe it.
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "clock").font(.system(size: 12, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                            Text(String(localized: "wearables.gated", defaultValue: "Connecting opens as soon as the updated Privacy Notice, which describes this data, is published. Nothing is read until then."))
                                .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                        }
                        .padding(.top, 12)
                    }
                }
                if case .failed(let message) = service.state {
                    Text(message).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 10)
                }
                if let errorMessage {
                    Text(errorMessage).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 10)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                .strokeBorder(Color(hex: 0x4A8A5C, opacity: service.isConnected ? 0.45 : 0), lineWidth: 1)
        }
    }

    /// Devices linked elsewhere (Thryve on the web app); this phone's own Apple Health row is the card above.
    private var otherConnections: [WearableConnectionRow] {
        connections.filter { $0.dataSourceId != WearableSource.appleHealth }
    }

    private var statusLine: String {
        guard service.isConnected else { return String(localized: "wearables.notConnected", defaultValue: "Not connected") }
        if let at = service.lastSyncAt {
            return String(localized: "wearables.lastSync", defaultValue: "Connected · synced \(at.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "wearables.connected", defaultValue: "Connected")
    }

    // MARK: Recent days

    private var recentCard: some View {
        FACard {
            if days.isEmpty {
                Text(String(localized: "wearables.recent.empty", defaultValue: "Nothing has landed yet. After the first sync your nights and days appear here."))
                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "wearables.col.day", defaultValue: "Day")).frame(width: 52, alignment: .leading)
                        Spacer()
                        Text(String(localized: "wearables.col.sleep", defaultValue: "Sleep")).frame(width: 52, alignment: .trailing)
                        Text(String(localized: "wearables.col.rhr", defaultValue: "RHR")).frame(width: 46, alignment: .trailing)
                        Text(String(localized: "wearables.col.hrv", defaultValue: "HRV")).frame(width: 46, alignment: .trailing)
                        Text(String(localized: "wearables.col.steps", defaultValue: "Steps")).frame(width: 56, alignment: .trailing)
                    }
                    .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(0.8).textCase(.uppercase).foregroundStyle(ProfilePalette.muted)
                    .padding(.bottom, 6)
                    ForEach(days.suffix(14).reversed()) { d in
                        HStack {
                            Text(String(d.date.suffix(5).replacingOccurrences(of: "-", with: "."))).frame(width: 52, alignment: .leading).foregroundStyle(ProfilePalette.muted)
                            Spacer()
                            Text(d.sleepHours.map { String(format: "%.1f h", $0) } ?? "·").frame(width: 52, alignment: .trailing)
                            Text(d.restingHr.map { "\($0)" } ?? "·").frame(width: 46, alignment: .trailing)
                            Text(d.hrvMs.map { "\(Int($0.rounded()))" } ?? "·").frame(width: 46, alignment: .trailing)
                            Text(d.steps.map { $0.formatted() } ?? "·").frame(width: 56, alignment: .trailing)
                        }
                        .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
                    }
                }
            }
        }
    }

    private func readRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft).frame(width: 18).padding(.top, 2)
            Text(text).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(4)
        }
    }

    // MARK: Actions

    private func connect() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        do {
            try await service.connect()
            await load()
        } catch {
            errorMessage = String(localized: "wearables.connectFailed", defaultValue: "Apple Health couldn't be opened. Check Settings → Health → Data Access & Devices and try again.")
        }
        busy = false
    }

    private func load() async {
        if member == nil { member = try? await dependencies.members.currentMember() }
        guard let member else { return }
        async let recent = service.recentDays(patientId: member.patientId)
        async let links = service.connections(patientId: member.patientId)
        async let notice = dependencies.account.legalDocument(key: "privacy_policy")
        days = await recent
        connections = await links
        let version = (try? await notice)?.version
        disclosed = service.isConnected || WearableDisclosure.isDisclosed(noticeVersion: version)
    }
}
