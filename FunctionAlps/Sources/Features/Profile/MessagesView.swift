import SwiftUI

/// The in-app thread with the nutritionist (the Expo `profile-messages.tsx`): header, the pinned
/// promise, day-grouped bubbles (mine gold, hers surface), an optional context chip, the composer.
struct MessagesView: View {
    /// "Ask about this meal" arrives with the meal; held in state so the member can drop it.
    var initialContext: MessageContext? = nil
    var contextMealName: String? = nil

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [PatientMessage] = []
    @State private var loading = true
    @State private var text = ""
    @State private var sending = false
    @State private var context: MessageContext?
    @State private var member: Member?
    @State private var errorMessage: String?

    private var canSend: Bool { MessagingLogic.validate(text) && !sending }

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "settings.messages", defaultValue: "Messages"), hairline: true)
            // The promise, pinned — NOT a "no AI" claim: the clinician may draft with help, a human always sends.
            Text(String(localized: "messages.promise", defaultValue: "Direct line with your nutritionist"))
                .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                .frame(maxWidth: .infinity).padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if loading {
                            ProgressView().tint(FAColor.gold).padding(.top, 60)
                        } else if messages.isEmpty {
                            emptyState.padding(.top, 40)
                        } else {
                            ForEach(MessagingLogic.groupByDay(messages)) { group in
                                Text(group.label.uppercased())
                                    .font(FATypography.sans(11, .semibold, relativeTo: .caption)).tracking(0.4).foregroundStyle(ProfilePalette.muted)
                                    .padding(.horizontal, 12).padding(.vertical, 3)
                                    .background(Color(hex: 0x7A796F, opacity: 0.12), in: Capsule())
                                    .padding(.vertical, 2)
                                ForEach(group.items) { m in bubble(m).id(m.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            if let context {
                HStack(spacing: 8) {
                    Text(String(localized: "messages.about", defaultValue: "About: \(context.chipLabel(mealName: contextMealName))"))
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { self.context = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "messages.removeContext", defaultValue: "Remove context"))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(hex: 0x4A8A5C, opacity: 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.28), lineWidth: 1) }
                .padding(.horizontal, 14).padding(.bottom, 6)
            }

            if let errorMessage {
                Text(errorMessage).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).padding(.horizontal, 16).padding(.bottom, 4)
            }

            composer
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            context = initialContext
            member = try? await dependencies.members.currentMember()
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: 0x4A8A5C, opacity: 0.16))
                Image(systemName: "bubble.left").font(.system(size: 24, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
            }
            .frame(width: 54, height: 54)
            Text(String(localized: "messages.promise", defaultValue: "Direct line with your nutritionist"))
                .font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.ink).multilineTextAlignment(.center)
            Text(String(localized: "messages.empty.body", defaultValue: "Ask about a meal, how you felt after eating, your check-ins · anything.\n\nYour nutritionist reads every message and replies personally."))
                .font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(5)
                .frame(maxWidth: 250)
        }
        .padding(30)
        .background(Color(hex: 0x4A8A5C, opacity: 0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.28), lineWidth: 1) }
        .padding(.horizontal, 8)
    }

    private func bubble(_ m: PatientMessage) -> some View {
        VStack(alignment: m.mine ? .trailing : .leading, spacing: 3) {
            if !m.mine {
                Text(String(localized: "messages.her", defaultValue: "Your nutritionist"))
                    .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forest).padding(.leading, 2)
            }
            Text(m.text)
                .font(FATypography.sans(14.5, relativeTo: .body)).lineSpacing(4)
                .foregroundStyle(m.mine ? FAColor.charcoal : FAColor.ink)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(m.mine ? FAColor.gold : ProfilePalette.surface, in: UnevenRoundedRectangle(topLeadingRadius: m.mine ? 18 : 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: m.mine ? 6 : 18, style: .continuous))
                .overlay {
                    if !m.mine {
                        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                            .strokeBorder(ProfilePalette.hairline, lineWidth: 1)
                    }
                }
            HStack(spacing: 5) {
                if m.unread { Circle().fill(FAColor.forestSoft).frame(width: 6, height: 6) }
                Text(m.createdAt.formatted(date: .omitted, time: .shortened)).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
        .padding(m.mine ? .leading : .trailing, 60)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField(String(localized: "messages.placeholder", defaultValue: "Write a message…"), text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(FAColor.ink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(text.isEmpty ? ProfilePalette.hairline : FAColor.gold, lineWidth: 1.5) }
            Button { Task { await send() } } label: {
                ZStack {
                    Circle().fill(canSend ? FAColor.gold : ProfilePalette.surfaceSoft)
                    if sending { ProgressView().tint(FAColor.charcoal) } else {
                        Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(canSend ? FAColor.charcoal : ProfilePalette.muted)
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "messages.send", defaultValue: "Send message"))
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 16)
        .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
    }

    private func load() async {
        messages = (try? await dependencies.messaging.thread()) ?? []
        loading = false
        await dependencies.messaging.markRead()
    }

    private func send() async {
        guard canSend, let member else { return }
        sending = true
        errorMessage = nil
        do {
            try await dependencies.messaging.send(text, member: member, context: context)
            text = ""
            context = nil
            await load()
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(localized: "messages.failed", defaultValue: "That did not send. Please try again.")
        }
        sending = false
    }
}
