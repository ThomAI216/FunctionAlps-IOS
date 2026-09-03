import Foundation
import Observation

/// Top-level app phase. Views switch on this; nothing else mutates it except `AuthService`.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn(userId: String)
    }

    var phase: Phase = .launching

    var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }
}
