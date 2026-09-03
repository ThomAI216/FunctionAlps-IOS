import SwiftUI

/// The three non-success states every network-backed screen must render (PRD §43).
struct FALoadingState: View {
    var message: String = String(localized: "state.loading", defaultValue: "Loading…")

    var body: some View {
        VStack(spacing: FASpacing.md) {
            ProgressView().tint(FAColor.brand)
            Text(message).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct FAErrorState: View {
    let title: String
    let message: String
    var retryTitle: String? = String(localized: "action.retry", defaultValue: "Try again")
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: FASpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(FAColor.warning)
                .accessibilityHidden(true)
            Text(title).font(FATypography.headline).foregroundStyle(FAColor.ink)
            Text(message)
                .font(FATypography.callout)
                .foregroundStyle(FAColor.inkSecondary)
                .multilineTextAlignment(.center)
            if let retry, let retryTitle {
                FAButton(title: retryTitle, style: .secondary, action: retry)
                    .frame(maxWidth: 220)
            }
        }
        .padding(FASpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FAEmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "leaf"

    var body: some View {
        VStack(spacing: FASpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(FAColor.brand)
                .accessibilityHidden(true)
            Text(title).font(FATypography.headline).foregroundStyle(FAColor.ink)
            Text(message)
                .font(FATypography.callout)
                .foregroundStyle(FAColor.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(FASpacing.lg)
        .frame(maxWidth: .infinity)
    }
}
