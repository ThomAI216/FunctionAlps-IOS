import SwiftUI

/// The Expo `profile-feedback.tsx`: the PRODUCT channel. Leads with what it is NOT (the nutritionist
/// card sits before the box), and the acknowledgement says what happens next.
struct FeedbackView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var message = ""
    @State private var busy = false
    @State private var sent = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: String(localized: "profile.feedback", defaultValue: "Your feedback"))
                if sent { thanks } else { form }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var thanks: some View {
        SurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(ProfilePalette.accentSoft)
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(FAColor.forestSoft)
                }
                .frame(width: 44, height: 44)
                .padding(.bottom, 14)
                Text(String(localized: "feedback.thanks.title", defaultValue: "Thank you")).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink).padding(.bottom, 8)
                Text(String(localized: "feedback.thanks.body1", defaultValue: "A real person reads every one of these. We will go through what you wrote and come back to you about it."))
                    .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
                Text(String(localized: "feedback.thanks.body2", defaultValue: "This is genuinely how the app gets better, so thank you for taking the time."))
                    .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.top, 10)
                Button { sent = false } label: {
                    Text(String(localized: "feedback.again", defaultValue: "Write something else")).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
        .padding(.top, 6)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ProfilePalette.accentSoft)
                    Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                }
                .frame(width: 40, height: 40)
                Text(String(localized: "profile.feedback.title", defaultValue: "Tell us about the app")).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
            }
            .padding(.top, 6)

            Text(String(localized: "feedback.intro", defaultValue: "What is confusing, what is slow, what is missing, what you wish it did. Anything at all about using the app. It helps us more than you would think, and small remarks are often the most useful ones."))
                .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.top, 12)

            // The split, said plainly and before the box.
            Button { router.profilePath.append(.messages) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "stethoscope").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "feedback.clinical.title", defaultValue: "Question about your health or your plan?")).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "feedback.clinical.sub", defaultValue: "That goes to your nutritionist instead. Tap here to message her.")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    }
                    .multilineTextAlignment(.leading)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            TextField(String(localized: "feedback.placeholder", defaultValue: "What is on your mind?"), text: $message, axis: .vertical)
                .lineLimit(6...14)
                .focused($focused)
                .font(FATypography.sans(15.5, relativeTo: .body))
                .foregroundStyle(FAColor.ink)
                .padding(14)
                .frame(minHeight: 150, alignment: .top)
                .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(message.isEmpty ? ProfilePalette.hairline : FAColor.forestSoft, lineWidth: 1.5) }
                .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.red).padding(.top, 8)
            }

            ForestPillButton(title: busy ? String(localized: "feedback.sending", defaultValue: "Sending...") : String(localized: "feedback.send", defaultValue: "Send feedback"),
                             enabled: !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, busy: busy) {
                Task { await submit() }
            }
            .padding(.top, 16)
        }
    }

    private func submit() async {
        guard !busy else { return }
        focused = false
        busy = true
        errorMessage = nil
        do {
            try await dependencies.account.sendFeedback(message)
            sent = true
            message = ""
        } catch {
            errorMessage = String(localized: "feedback.failed", defaultValue: "That did not send. Please try again.")
        }
        busy = false
    }
}
