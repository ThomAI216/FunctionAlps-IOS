import SwiftUI

/// Switches the whole UI on the auth phase. Feature views never check auth themselves.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch state.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.phase)
        .task { await dependencies.auth.restore() }
    }
}

/// Native launch moment: brand mark on cream, nothing else (PRD §22).
struct LaunchView: View {
    var body: some View {
        ZStack {
            FAColor.background.ignoresSafeArea()
            VStack(spacing: FASpacing.md) {
                FALogo(height: 96)
                ProgressView()
                    .tint(FAColor.brand)
                    .padding(.top, FASpacing.lg)
            }
        }
        .accessibilityLabel(String(localized: "app.loading", defaultValue: "Loading FunctionAlps"))
    }
}
