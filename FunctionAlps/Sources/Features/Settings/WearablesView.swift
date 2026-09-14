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
    // Direct vendors
    @State private var availableVendors: Set<String> = []
    @State private var accounts: [WearableVendorAccountRow] = []
    @State private var vendorDisclosed: Bool?
    @State private var busyVendor: String?
    @State private var vendorMessage: String?
    @State private var confirmVendorDisconnect: WearableVendor?

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
                    if let vendorMessage {
                        Text(vendorMessage).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.bottom, 8)
                    }
                    if vendorDisclosed == false {
                        FACard {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "clock").font(.system(size: 12, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                                Text(String(localized: "vendor.gated", defaultValue: "Linking a wearable account opens with the next update of the Privacy Notice, which describes this data. Apple Health above works today."))
                                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                            }
                        }
                    }
                    ForEach(WearableVendor.all) { vendor in
                        VendorCard(
                            vendor: vendor,
                            account: accounts.first { $0.vendor == vendor.key },
                            available: availableVendors.contains(vendor.key) && vendorDisclosed == true,
                            busy: busyVendor == vendor.key,
                            onConnect: { Task { await connect(vendor) } },
                            onSync: { Task { await syncVendors() } },
                            onDisconnect: { confirmVendorDisconnect = vendor }
                        )
                        .padding(.bottom, 10)
                    }
                    Text(String(localized: "vendor.footnote", defaultValue: "Devices without a public service (Eight Sleep, RingConn, Renpho, Zepp…) still arrive through Apple Health when their app writes to it."))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 4)
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
        .confirmationDialog(String(localized: "vendor.disconnect.confirm", defaultValue: "Unlink this account?"), isPresented: Binding(get: { confirmVendorDisconnect != nil }, set: { if !$0 { confirmVendorDisconnect = nil } }), titleVisibility: .visible) {
            Button(String(localized: "wearables.disconnect", defaultValue: "Disconnect"), role: .destructive) {
                if let v = confirmVendorDisconnect { Task { await disconnect(v, erase: false) } }
            }
            Button(String(localized: "vendor.disconnect.erase", defaultValue: "Disconnect and delete synced data"), role: .destructive) {
                if let v = confirmVendorDisconnect { Task { await disconnect(v, erase: true) } }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "vendor.disconnect.body", defaultValue: "We delete the access credential and stop pulling. Readings already in your record stay, under the retention rules of the Privacy Notice — or choose to delete them as well."))
        }
    }

    // MARK: Direct vendors

    private func connect(_ vendor: WearableVendor) async {
        guard busyVendor == nil else { return }
        busyVendor = vendor.key
        vendorMessage = nil
        do {
            switch try await service.connectVendor(vendor.key) {
            case .ok:
                await load()
            case .failed(_, let reason):
                if reason != "denied" { vendorMessage = VendorCallback.message(for: reason) }
            }
        } catch let error as AppError {
            vendorMessage = error.userMessage
        } catch {
            vendorMessage = VendorCallback.message(for: "unknown")
        }
        busyVendor = nil
    }

    private func syncVendors() async {
        guard busyVendor == nil else { return }
        busyVendor = "*"
        await service.syncVendorsNow()
        await load()
        busyVendor = nil
    }

    private func disconnect(_ vendor: WearableVendor, erase: Bool) async {
        busyVendor = vendor.key
        do { try await service.disconnectVendor(vendor.key, erase: erase); await load() }
        catch let error as AppError { vendorMessage = error.userMessage }
        catch { vendorMessage = VendorCallback.message(for: "unknown") }
        busyVendor = nil
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
        async let accs = service.vendorAccounts(patientId: member.patientId)
        async let notice = dependencies.account.legalDocument(key: "privacy_policy")
        days = await recent
        connections = await links
        accounts = await accs
        let version = (try? await notice)?.version
        disclosed = service.isConnected || WearableDisclosure.isDisclosed(noticeVersion: version)
        vendorDisclosed = WearableDisclosure.isVendorDisclosed(noticeVersion: version)
        availableVendors = await service.availableVendors()
    }
}

/// One direct vendor: mark, name, status line (the nine server states collapsed), what it adds,
/// Connect / Reconnect / Sync now / Disconnect.
private struct VendorCard: View {
    let vendor: WearableVendor
    let account: WearableVendorAccountRow?
    let available: Bool
    let busy: Bool
    let onConnect: () -> Void
    let onSync: () -> Void
    let onDisconnect: () -> Void

