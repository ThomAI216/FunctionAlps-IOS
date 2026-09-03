import Foundation

/// Minimal, testable HTTP layer. No third-party networking dependency (PRD §13).
struct HTTPRequest: Sendable, Equatable {
    enum Method: String, Sendable { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    var method: Method
    var url: URL
    var headers: [String: String] = [:]
    var body: Data? = nil

    init(_ method: Method, _ url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    static func json(_ method: Method, _ url: URL, headers: [String: String] = [:], body: some Encodable) throws -> HTTPRequest {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var h = headers
        h["Content-Type"] = "application/json"
        return HTTPRequest(method, url, headers: h, body: try encoder.encode(body))
    }
}

struct HTTPResponse: Sendable, Equatable {
    let status: Int
    let headers: [String: String]
    let body: Data

    var isSuccess: Bool { (200..<300).contains(status) }
}

/// The seam for tests: `MockTransport` replaces `URLSessionTransport` without touching services.
protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "FunctionAlps-iOS/\(AppInfo.version) (\(AppInfo.build))"]
        return URLSession(configuration: config)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                throw AppError.offline
            default:
                throw AppError.network(detail: error.localizedDescription)
            }
        } catch {
            throw AppError.network(detail: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network(detail: "non-HTTP response")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k] = v }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

/// Shared JSON decoding with the conventions of the FunctionAlps backend
/// (snake_case keys, ISO-8601 timestamps with fractional seconds from Postgres).
enum JSON {
    /// A fresh decoder per call: JSONDecoder is a class and Swift 6 will not let a
    /// shared instance cross isolation domains. Construction is cheap.
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(detail: String(describing: error))
        }
    }
}

enum ISO8601 {
    // ISO8601DateFormatter is documented thread-safe but is not marked Sendable;
    // the instances are immutable after configuration, hence nonisolated(unsafe).
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Accepts `2026-09-02T14:03:11.123456+00:00`, `2026-09-02T14:03:11Z`, `2026-09-02`.
    static func parse(_ raw: String) -> Date? {
        // Postgres emits up to 6 fractional digits; ISO8601DateFormatter wants at most 3.
        let normalised = truncateFraction(raw)
        return withFraction.date(from: normalised) ?? plain.date(from: normalised) ?? dateOnly.date(from: raw)
    }

    static func truncateFraction(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        let afterDot = raw.index(after: dot)
        var end = afterDot
        while end < raw.endIndex, raw[end].isNumber { end = raw.index(after: end) }
        let digits = raw[afterDot..<end]
        guard digits.count > 3 else { return raw }
        return String(raw[..<afterDot]) + digits.prefix(3) + String(raw[end...])
    }

    static func string(_ date: Date) -> String { withFraction.string(from: date) }
    /// `YYYY-MM-DD` in the user's calendar/time zone (the app's "day" boundary).
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = calendar.timeZone
        return f.string(from: date)
    }
}
