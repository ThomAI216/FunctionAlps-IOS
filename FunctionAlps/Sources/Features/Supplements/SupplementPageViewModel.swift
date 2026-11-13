import Foundation
import Observation

/// One supplement's page: what it shows and the ticks, over the shared `SupplementService`. The blocks themselves are
/// decided by `SupplementPageBlocks` (pure, tested).
@MainActor
@Observable
final class SupplementPageViewModel {
    let supplementId: String
    private let service: SupplementService
    private let notifications: NotificationService

    init(supplementId: String, service: SupplementService, notifications: NotificationService) {
        self.supplementId = supplementId
        self.service = service
        self.notifications = notifications
    }

    var phase: SupplementService.Phase { service.phase }
    var supplement: Supplement? { service.supplement(id: supplementId) }
    var tickError: String? { service.tickError }

    func load() async {
        if case .idle = service.phase { await service.load() }
    }

    func retry() async { await service.retry() }

    func setTaken(_ taken: Bool, moment: SupplementMoment) async {
        await service.setTaken(taken, supplementId: supplementId, moment: moment)
    }

    // MARK: Blocks

    /// The ticks of today: one per moment, only while the supplement is active and due today.
    func toggles(_ s: Supplement) -> [SupplementTick] {
        guard s.isActive, s.dueToday else { return [] }
        return s.slots.map { SupplementTick(moment: $0, taken: s.isTaken($0), takenAt: s.takenAt($0)) }
    }

    func why(_ s: Supplement) -> String? { SupplementPageBlocks.why(s) }
    func bodyEffect(_ s: Supplement) -> SupplementPageBlocks.BodyEffect? { SupplementPageBlocks.bodyEffect(s) }
    func howToTake(_ s: Supplement) -> [String] { SupplementPageBlocks.howToTake(s) }
    func brand(_ s: Supplement) -> SupplementPageBlocks.Brand? { SupplementPageBlocks.brand(s) }
    func prescribed(_ s: Supplement) -> SupplementPageBlocks.Prescribed? { SupplementPageBlocks.prescribed(s) }

    func reminderLine(_ s: Supplement) -> String? { SupplementLogic.reminderLine(s, prefs: notifications.prefs) }
}

/// One tick of today on the page: a moment, taken or not, and when.
struct SupplementTick: Identifiable, Sendable, Equatable {
    let moment: SupplementMoment
    let taken: Bool
    let takenAt: Date?
    var id: String { moment.rawValue }
}
