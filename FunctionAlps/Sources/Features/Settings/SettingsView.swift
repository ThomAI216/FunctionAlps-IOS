import SwiftUI

/// Settings skeleton (PRD §24 Phase A / §48). Account deletion is intentionally
/// disabled until the retention behaviour is specified; the backend already has
/// a `delete-account` edge function the future flow will call.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: FASpacing.lg) {
                    FASection(title: String(localized: "settings.about", defaultValue: "About")) {
                        FACard {
                            VStack(spacing: 0) {
                                FAListRow(title: String(localized: "settings.version", defaultValue: "Version"), subtitle: "\(AppInfo.version) (\(AppInfo.build))", systemImage: "info.circle")
                                Divider().overlay(FAColor.separator)
                                FAListRow(title: String(localized: "settings.environment", defaultValue: "Environment"), subtitle: dependencies.environment.name.rawValue, systemImage: "server.rack")
                            }
                        }
                    }
                    FASection(title: String(localized: "settings.account", defaultValue: "Account")) {
                        FACard {
                            VStack(alignment: .leading, spacing: FASpacing.sm) {
                                FAButton(title: String(localized: "settings.deleteAccount", defaultValue: "Delete account"), style: .destructive, isEnabled: false) {}
                                Text(String(localized: "settings.deleteAccount.note", defaultValue: "Account deletion will be available in the app soon. Until then, use Privacy & Data in the FunctionAlps app or write to data@functionalps.ch."))
                                    .font(FATypography.caption)
                                    .foregroundStyle(FAColor.inkSecondary)
                            }
                        }
                    }
                }
                .padding(FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
