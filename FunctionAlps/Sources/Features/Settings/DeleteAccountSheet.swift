import SwiftUI

/// GDPR / revFADP account deletion: type DELETE → the `delete-account` edge function (audit row,
/// photos wiped, auth user gone, everything cascades) → signed out locally.
struct DeleteAccountSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var matched: Bool { confirmText.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" }
    private let erased = [
        String(localized: "delete.erased.profile", defaultValue: "Your profile & goals"),
        String(localized: "delete.erased.meals", defaultValue: "All logged meals, photos & scores"),
        String(localized: "delete.erased.checkins", defaultValue: "Daily and gut check-ins"),
        String(localized: "delete.erased.reports", defaultValue: "AI reports & insights"),
        String(localized: "delete.erased.consents", defaultValue: "Consents & preferences"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(ProfilePalette.red.opacity(0.14))
                        Image(systemName: "trash").font(.system(size: 22, weight: .semibold)).foregroundStyle(ProfilePalette.red)
                    }
                    .frame(width: 54, height: 54)
                    Text(String(localized: "delete.title", defaultValue: "Delete your account")).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    Text(String(localized: "delete.intro", defaultValue: "This permanently erases everything below from FunctionAlps servers. It cannot be undone."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(5)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(erased, id: \.self) { line in
                            HStack(spacing: 9) {
                                Circle().fill(ProfilePalette.red).frame(width: 5, height: 5)
                                Text(line).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            }
                        }
                    }
                }
                .padding(.top, 14)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 13)).foregroundStyle(ProfilePalette.muted)
                    Text(String(localized: "delete.exportFirst", defaultValue: "Want a copy first? Export your data from Privacy & data before deleting."))
                        .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                }
                .padding(.top, 12)

                (Text(String(localized: "delete.type", defaultValue: "Type ")) + Text("DELETE").font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundColor(ProfilePalette.red) + Text(String(localized: "delete.toConfirm", defaultValue: " to confirm")))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    .padding(.top, 18).padding(.bottom, 8)
                TextField("DELETE", text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .disabled(busy)
                    .font(FATypography.sans(15, .semibold, relativeTo: .body))
                    .foregroundStyle(FAColor.ink)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(matched ? ProfilePalette.red : ProfilePalette.hairline, lineWidth: 1) }

                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(ProfilePalette.red)
                        Text(errorMessage).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ProfilePalette.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ProfilePalette.red.opacity(0.3), lineWidth: 1) }
                    .padding(.top, 12)
                }

                Button { Task { await deleteNow() } } label: {
                    Group {
                        if busy { ProgressView().tint(.white) } else {
                            Text(String(localized: "delete.cta", defaultValue: "Delete permanently")).font(FATypography.sans(15, .bold, relativeTo: .body))
                        }
                    }
                    .foregroundStyle(matched ? .white : ProfilePalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(matched ? ProfilePalette.red : ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!matched || busy)
                .padding(.top, 18)

                Button { dismiss() } label: {
                    Text(String(localized: "common.cancel", defaultValue: "Cancel")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
        }
        .background(FAColor.cream)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
    }

    private func deleteNow() async {
        guard matched, !busy else { return }
        busy = true
        errorMessage = nil
        do {
            try await dependencies.account.deleteAccount()
            // The auth user is already destroyed server-side; clear the local session (401 is fine).
            await dependencies.auth.signOut()
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(localized: "delete.failed", defaultValue: "Deletion did not complete. Please try again.")
        }
        busy = false
    }
}
