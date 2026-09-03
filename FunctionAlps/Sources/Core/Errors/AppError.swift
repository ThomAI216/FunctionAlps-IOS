import Foundation

/// The single error vocabulary the UI understands (PRD §43).
/// Transport/decoding details stay in `debugDescription` for development logs;
/// users only ever see `userMessage`.
enum AppError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    case forbidden
    case notFound
    case validation(message: String)
    case invalidCredentials
    case server(status: Int)
    case decoding(detail: String)
    case network(detail: String)
    case configuration(detail: String)
    case unknown(detail: String)

    /// User-safe, localized message. Never contains raw technical text.
    var userMessage: String {
        switch self {
        case .offline:
            return String(localized: "error.offline", defaultValue: "You appear to be offline. Check your connection and try again.")
        case .unauthorized:
            return String(localized: "error.unauthorized", defaultValue: "Your session has expired. Please sign in again.")
        case .forbidden:
            return String(localized: "error.forbidden", defaultValue: "You don't have access to this.")
        case .notFound:
            return String(localized: "error.notFound", defaultValue: "We couldn't find what you were looking for.")
        case .validation(let message):
            return message
        case .invalidCredentials:
            return String(localized: "error.invalidCredentials", defaultValue: "Email or password is incorrect.")
        case .server:
            return String(localized: "error.server", defaultValue: "FunctionAlps is having a problem right now. Please try again shortly.")
        case .decoding, .network, .configuration, .unknown:
            return String(localized: "error.generic", defaultValue: "Something went wrong. Please try again.")
        }
    }

    /// Developer-facing detail for logs. Never shown to users.
    var debugDescription: String {
        switch self {
        case .offline: return "offline"
        case .unauthorized: return "unauthorized (401)"
        case .forbidden: return "forbidden (403)"
        case .notFound: return "not found (404)"
        case .validation(let m): return "validation: \(m)"
        case .invalidCredentials: return "invalid credentials"
        case .server(let s): return "server error \(s)"
        case .decoding(let d): return "decoding: \(d)"
        case .network(let d): return "network: \(d)"
        case .configuration(let d): return "configuration: \(d)"
        case .unknown(let d): return "unknown: \(d)"
        }
    }

    /// Maps an HTTP status to the closest domain error. 2xx never reaches here.
    static func fromStatus(_ status: Int, body: Data) -> AppError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 400, 409, 422:
            let message = ErrorBody.message(from: body)
            return .validation(message: message ?? String(localized: "error.validation", defaultValue: "Please check what you entered."))
        case 500...599: return .server(status: status)
        default: return .unknown(detail: "http \(status)")
        }
    }
}

/// Best-effort extraction of a human message from Supabase / PostgREST / GoTrue error bodies.
enum ErrorBody {
    private struct Shape: Decodable {
        let message: String?
        let msg: String?
        let error_description: String?
        let error: String?
        let error_code: String?
        let code: StringOrInt?
        let hint: String?
        let details: String?
    }
    private enum StringOrInt: Decodable {
        case string(String), int(Int)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            self = .string(try c.decode(String.self))
        }
    }

    static func message(from data: Data) -> String? {
        guard !data.isEmpty, let shape = try? JSONDecoder().decode(Shape.self, from: data) else { return nil }
        return shape.message ?? shape.msg ?? shape.error_description ?? shape.details ?? shape.error
    }

    static func errorCode(from data: Data) -> String? {
        guard !data.isEmpty, let shape = try? JSONDecoder().decode(Shape.self, from: data) else { return nil }
        return shape.error_code ?? shape.error
    }
}
