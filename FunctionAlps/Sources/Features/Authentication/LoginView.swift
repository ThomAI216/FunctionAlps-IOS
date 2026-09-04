import AuthenticationServices
import SwiftUI

/// Mirrors the Expo app's `(auth)/login` look: cream page, the mitochondria texture under a cream veil,
/// the FA logo, an italic serif headline and a frosted card that walks the email-first flow.
struct LoginView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: LoginViewModel?
    @State private var showPassword = false
    @State private var showDetails = false
    @State private var legalKey: LegalKey?
    @FocusState private var focus: Field?

    private enum Field { case email, password, confirm, firstName, lastName, phone }
    private struct LegalKey: Identifiable { let id: String }

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
        .sheet(item: $legalKey) { key in
            NavigationStack { LegalDocumentView(key: key.id) }
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

    // MARK: The card, one step at a time

    @ViewBuilder
    private func card(_ model: LoginViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.flow {
            case .email: emailStep(model)
            case .login: loginStep(model)
            case .signup: signupStep(model)
            case .signupDone: inboxStep(
                title: String(localized: "signup.done.title", defaultValue: "Check your inbox"),
                lead: String(localized: "signup.done.lead", defaultValue: "A confirmation email has just been sent to"),
                email: model.capturedEmail,
                trail: String(localized: "signup.done.trail", defaultValue: "Click the link to activate your account."),
                link: nil, onLink: {}
            )
            case .forgot: forgotStep(model)
            case .forgotSent: inboxStep(
                title: String(localized: "forgot.sent.title", defaultValue: "Email sent"),
                lead: String(localized: "forgot.sent.lead", defaultValue: "If an account exists for"),
                email: model.capturedEmail,
                trail: String(localized: "forgot.sent.trail", defaultValue: "a password reset email has been sent."),
                link: String(localized: "forgot.backToSignIn", defaultValue: "Back to sign in"), onLink: { model.show(.login) }
            )
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: FAColor.forest.opacity(0.18), radius: 24, y: 12)
        .animation(.easeInOut(duration: 0.2), value: model.flow)
    }

    /// Google · Apple · or the email address.
    @ViewBuilder
    private func emailStep(_ model: LoginViewModel) -> some View {
        @Bindable var model = model
        Text(String(localized: "login.title", defaultValue: "Sign in"))
            .font(.system(size: 22, design: .serif))
            .foregroundStyle(dark)
        Text(String(localized: "login.emailLead", defaultValue: "Sign in or create your account."))
            .font(.system(size: 13))
            .foregroundStyle(stoneLight)
            .padding(.top, 4)

        socialButtons(model)
            .padding(.top, 18)
        orDivider
            .padding(.vertical, 14)

        fieldLabel(String(localized: "login.email", defaultValue: "Email"))
        field {
            TextField(String(localized: "login.emailPlaceholder", defaultValue: "marie@email.com"), text: $model.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($focus, equals: .email)
                .onSubmit { Task { await model.continueWithEmail() } }
        }
        errorLine(model)
        gradientButton(String(localized: "action.continue", defaultValue: "Continue"), busy: model.isSubmitting, enabled: model.canContinue) {
            Task { await model.continueWithEmail() }
        }
        .padding(.top, 18)
        Text(String(localized: "login.swiss", defaultValue: "Your data stays in Switzerland, private."))
            .font(.system(size: 11))
            .foregroundStyle(stoneLight)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
    }

    @ViewBuilder
    private func loginStep(_ model: LoginViewModel) -> some View {
        @Bindable var model = model
        Text(String(localized: "login.title", defaultValue: "Sign in"))
            .font(.system(size: 22, design: .serif))
            .foregroundStyle(dark)
        Text(String(localized: "login.welcomeBack", defaultValue: "Welcome back."))
            .font(.system(size: 13))
            .foregroundStyle(stoneLight)
            .padding(.top, 4)

        fieldLabel(String(localized: "login.email", defaultValue: "Email")).padding(.top, 20)
        emailReadOnly(model)
        fieldLabel(String(localized: "login.password", defaultValue: "Password")).padding(.top, 14)
        passwordField($model.password, placeholder: "••••••••", contentType: .password, focusKey: .password, submit: .go) { Task { await model.submit() } }
        errorLine(model)
        gradientButton(String(localized: "login.submit", defaultValue: "Sign in"), busy: model.isSubmitting, enabled: model.canSubmit) {
            Task { await model.submit() }
        }
        .padding(.top, 18)
        linkButton(String(localized: "login.forgot", defaultValue: "Forgot password?")) { model.show(.forgot) }
            .padding(.top, 12)
    }

    @ViewBuilder
    private func signupStep(_ model: LoginViewModel) -> some View {
        @Bindable var model = model
        Text(String(localized: "signup.lead", defaultValue: "Not yet a member? Join the FunctionAlps ecosystem."))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(dark)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel(String(localized: "signup.firstName", defaultValue: "First name"))
                field {
                    TextField(String(localized: "signup.firstNamePlaceholder", defaultValue: "Marie"), text: $model.firstName)
                        .textContentType(.givenName).textInputAutocapitalization(.words).submitLabel(.next)
                        .focused($focus, equals: .firstName).onSubmit { focus = .lastName }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel(String(localized: "signup.lastName", defaultValue: "Last name"))
                field {
                    TextField(String(localized: "signup.lastNamePlaceholder", defaultValue: "Dupont"), text: $model.lastName)
                        .textContentType(.familyName).textInputAutocapitalization(.words).submitLabel(.next)
                        .focused($focus, equals: .lastName).onSubmit { focus = .phone }
                }
            }
        }
        .padding(.top, 16)

        fieldLabel(String(localized: "signup.phone", defaultValue: "Phone")).padding(.top, 14)
        field {
            TextField("+41 79 123 45 67", text: $model.phone)
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
                .focused($focus, equals: .phone)
        }

        fieldLabel(String(localized: "login.email", defaultValue: "Email")).padding(.top, 14)
        emailReadOnly(model)

        fieldLabel(String(localized: "login.password", defaultValue: "Password")).padding(.top, 14)
        passwordField($model.password, placeholder: String(localized: "signup.passwordHint", defaultValue: "Min. 8 chars, 1 uppercase, 1 special"), contentType: .newPassword, focusKey: .password, submit: .next) { focus = .confirm }
        passwordChecklist(model.passwordCheck)

        fieldLabel(String(localized: "signup.confirmPassword", defaultValue: "Confirm password")).padding(.top, 14)
        passwordField($model.confirmPassword, placeholder: String(localized: "signup.confirmPlaceholder", defaultValue: "Repeat your password"), contentType: .newPassword, focusKey: .confirm, submit: .done) { focus = nil }
        if !model.confirmPassword.isEmpty, !model.passwordsMatch {
            Text(String(localized: "signup.mismatch", defaultValue: "Passwords do not match."))
                .font(.system(size: 11.5)).foregroundStyle(errorRed).padding(.top, 4)
        }

        consentRow(model).padding(.top, 16)

        errorLine(model)
        gradientButton(String(localized: "signup.cta", defaultValue: "Create my account"), busy: model.isSubmitting, enabled: model.canSignUp) {
            Task { await model.signUp() }
        }
        .padding(.top, 18)
        linkButton(String(localized: "signup.alreadyMember", defaultValue: "Already a member? Sign in")) { model.show(.login) }
            .padding(.top, 12)
    }

    @ViewBuilder
    private func forgotStep(_ model: LoginViewModel) -> some View {
        Text(String(localized: "forgot.title", defaultValue: "Reset your password"))
            .font(.system(size: 22, design: .serif))
            .foregroundStyle(dark)
        Text(String(localized: "forgot.lead", defaultValue: "A reset link will be sent to your email address."))
            .font(.system(size: 13))
            .foregroundStyle(stoneLight)
            .padding(.top, 4)
        fieldLabel(String(localized: "login.email", defaultValue: "Email")).padding(.top, 20)
        emailReadOnly(model)
        gradientButton(String(localized: "forgot.cta", defaultValue: "Send reset link"), busy: model.isSubmitting, enabled: !model.isSubmitting) {
            Task { await model.requestReset() }
        }
        .padding(.top, 18)
        linkButton(String(localized: "action.back", defaultValue: "Back")) { model.show(.login) }
            .padding(.top, 12)
    }

    /// The two envelope states: sign-up confirmation and the reset link.
    private func inboxStep(title: String, lead: String, email: String, trail: String, link: String?, onLink: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color(hex: 0x4A8A5C, opacity: 0.16))
                Image(systemName: "envelope").font(.system(size: 20, weight: .medium)).foregroundStyle(forestS)
            }
            .frame(width: 48, height: 48)
            .padding(.bottom, 14)
            Text(title).font(.system(size: 22, design: .serif)).foregroundStyle(dark)
            (Text(lead + " ").foregroundColor(stone) + Text(email).font(.system(size: 13.5, weight: .bold)).foregroundColor(dark) + Text(". " + trail).foregroundColor(stone))
                .font(.system(size: 13.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
            if let link {
                Button(action: onLink) {
                    Text(link).font(.system(size: 12)).foregroundStyle(forestS).underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    private func socialButtons(_ model: LoginViewModel) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await model.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Image("GoogleG").resizable().frame(width: 18, height: 18)
                    Text(String(localized: "login.google", defaultValue: "Continue with Google"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(dark)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(fieldBorder, lineWidth: 1))
            }
            .disabled(model.isSocialBusy)

            SignInWithAppleButton(.continue) { request in
                model.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await model.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
            .clipShape(Capsule())
            .disabled(model.isSocialBusy)
        }
        .overlay {
            if model.isSocialBusy { ProgressView().tint(forestS) }
        }
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
            Text(String(localized: "login.or", defaultValue: "or"))
                .font(.system(size: 12))
                .foregroundStyle(stoneLight)
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
        }
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

    /// The captured address, read-only, with "change" back to the email step.
    private func emailReadOnly(_ model: LoginViewModel) -> some View {
        HStack {
            Text(model.capturedEmail).font(.system(size: 13.5)).foregroundStyle(dark).lineLimit(1)
            Spacer()
            Button { model.backToEmail() } label: {
                Text(String(localized: "login.changeEmail", defaultValue: "change")).font(.system(size: 11.5)).foregroundStyle(forestS).underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(fieldBorder, lineWidth: 1))
    }

    private func passwordField(_ text: Binding<String>, placeholder: String, contentType: UITextContentType, focusKey: Field, submit: SubmitLabel, onSubmit: @escaping () -> Void) -> some View {
        field {
            HStack {
                Group {
                    if showPassword {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submit)
                .focused($focus, equals: focusKey)
                .onSubmit(onSubmit)
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
    }

    private func passwordChecklist(_ check: OnboardingLogic.PasswordCheck) -> some View {
        let items: [(Bool, String)] = [
            (check.length, String(localized: "signup.pw.length", defaultValue: "At least 8 characters")),
            (check.upper, String(localized: "signup.pw.upper", defaultValue: "One uppercase letter")),
            (check.special, String(localized: "signup.pw.special", defaultValue: "One special character")),
        ]
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: item.0 ? "checkmark.circle.fill" : "circle").font(.system(size: 11)).foregroundStyle(item.0 ? forestS : stoneLight)
                    Text(item.1).font(.system(size: 11.5)).foregroundStyle(item.0 ? forestS : stoneLight)
                }
            }
        }
        .padding(.top, 8)
    }

    /// The tick that gates account creation (NOT the legal record — that is the consent gate on first launch).
    private func consentRow(_ model: LoginViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.consent.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(model.consent ? forestS : .clear)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(model.consent ? forestS : fieldBorder, lineWidth: 1.5)
                    if model.consent { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: 18, height: 18).padding(.top, 1).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "signup.consent.a11y", defaultValue: "I accept the Terms of Service and the Privacy Policy"))
            .accessibilityAddTraits(model.consent ? [.isSelected] : [])
            VStack(alignment: .leading, spacing: 2) {
                Button { model.consent.toggle() } label: {
                    Text(String(localized: "signup.consent.lead", defaultValue: "By creating my account, I accept the"))
                        .font(.system(size: 11.5)).foregroundStyle(stone).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                HStack(spacing: 4) {
                    Button { legalKey = LegalKey(id: "terms_of_use") } label: {
                        Text(String(localized: "signup.consent.terms", defaultValue: "Terms of Service")).font(.system(size: 11.5)).foregroundStyle(forestS).underline()
                    }
                    .buttonStyle(.plain)
                    Text(String(localized: "signup.consent.and", defaultValue: "and the")).font(.system(size: 11.5)).foregroundStyle(stone)
                    Button { legalKey = LegalKey(id: "privacy_policy") } label: {
                        Text(String(localized: "signup.consent.privacy", defaultValue: "Privacy Policy")).font(.system(size: 11.5)).foregroundStyle(forestS).underline()
                    }
                    .buttonStyle(.plain)
                }
                Text(String(localized: "signup.consent.trail", defaultValue: "including non-clinical AI analysis of my meals and check-ins."))
                    .font(.system(size: 11.5)).foregroundStyle(stone).lineSpacing(3)
            }
        }
    }

    @ViewBuilder
    private func errorLine(_ model: LoginViewModel) -> some View {
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
    }

    private func gradientButton(_ title: String, busy: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x4A8A5C), Color(hex: 0x306242), Color(hex: 0x284832)], startPoint: .leading, endPoint: .trailing)
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .clipShape(Capsule())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(stoneLight).underline()
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
