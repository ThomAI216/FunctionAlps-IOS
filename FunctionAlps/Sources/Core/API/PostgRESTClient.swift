import Foundation

/// Typed access to the current data transport (Supabase PostgREST) for the user's
/// OWN rows under RLS. Only `Core/API` may know about tables; features go through
/// services and domain models (PRD §6). Swapping to `api.functionalps.ch` replaces
/// this file and `EdgeFunctionClient`, nothing above them.
struct PostgRESTClient: Sendable {
    private let environment: AppEnvironment
    private let requester: AuthorizedRequester

    init(environment: AppEnvironment, requester: AuthorizedRequester) {
        self.environment = environment
        self.requester = requester
    }

    /// `GET /rest/v1/{table}?{query}` decoded as an array.
    func select<Row: Decodable & Sendable>(_ table: String, query: [URLQueryItem]) async throws -> [Row] {
        let response = try await requester.send { token in
            HTTPRequest(.get, url(table, query: query), headers: headers(token))
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        return try JSON.decode([Row].self, from: response.body)
    }

    /// Single row or nil (uses `limit=1`, never the object header, so 0 rows is not an error).
    func selectOne<Row: Decodable & Sendable>(_ table: String, query: [URLQueryItem]) async throws -> Row? {
        var q = query
        q.append(URLQueryItem(name: "limit", value: "1"))
        let rows: [Row] = try await select(table, query: q)
        return rows.first
    }

    /// `POST /rest/v1/{table}` returning the inserted representation.
    func insert<Body: Encodable & Sendable, Row: Decodable & Sendable>(_ table: String, body: Body) async throws -> Row {
        let response = try await requester.send { token in
            var h = headers(token)
            h["Prefer"] = "return=representation"
            return try HTTPRequest.json(.post, url(table), headers: h, body: body)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        let rows: [Row] = try JSON.decode([Row].self, from: response.body)
        guard let row = rows.first else { throw AppError.decoding(detail: "insert returned no row") }
        return row
    }

    /// `PATCH /rest/v1/{table}?{filter}` with a partial body.
    func update<Body: Encodable & Sendable>(_ table: String, query: [URLQueryItem], body: Body) async throws {
        let response = try await requester.send { token in
            var h = headers(token)
            h["Prefer"] = "return=minimal"
            return try HTTPRequest.json(.patch, url(table, query: query), headers: h, body: body)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
    }

    /// Exact row count via `Prefer: count=exact` + `Content-Range` (`0-0/N` or `*/N`).
    func count(_ table: String, query: [URLQueryItem]) async throws -> Int {
        let q = query + [URLQueryItem(name: "select", value: "id"), URLQueryItem(name: "limit", value: "1")]
        let response = try await requester.send { token in
            var h = headers(token)
            h["Prefer"] = "count=exact"
            return HTTPRequest(.get, url(table, query: q), headers: h)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        let range = response.headers.first { $0.key.lowercased() == "content-range" }?.value ?? ""
        guard let slash = range.lastIndex(of: "/"), let total = Int(range[range.index(after: slash)...]) else {
            throw AppError.decoding(detail: "content-range: \(range)")
        }
        return total
    }

    /// `POST /rest/v1/rpc/{function}` returning a scalar text/uuid (or null).
    func rpcScalar<Body: Encodable & Sendable>(_ function: String, body: Body) async throws -> String? {
        let response = try await requester.send { token in
            try HTTPRequest.json(.post, url("rpc/\(function)"), headers: headers(token), body: body)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        let object = try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])
        if object is NSNull || object == nil { return nil }
        if let s = object as? String { return s }
        throw AppError.decoding(detail: "rpc \(function): expected scalar")
    }

    /// `POST /rest/v1/rpc/{function}`.
    func rpc<Body: Encodable & Sendable, Result: Decodable & Sendable>(_ function: String, body: Body) async throws -> Result {
        let response = try await requester.send { token in
            try HTTPRequest.json(.post, url("rpc/\(function)"), headers: headers(token), body: body)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        return try JSON.decode(Result.self, from: response.body)
    }

    // MARK: Helpers

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: environment.supabaseURL.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func headers(_ token: String) -> [String: String] {
        [
            "apikey": environment.supabasePublishableKey,
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Accept-Profile": "public",
            "Content-Profile": "public",
        ]
    }
}

/// Small PostgREST filter builder so services read like domain code.
enum PG {
    static func eq(_ column: String, _ value: String) -> URLQueryItem { URLQueryItem(name: column, value: "eq.\(value)") }
    static func gte(_ column: String, _ value: String) -> URLQueryItem { URLQueryItem(name: column, value: "gte.\(value)") }
    static func lt(_ column: String, _ value: String) -> URLQueryItem { URLQueryItem(name: column, value: "lt.\(value)") }
    static func select(_ columns: String) -> URLQueryItem { URLQueryItem(name: "select", value: columns) }
    static func order(_ column: String, descending: Bool = false) -> URLQueryItem {
        URLQueryItem(name: "order", value: "\(column).\(descending ? "desc" : "asc")")
    }
    static func limit(_ n: Int) -> URLQueryItem { URLQueryItem(name: "limit", value: String(n)) }
}
