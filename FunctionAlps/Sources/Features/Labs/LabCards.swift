import SwiftUI

// The lab results screens' shared pieces (labs workspace v2, WP-7b — the Expo `components/labs/*`
// card for card): the status badge, the prose block, the marker row, the "ask" button, the states.
// Every clinical word on these screens comes from the release, in the release's own language
// (`LabResultCopy`); the only app-language strings are the chrome around a result that does not
// exist yet or could not load.

/// Status is ALWAYS an icon plus a label — never colour alone (rule 10 / WCAG 1.4.1).
struct LabStatusBadge: View {
    let status: LabMarkerStatus
    let copy: LabResultCopy
    var large = false

    private var tint: Color {
        switch status {
        case .inRange: FAColor.success
        case .watch: FAColor.warning
        case .outOfRange: FAColor.danger
        }
    }

    private var symbol: String {
        switch status {
        case .inRange: "checkmark.circle"
        case .watch: "eye"
        case .outOfRange: "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: large ? 15 : 12, weight: .semibold))
            Text(copy.statusLabel(status)).font(FATypography.sans(large ? 14 : 12, .semibold, relativeTo: large ? .subheadline : .caption))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, large ? 12 : 9)
        .padding(.vertical, large ? 6 : 4)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A kicker and a paragraph, verbatim from the release. Renders nothing when the release left it blank.
struct LabBlockCard: View {
    let title: String
    let text: String?
    var tinted = false

    var body: some View {
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    LabKicker(title, tinted: tinted)
                    Text(text).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                }
            }
            .overlay {
                if tinted {
                    RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                        .strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.35), lineWidth: 1)
                }
            }
        }
    }
}

/// The uppercase section label (the profile's `SectionLabel` size, tinted forest on the plan cards).
struct LabKicker: View {
    let title: String
    var tinted = false

    init(_ title: String, tinted: Bool = false) {
        self.title = title
        self.tinted = tinted
    }

    var body: some View {
        Text(title.uppercased())
            .font(FATypography.sans(11, .bold, relativeTo: .caption2))
            .tracking(1.2)
            .foregroundStyle(tinted ? FAColor.forestSoft : ProfilePalette.muted)
    }
}

/// One released marker line. The whole row opens its explanation (≥ 56 pt tall touch target).
struct LabMarkerRow: View {
    let marker: LabMarker
    let copy: LabResultCopy
    var first = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(marker.label).font(FATypography.sans(15, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(marker.unit.map { "\(marker.value) \($0)" } ?? marker.value)
                        .font(FATypography.sans(13, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LabStatusBadge(status: marker.status, copy: copy)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !first { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// "Ask your nutritionist a question" — opens the in-app thread (the release language names the button).
struct LabAskButton: View {
    let copy: LabResultCopy
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button { router.push(.messages) } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 15, weight: .semibold))
                Text(copy.ask).font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
            }
            .foregroundStyle(FAColor.forestSoft)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Color(hex: 0x4A8A5C, opacity: 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.3), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// The frame's small print under a result (the release's validated line, the disclaimer).
struct LabFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FATypography.sans(11, relativeTo: .caption2))
            .foregroundStyle(ProfilePalette.muted)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
    }
}

// MARK: - States (app language — no release exists to borrow words from)

enum LabStates {
    static var loading: some View {
        FALoadingState(message: String(localized: "labs.loading", defaultValue: "Loading your results…"))
    }

    static func failed(_ error: AppError, retry: @escaping () -> Void) -> some View {
        FAErrorState(title: String(localized: "labs.error.title", defaultValue: "Your results could not be loaded"), message: error.userMessage, retry: retry)
    }

    /// Nothing approved yet — the honest state, never a sample.
    static var empty: some View {
        FACard {
            FAEmptyState(
                title: String(localized: "labs.empty.title", defaultValue: "No released results yet"),
                message: String(localized: "labs.empty.message", defaultValue: "Your results appear here once your nutritionist has reviewed and approved them."),
                systemImage: "testtube.2"
            )
        }
    }

    /// A release id that is not (or no longer) in the member's results — a stale link, or a revocation.
    static var missing: some View {
        FACard {
            FAEmptyState(
                title: String(localized: "labs.missing.title", defaultValue: "This result isn't available"),
                message: String(localized: "labs.missing.message", defaultValue: "It may have been withdrawn by your nutritionist. Pull down to refresh, or go back to your results."),
                systemImage: "testtube.2"
            )
        }
    }
}
