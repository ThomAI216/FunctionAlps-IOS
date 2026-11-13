import Foundation

/// A counter the write paths bump and the screens that cache a read compare against: "something Home shows
/// changed since I last loaded". It carries no data — only a number — so it is safe to share across
/// isolation domains. Home reloads on re-appear when it is older than its staleness window OR this moved.
final class DataFreshness: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Bumped after any write that Home's snapshot reflects (a check-in, a meal added, edited or removed).
    func homeChanged() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    var homeVersion: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