    private var presentation: WearableVendorAccountRow.Presentation { account?.presentation ?? .off }
    private var isLive: Bool { account?.isLive == true }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 13) {
                    VendorMark(vendor: vendor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vendor.name).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        Text(statusLine).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(statusColor)
                    }
                    Spacer(minLength: 0)
                    if presentation == .off, available {
                        pill(String(localized: "vendor.connect", defaultValue: "Connect"), action: onConnect)
                    } else if presentation == .reconnect {
                        pill(String(localized: "vendor.reconnect", defaultValue: "Reconnect"), action: onConnect)
                    } else if presentation == .off, account == nil {
                        // Not open to members yet: a quiet tag where Connect will appear once the vendor is `available`.
                        Text(String(localized: "vendor.tag.inDevelopment", defaultValue: "In development"))
                            .font(FATypography.sans(11, .semibold, relativeTo: .caption2))
                            .foregroundStyle(ProfilePalette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                    }
                }
                if isLive || presentation == .reconnect {
                    HStack(spacing: 8) {
                        if isLive {
                            Button(action: onSync) {
                                HStack(spacing: 6) {
                                    if busy { ProgressView().tint(FAColor.charcoal).scaleEffect(0.7) } else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .bold)) }
                                    Text(String(localized: "wearables.syncNow", defaultValue: "Sync now")).font(FATypography.sans(12, .bold, relativeTo: .caption))
                                }
                                .foregroundStyle(FAColor.charcoal).padding(.horizontal, 12).padding(.vertical, 8).background(FAColor.forestSoft, in: Capsule())
                            }
                            .buttonStyle(.plain).disabled(busy)
                        }
                        Button(action: onDisconnect) {
                            Text(String(localized: "wearables.disconnect", defaultValue: "Disconnect"))
                                .font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(ProfilePalette.red)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .overlay { Capsule().strokeBorder(ProfilePalette.red.opacity(0.35), lineWidth: 1) }
                        }
                        .buttonStyle(.plain).disabled(busy)
                    }
                    .padding(.top, 12)
                }
                Text(String(localized: "vendor.adds", defaultValue: "Adds: \(vendor.adds)")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4).padding(.top, 10)
                Text(String(localized: "vendor.viaHealth", defaultValue: "Already via Apple Health: \(vendor.viaAppleHealth)")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 3)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: isLive ? 0.45 : 0), lineWidth: 1) }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(FAColor.charcoal).scaleEffect(0.7) }
                Text(title).font(FATypography.sans(12, .bold, relativeTo: .caption))
            }
            .foregroundStyle(FAColor.charcoal).padding(.horizontal, 12).padding(.vertical, 8).background(FAColor.forestSoft, in: Capsule())
        }
        .buttonStyle(.plain).disabled(busy)
    }

    private var statusColor: Color {
        switch presentation {
        case .live, .syncing: FAColor.forestSoft
        case .degraded, .reconnect: ProfilePalette.red
        case .off: ProfilePalette.muted
        }
    }

    private var statusLine: String {
        switch presentation {
        case .syncing:
            return String(localized: "vendor.status.syncing", defaultValue: "Connected · syncing…")
        case .degraded:
            return String(localized: "vendor.status.degraded", defaultValue: "Connected · the last sync had trouble, retrying")
        case .reconnect:
            return String(localized: "vendor.status.reconnect", defaultValue: "Needs reconnecting — the access expired or was revoked")
        case .live:
            if let at = account?.lastSuccessfulSyncAt {
                return String(localized: "vendor.status.lastSync", defaultValue: "Connected · synced \(at.formatted(.relative(presentation: .named)))")
            }
            if let at = account?.connectedAt {
                return String(localized: "vendor.connectedSince", defaultValue: "Connected · since \(at.formatted(date: .abbreviated, time: .omitted))")
            }
            return String(localized: "wearables.connected", defaultValue: "Connected")
        case .off:
            if account?.status == "disconnected" {
                return String(localized: "vendor.status.disconnected", defaultValue: "Disconnected")
            }
            return available ? String(localized: "vendor.available", defaultValue: "Account link available") : String(localized: "vendor.soon", defaultValue: "In development")
        }
    }
}

/// The brand mark on a vendor card: the brand's monochrome logo from the asset catalog (`vendor-<key>` image
/// set, template-rendered in the brand colour), else the brand's wordmark in its colour. Sources and licences:
/// THIRD_PARTY_NOTICES.md (simple-icons CC0, Arcticons CC BY-SA 4.0); the owner may swap in a press-kit logo.
struct VendorMark: View {
    let vendor: WearableVendor

    private var hasLogo: Bool { UIImage(named: vendor.logoAsset) != nil }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: vendor.tintHex, opacity: 0.12))
            if hasLogo {
                Image(vendor.logoAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(hex: vendor.tintHex))
                    .padding(vendor.key == "garmin" ? 6 : 9)
            } else {
                Text(vendor.wordmark)
                    .font(.system(size: vendor.wordmark.count > 6 ? 9 : 10, weight: .heavy, design: .rounded))
                    .tracking(vendor.wordmark == vendor.wordmark.uppercased() ? 0.6 : 0)
                    .foregroundStyle(Color(hex: vendor.tintHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(vendor.name)
    }
}
