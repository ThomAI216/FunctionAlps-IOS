import SwiftUI

/// Mirrors the Expo app's `(auth)/login` look: cream page, the mitochondria
/// texture under a cream veil, the FA logo, an italic serif headline and a
/// frosted card with a forest gradient button.
struct LoginView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: LoginViewModel?
    @State private var showPassword = false
    @State private var showDetails = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    // Login-screen palette (from the Expo screen's local constants)
    private let dark = Color(hex: 0x1A1A16)
    private let stone = Color(hex: 0x6B6859)
    private let stoneLight = Color(hex: 0xA8A79E)
    private let forestS = Color(hex: 0x4A8A5C)
    private let errorRed = Color(hex: 0xC0453A)
    private let fieldBorder = Color(hex: 0x1A1A16, opacity: 0.10)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                FAColor.cream.ignoresSafeArea()
                background(geo.size)
                ScrollView {
                    VStack(spacing: 0) {
                        FALogo(height: 96)
                            .padding(.top, 18)
                        headline
                            .padding(.top, 14)
                            .padding(.bottom, 22)
                        if let model { card(model) }
                        footer
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            if model == nil { model = LoginViewModel(auth: dependencies.auth) }
        }
    }

    // Square texture at 135% of the width, centred at 50% / 55%, under a cream veil
    // that is solid at the top and bottom so the texture's edges dissolve.
    private func background(_ size: CGSize) -> some View {
        let side = size.width * 1.35
        return ZStack {
            FABundledImage(name: "mito-mobile", contentMode: .fit)
                .frame(width: side, height: side)
                .position(x: size.width / 2, y: size.height * 0.55)
            LinearGradient(
                stops: [
                    .init(color: FAColor.cream, location: 0),
                    .init(color: FAColor.cream.opacity(0.32), location: 0.32),
                    .init(color: FAColor.cream.opacity(0.32), location: 0.74),
                    .init(color: FAColor.cream, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(String(localized: "login.welcomeTo", defaultValue: "Welcome to").uppercased())
                .font(FATypography.callout)
                .tracking(1)
                .foregroundStyle(stone)
            Text(String(localized: "login.headline", defaultValue: "Your Functional Health Space"))
                .font(.system(size: 27, design: .serif).italic())
                .foregroundStyle(forestS)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    @ViewBuilder
    private func card(_ model: LoginViewModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "login.title", defaultValue: "Sign in"))
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(dark)
            Text(String(localized: "login.welcomeBack", defaultValue: "Welcome back."))
                .font(.system(size: 13))
                .foregroundStyle(stoneLight)
                .padding(.top, 4)

            fieldLabel(String(localized: "login.email", defaultValue: "Email"))
                .padding(.top, 20)
            field {
                TextField("", text: $model.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            fieldLabel(String(localized: "login.password", defaultValue: "Password"))
                .padding(.top, 14)
            field {
                HStack {
                    Group {
                        if showPassword {
                            TextField("", text: $model.password)
                        } else {
                            SecureField("", text: $model.password)
                        }
                    }
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { Task { await model.submit() } }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(stoneLight)
                    }
                    .accessibilityLabel(showPassword
                        ? String(localized: "login.hidePassword", defaultValue: "Hide password")
                        : String(localized: "login.showPassword", defaultValue: "Show password"))
                }
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(errorRed)
                    .padding(.top, 10)
                    .accessibilityLabel(String(localized: "login.errorPrefix", defaultValue: "Sign-in error:") + " " + message)
                if BuildInfo.showsTechnicalDetails, let detail = model.errorDetail {
                    DisclosureGroup(isExpanded: $showDetails) {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(stone)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Text(String(localized: "login.technicalDetails", defaultValue: "Technical details (TestFlight only)"))
                            .font(.system(size: 11))
                            .foregroundStyle(stoneLight)
                    }
                    .tint(stoneLight)
                    .padding(.top, 4)
                }
            }

            gradientButton(model)
                .padding(.top, 18)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: FAColor.forest.opacity(0.18), radius: 24, y: 12)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(stone)
            .padding(.bottom, 6)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 13.5))
            .foregroundStyle(dark)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(fieldBorder, lineWidth: 1))
    }

    private func gradientButton(_ model: LoginViewModel) -> some View {
        Button {
            Task { await model.submit() }
        } label: {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x4A8A5C), Color(hex: 0x306242), Color(hex: 0x284832)], startPoint: .leading, endPoint: .trailing)
                if model.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(String(localized: "login.submit", defaultValue: "Sign in"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .clipShape(Capsule())
        }
        .disabled(!model.canSubmit)
        .opacity(model.canSubmit ? 1 : 0.55)
    }

    private var footer: some View {
        Text(String(localized: "login.help", defaultValue: "Use the same account as the FunctionAlps app and members site."))
            .font(.system(size: 11))
            .foregroundStyle(stoneLight)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    LoginView()
        .environment(AppDependencies.preview(signedIn: false))
}
