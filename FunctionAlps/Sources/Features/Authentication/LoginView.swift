import SwiftUI

struct LoginView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: LoginViewModel?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            FAColor.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: FASpacing.lg) {
                    header
                    if let model {
                        form(model)
                    }
                }
                .padding(FASpacing.lg)
                .frame(maxWidth: 420)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if model == nil { model = LoginViewModel(auth: dependencies.auth) }
        }
    }

    private var header: some View {
        VStack(spacing: FASpacing.sm) {
            FABrandMark(size: 56)
                .padding(.top, FASpacing.xl)
            Text("FunctionAlps")
                .font(FATypography.largeTitle)
                .foregroundStyle(FAColor.ink)
            Text(String(localized: "login.subtitle", defaultValue: "Connect what you eat and do to how you feel."))
                .font(FATypography.callout)
                .foregroundStyle(FAColor.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func form(_ model: LoginViewModel) -> some View {
        @Bindable var model = model
        FACard {
            VStack(spacing: FASpacing.md) {
                FATextField(
                    label: String(localized: "login.email", defaultValue: "Email"),
                    text: $model.email,
                    kind: .email,
                    submitLabel: .next
                ) { focus = .password }
                .focused($focus, equals: .email)

                FATextField(
                    label: String(localized: "login.password", defaultValue: "Password"),
                    text: $model.password,
                    kind: .password,
                    submitLabel: .go
                ) { Task { await model.submit() } }
                .focused($focus, equals: .password)

                if let message = model.errorMessage {
                    Text(message)
                        .font(FATypography.callout)
                        .foregroundStyle(FAColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "login.errorPrefix", defaultValue: "Sign-in error:") + " " + message)
                }

                FAButton(
                    title: String(localized: "login.submit", defaultValue: "Sign in"),
                    isLoading: model.isSubmitting,
                    isEnabled: model.canSubmit
                ) { Task { await model.submit() } }
            }
        }
        Text(String(localized: "login.help", defaultValue: "Use the same account as the FunctionAlps app and members site."))
            .font(FATypography.caption)
            .foregroundStyle(FAColor.inkMuted)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    LoginView()
        .environment(AppDependencies.preview(signedIn: false))
}
