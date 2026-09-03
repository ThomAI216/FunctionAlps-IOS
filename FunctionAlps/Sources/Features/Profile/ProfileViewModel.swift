import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var state: Loadable<Member> = .loading
    var isSigningOut = false

    private let members: MemberService
    private let auth: AuthService

    init(members: MemberService, auth: AuthService) {
        self.members = members
        self.auth = auth
    }

    func load() async {
        do {
            state = .loaded(try await members.currentMember())
        } catch MemberService.MemberError.notRegistered {
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "profile.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            state = .failed(error)
        } catch {
            state = .failed(.unknown(detail: String(describing: error)))
        }
    }

    func signOut() async {
        isSigningOut = true
        await auth.signOut()
        isSigningOut = false
    }
}
