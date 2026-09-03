import SwiftUI

struct ProfileView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: ProfileViewModel?
    @State private var confirmSignOut = false

    var body: some View {
        ZStack {
            FAColor.background.ignoresSafeArea()
            if let model { content(model) }
        }
        .navigationTitle(String(localized: "profile.title", defaultValue: "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = ProfileViewModel(members: dependencies.members, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ProfileViewModel) -> some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "profile.error.title", defaultValue: "Couldn't load your profile"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            VStack(spacing: FASpacing.lg) {
                FAEmptyState(
                    title: String(localized: "home.notRegistered.title", defaultValue: "Almost there"),
                    message: String(localized: "home.notRegistered.message", defaultValue: "This account isn't linked to a FunctionAlps client profile yet. Finish onboarding on the FunctionAlps web app, then come back."),
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                signOutButton(model)
            }
            .padding(FASpacing.lg)
        case .loaded(let member):
            ScrollView {
                VStack(spacing: FASpacing.lg) {
                    header(member)
                    details(member.profile)
                    FACard {
                        NavigationLink(value: Route.settings) {
                            FAListRow(title: String(localized: "profile.settings", defaultValue: "Settings"), subtitle: nil, systemImage: "gearshape")
                        }
                        .buttonStyle(.plain)
                    }
                    signOutButton(model)
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.top, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
    }

    private func header(_ member: Member) -> some View {
        VStack(spacing: FASpacing.sm) {
            ZStack {
                Circle().fill(FAColor.forestGlow)
                Text(String(member.firstName.prefix(1)).uppercased())
                    .font(FATypography.largeTitle)
                    .foregroundStyle(FAColor.forest)
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
            Text(member.displayName)
                .font(FATypography.title)
                .foregroundStyle(FAColor.ink)
            Text(String(localized: "profile.client", defaultValue: "FunctionAlps client"))
                .font(FATypography.caption)
                .foregroundStyle(FAColor.inkSecondary)
            if let email = member.email {
                Text(email).font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func details(_ profile: MemberProfile?) -> some View {
        FASection(title: String(localized: "profile.details", defaultValue: "Your baseline")) {
            if let profile {
                FACard {
                    VStack(spacing: 0) {
                        row(String(localized: "profile.age", defaultValue: "Age"), profile.age.map { "\($0)" })
                        row(String(localized: "profile.height", defaultValue: "Height"), profile.heightCm.map { "\(Int($0)) cm" })
                        row(String(localized: "profile.weight", defaultValue: "Weight"), profile.weightKg.map { "\(Int($0)) kg" })
                        row(String(localized: "profile.activity", defaultValue: "Activity"), profile.activityLevel)
                        row(String(localized: "profile.goal", defaultValue: "Goal"), profile.goalMode?.rawValue.capitalized)
                        row(String(localized: "profile.diet", defaultValue: "Diet"), profile.dietaryPattern)
                        if !profile.healthGoals.isEmpty {
                            row(String(localized: "profile.goals", defaultValue: "Health goals"), profile.healthGoals.joined(separator: ", "))
                        }
                        if !profile.currentComplaints.isEmpty {
                            row(String(localized: "profile.complaints", defaultValue: "Focus areas"), profile.currentComplaints.joined(separator: ", "))
                        }
                    }
                }
            } else {
                FACard {
                    FAEmptyState(
                        title: String(localized: "profile.noProfile.title", defaultValue: "No baseline yet"),
                        message: String(localized: "profile.noProfile.message", defaultValue: "Complete onboarding in FunctionAlps to see your baseline here."),
                        systemImage: "figure.walk"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                Spacer()
                Text(value).font(FATypography.body).foregroundStyle(FAColor.ink).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, FASpacing.sm)
            .accessibilityElement(children: .combine)
            Divider().overlay(FAColor.separator)
        }
    }

    private func signOutButton(_ model: ProfileViewModel) -> some View {
        FAButton(title: String(localized: "profile.signOut", defaultValue: "Sign out"), style: .destructive, isLoading: model.isSigningOut) {
            confirmSignOut = true
        }
        .confirmationDialog(String(localized: "profile.signOut.confirm", defaultValue: "Sign out of FunctionAlps?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(String(localized: "profile.signOut", defaultValue: "Sign out"), role: .destructive) {
                Task { await model.signOut() }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(AppDependencies.preview())
}
