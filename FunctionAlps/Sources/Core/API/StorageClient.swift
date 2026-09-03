import Foundation

/// Supabase Storage over plain HTTP: upload, short-lived signed URLs, delete.
/// Buckets are PRIVATE; folder RLS keys on `auth.uid()` (NOT the patient id — see
/// docs/SUPABASE_DEPENDENCY_MAP.md §storage).
struct StorageClient: Sendable {
    private let environment: AppEnvironment
    private let requester: AuthorizedRequester

    init(environment: AppEnvironment, requester: AuthorizedRequester) {
        self.environment = environment
        self.requester = requester
    }

    /// `POST /storage/v1/object/{bucket}/{path}` — never upserts (a second upload is a new object).
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        let response = try await requester.send { token in
            var h = headers(token)
            h["Content-Type"] = contentType
            h["x-upsert"] = "false"
            h["Cache-Control"] = "3600"
            return HTTPRequest(.post, base.appending(path: "object/\(bucket)/\(path)"), headers: h, body: data)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
    }

    /// `POST /storage/v1/object/sign/{bucket}/{path}` → a URL valid for `expiresIn` seconds.
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        struct Body: Encodable, Sendable { let expiresIn: Int }
        struct Response: Decodable, Sendable { let signedURL: String }
        let response = try await requester.send { token in
            try HTTPRequest.json(.post, base.appending(path: "object/sign/\(bucket)/\(path)"), headers: headers(token), body: Body(expiresIn: expiresIn), snakeCase: false)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
        let decoded = try JSON.decode(Response.self, from: response.body)
        let signed = decoded.signedURL
        if signed.lowercased().hasPrefix("http"), let url = URL(string: signed) { return url }
        let relative = signed.hasPrefix("/") ? signed : "/" + signed
        guard let url = URL(string: base.absoluteString + relative) else {
            throw AppError.decoding(detail: "signed url: \(signed)")
        }
        return url
    }

    /// `DELETE /storage/v1/object/{bucket}` with the object list (own folder only under RLS).
    func remove(bucket: String, paths: [String]) async throws {
        struct Body: Encodable, Sendable { let prefixes: [String] }
        guard !paths.isEmpty else { return }
        let response = try await requester.send { token in
            try HTTPRequest.json(.delete, base.appending(path: "object/\(bucket)"), headers: headers(token), body: Body(prefixes: paths), snakeCase: false)
        }
        guard response.isSuccess else { throw AppError.fromStatus(response.status, body: response.body) }
    }

    // MARK: Helpers

    private var base: URL {
        var root = environment.supabaseURL.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + "/storage/v1")!
    }

    private func headers(_ token: String) -> [String: String] {
        [
            "apikey": environment.supabasePublishableKey,
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
        ]
    }
}
