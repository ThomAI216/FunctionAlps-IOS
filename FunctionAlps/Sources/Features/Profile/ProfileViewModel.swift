import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var state: Loadable<Member> = .loading
    var isSigningOut = false
    /// nil while loading or when nothing is published — the preview shows the waiting copy.
    private(set) var plan: CarePlan?
    private(set) var planLoading = true
    /// Nil for a client (no deadline) and until the entitlement read lands (never a flash).
    private(set) var countdown: AccessCountdown?
    /// The server composite for the compact trend card; nil renders the dashes.
    private(set) var scores: MemberScores?

    private let members: MemberService
    private let auth: AuthService
    private let profile: ProfileService
    private let backend: any FunctionAlpsBackend

    init(members: MemberService, auth: AuthService, profile: ProfileService, backend: any FunctionAlpsBackend) {
        self.members = members
        self.auth = auth
        self.profile = profile
        self.backend = backend
    }

    func load() async {
        do {
            let member = try await members.currentMember()
            state = .loaded(member)
            let offset = TimeZone.current.secondsFromGMT() / 60
            let backend = self.backend
            async let planRead = profile.carePlan(patientId: member.patientId)
            async let accessRead = profile.access(patientId: member.patientId)
            async let scoresRead: MemberScores? = { try? await backend.memberScores(tzOffsetMinutes: offset) }()
            plan = await planRead
            planLoading = false
            countdown = AccessCountdown.describe(await accessRead)
            scores = await scoresRead
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
