import Foundation
import OSLog

/// Structured development logging (PRD §52). Never log tokens, passwords, keys or
/// full health payloads — pass identifiers and counts, not bodies.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.functionalps.patient"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let data = Logger(subsystem: subsystem, category: "data")

    /// Logs an `AppError` with its developer detail at the right level.
    static func error(_ error: AppError, in logger: Logger, context: StaticString) {
        switch error {
        case .offline, .unauthorized:
            logger.info("\(context, privacy: .public): \(error.debugDescription, privacy: .public)")
        default:
            logger.error("\(context, privacy: .public): \(error.debugDescription, privacy: .public)")
        }
    }
}
