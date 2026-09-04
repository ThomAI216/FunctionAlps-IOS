import SwiftUI

/// What stands between a signed-in session and the tabs — the Expo root `AuthGate`, in its order:
/// resolve the member (the `patient-register` rung creates the row on a first sign-in) → the access
/// window (fail-open) → the consent gate (18+ first, then every required tick) → onboarding until
/// CM OS holds the stamp AND the five baseline inputs → `MainTabView`.
///
/// Every decision is taken on a fresh read; nothing here trusts a device flag for what the server owns.
struct MemberGateView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    enum Stage: Equatable {
        case loading
        case failed
        case notRegistered
        case accessClosed(AppAccess)
        case consent(needsAge: Bool)
        case onboarding
        case ready
    }

    @State private var stage: Stage = .loading
    @State private var member: Member?
    @State private var bundle: AccountService.ConsentsBundle?

    var body: some View {
        Group {
            switch stage {
            case .loading:
                LaunchView()
            case .failed:
                GateMessageView(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "gate.failed.title", defaultValue: "We couldn't reach your account"),
                    message: String(localized: "gate.failed.body", defaultValue: "Check your connection and try again. Nothing you recorded is affected."),
                    primary: String(localized: "action.retry", defaultValue: "Try again"),
                    onPrimary: { Task { await resolve() } },
                    secondary: String(localized: "profile.signOut", defaultValue: "Sign out"),
                    onSecondary: { Task { await dependencies.auth.signOut() } }
                )
            case .notRegistered:
                GateMessageView(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: String(localized: "gate.notRegistered.title", defaultValue: "We couldn't find your membership"),
                    message: String(localized: "gate.notRegistered.body", defaultValue: "Your account exists but isn't linked to a FunctionAlps member yet. Try again in a moment, or write to data@functionalps.ch and we'll sort it out."),
                    primary: String(localized: "action.retry", defaultValue: "Try again"),
                    onPrimary: { Task { await resolve() } },
                    secondary: String(localized: "profile.signOut", defaultValue: "Sign out"),
                    onSecondary: { Task { await dependencies.auth.signOut() } }
                )
            case .accessClosed(let access):
                AccessClosedView(access: access) { Task { await resolve() } }
            case .consent(let needsAge):
                if let bundle {
                    ConsentGateView(bundle: bundle, needsAge: needsAge) { Task { await resolve() } }
                } else {
                    LaunchView()
                }
            case .onboarding:
                if let member {
                    OnboardingFlowView(member: member) { Task { await resolve() } }
                } else {
                    LaunchView()
                }
            case .ready:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stage)
        .task { await resolve() }
        .onChange(of: scenePhase) { _, phase in
            // A closed window re-checks when the app comes forward, so a granted access never needs a restart.
            guard phase == .active, case .accessClosed = stage else { return }
            Task { await resolve() }
        }
    }

    /// One pass through the gates, top to bottom. Each step reads afresh — the previous answer may
    /// have just been changed by the screen that called us back.
    private func resolve() async {
        let m: Member
        do {
            m = try await dependencies.members.currentMember()
        } catch MemberService.MemberError.notRegistered {
            stage = .notRegistered
            return
        } catch let error as AppError where error == .unauthorized {
            await dependencies.auth.handleUnauthorized()
            return
        } catch {
            Log.auth.error("gate: member read failed: \(String(describing: error), privacy: .public)")
            stage = .failed
            return
        }
        member = m

        // Access window — FAIL-OPEN: a read error is "allowed, unknown", never a locked door.
        let access = await dependencies.profile.access(patientId: m.patientId)
        if !access.allowed {
            stage = .accessClosed(access)
            return
        }

        // Consents. Nothing approved yet ⇒ no rows ⇒ nothing to accept ⇒ the gate must not block
        // (fail-open here and ONLY here). A read failure blocks with a retry — the screen shows it.
        do {
            let b = try await dependencies.account.consents()
            bundle = b
            let requiredOpen = b.consents.contains { $0.required && !$0.accepted }
            if requiredOpen {
                stage = .consent(needsAge: m.profile?.adultConfirmedAt == nil)
                return
            }
        } catch {
            bundle = nil
            stage = .consent(needsAge: m.profile?.adultConfirmedAt == nil)
            return
        }

        if OnboardingLogic.status(m.profile) == .needsOnboarding {
            stage = .onboarding
            return
        }
        stage = .ready
    }
}

/// A centred message with one forest pill and an optional text action — the gate's error states.
struct GateMessageView: View {
    let symbol: String
    let title: String
    let message: String
    let primary: String
    let onPrimary: () -> Void
    var secondary: String? = nil
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ProfilePalette.accentSoft)
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
            }
            .frame(width: 54, height: 54)
            .padding(.bottom, 18)
            Text(title).font(FATypography.display(24, relativeTo: .title)).foregroundStyle(FAColor.ink).multilineTextAlignment(.center).lineSpacing(4).padding(.bottom, 10)
            Text(message).font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(5)
            ForestPillButton(title: primary, action: onPrimary).padding(.top, 24)
            if let secondary {
                Button(action: onSecondary) {
                    Text(secondary).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer()
        }
        .padding(.horizontal, 30)
        .faWall()
    }
}

/// The member's window has closed (discovery past three days, beta past thirty) — the Expo `AccessWindowGate`.
/// No guilt, one next step, and it says plainly that the data is safe.
struct AccessClosedView: View {
    let access: AppAccess
    let onRecheck: () -> Void
    @Environment(\.openURL) private var openURL

    private var isDiscovery: Bool { access.tier == .discovery }
    static let membersRequestURL = URL(string: "https://members.functionalps.ch/dashboard/request-access")!

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ProfilePalette.accentSoft)
                        Image(systemName: "sparkles").font(.system(size: 24, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(width: 54, height: 54)
                    .padding(.bottom, 18)
                    Text(isDiscovery
                        ? String(localized: "access.closed.discovery.title", defaultValue: "Your three days are up")
                        : String(localized: "access.closed.beta.title", defaultValue: "Your beta access has ended"))
                        .font(FATypography.display(27, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).lineSpacing(4).padding(.bottom, 8)
                    Text(isDiscovery
                        ? String(localized: "access.closed.discovery.body", defaultValue: "Thank you for trying it properly. Everything you recorded is safe and stays yours. To keep tracking, tell us a little about yourself and we will take it from there.")
                        : String(localized: "access.closed.beta.body", defaultValue: "Thank you for testing with us. Everything you recorded is safe and stays yours. To keep going, talk to us about what comes next."))
                        .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.bottom, 22)
                    FACard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock").font(.system(size: 17, weight: .medium)).foregroundStyle(FAColor.forestSoft).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "access.closed.safe.title", defaultValue: "Your data is not going anywhere")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Text(String(localized: "access.closed.safe.body", defaultValue: "Your check ins, meals and notes stay in your account. The moment your access reopens, they are exactly where you left them."))
                                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 40).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 4) {
                ForestPillButton(title: isDiscovery
                    ? String(localized: "access.closed.discovery.cta", defaultValue: "Tell us about you")
                    : String(localized: "access.closed.beta.cta", defaultValue: "Talk about what is next")) {
                    openURL(Self.membersRequestURL)
                }
                Button(action: onRecheck) {
                    Text(String(localized: "access.closed.recheck", defaultValue: "I've been given access · check again"))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
            .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
        }
        .faWall()
    }
}
