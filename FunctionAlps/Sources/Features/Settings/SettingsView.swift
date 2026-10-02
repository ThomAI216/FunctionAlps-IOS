import SwiftUI
import UIKit

/// The Expo `profile-settings.tsx`: Language · Appearance · Account rows · Sign out · Delete account.
/// Language is the phone's own per-app setting (iOS owns it); Appearance offers the photo walls.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @AppStorage(FAWalls.storageKey) private var wallKey: String = FAWalls.defaultKey
    @State private var confirmSignOut = false
    @State private var showDelete = false
    @State private var signingOut = false

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "settings.title", defaultValue: "Settings"))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Language — iOS keeps the per-app choice in Settings; this is the way there.
                    SettingsSectionLabel(title: String(localized: "settings.language", defaultValue: "Language"))
                    FACard(padded: false) {
                        SettingsRow(symbol: "globe", label: String(localized: "settings.language.row", defaultValue: "App language"), sub: String(localized: "settings.language.sub", defaultValue: "English or French · set in your phone's Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }

                    // Appearance — the owner's photo walls.
                    SettingsSectionLabel(title: String(localized: "settings.appearance", defaultValue: "Appearance"))
                    FACard(padded: false) {
                        HStack(spacing: 6) {
                            ForEach(FAPhotoWalls.all, id: \.key) { photo in
                                WallSwatch(photo: photo, selection: $wallKey)
                            }
                        }
                        .padding(10)
                    }

                    // Notifications — the member owns every reminder.
                    SettingsSectionLabel(title: String(localized: "settings.notifications.section", defaultValue: "Reminders"))
                    FACard(padded: false) {
                        SettingsRow(symbol: "bell", label: String(localized: "settings.notifications", defaultValue: "Notifications"), sub: String(localized: "settings.notifications.sub", defaultValue: "Check-ins, meals, how you feel, your practitioner"), tintHex: 0xC99A3B) { router.profilePath.append(.notifications) }
                    }

                    // Devices — Apple Health covers the Apple Watch and anything that syncs into Health.
                    SettingsSectionLabel(title: String(localized: "settings.devices", defaultValue: "Devices"))
                    FACard(padded: false) {
                        SettingsRow(symbol: "applewatch", label: String(localized: "settings.wearables", defaultValue: "Apple Health & Apple Watch"), sub: String(localized: "settings.wearables.sub", defaultValue: "Steps, sleep, heart rate and recovery"), tintHex: 0x3F7FC4) { router.profilePath.append(.wearables) }
                    }

                    // Account
                    SettingsSectionLabel(title: String(localized: "settings.account", defaultValue: "Account"))
                    FACard(padded: false) {
                        VStack(spacing: 0) {
                            SettingsRow(symbol: "shield", label: String(localized: "settings.privacy", defaultValue: "Privacy & data")) { router.profilePath.append(.privacy) }
                            SettingsRow(symbol: "bubble.left", label: String(localized: "settings.messages", defaultValue: "Messages"), tintHex: 0x3F7FC4, first: false) { router.profilePath.append(.messages) }
                            SettingsRow(symbol: "questionmark.circle", label: String(localized: "settings.help", defaultValue: "Help & FAQ"), first: false) { router.profilePath.append(.help) }
                        }
                    }

                    // Sign out
                    Button { confirmSignOut = true } label: {
                        HStack(spacing: 8) {
                            if signingOut { ProgressView().tint(ProfilePalette.red) }
                            Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 13, weight: .semibold))
                            Text(String(localized: "profile.signOut", defaultValue: "Sign out")).font(FATypography.sans(13, .semibold, relativeTo: .subheadline))
                        }
                        .foregroundStyle(ProfilePalette.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .overlay { Capsule().strokeBorder(ProfilePalette.red.opacity(0.4), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 26)
                    .confirmationDialog(String(localized: "profile.signOut.confirm", defaultValue: "Sign out of FunctionAlps?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button(String(localized: "profile.signOut", defaultValue: "Sign out"), role: .destructive) {
                            Task { signingOut = true; await dependencies.auth.signOut(); signingOut = false }
                        }
                        Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
                    }

                    // Delete account (GDPR / nFADP)
                    Button { showDelete = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                            Text(String(localized: "settings.deleteAccount", defaultValue: "Delete my account & data")).font(FATypography.sans(12, .semibold, relativeTo: .caption))
                        }
                        .foregroundStyle(ProfilePalette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)

                    Text(String(localized: "settings.versionLine", defaultValue: "FunctionAlps v\(AppInfo.version) (\(AppInfo.build))"))
                        .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                        .frame(maxWidth: .infinity).padding(.top, 18)
                        // Hidden way into camera movement counting while it is being validated on real phones.
                        .onLongPressGesture(minimumDuration: 1.2) { router.profilePath.append(.motionLab) }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
    }
}

/// One Appearance choice: a 44 pt round preview, its name under it, a ring when selected.
private struct WallSwatch: View {
    let photo: PhotoWall
    @Binding var selection: String

    var body: some View {
        let active = FAWalls.resolved(selection) == photo
        Button { selection = photo.key } label: {
            VStack(spacing: 5) {
                Group {
                    if let thumb = PhotoWallImages.thumbnail(photo) {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Color(hex: photo.tint)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(active ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: active ? 2 : 1) }
                Text(photo.label)
                    .font(FATypography.sans(9.5, .semibold, relativeTo: .caption2))
                    .foregroundStyle(active ? FAColor.ink : ProfilePalette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
