import Foundation

/// Build-time environment, injected from `Config/*.xcconfig` through Info.plist.
/// Nothing here is a secret: the publishable key is a client key protected by RLS.
struct AppEnvironment: Sendable, Equatable {
    enum Name: String, Sendable {
        case development, staging, production
    }

    let name: Name
    /// Supabase project URL (current transport). Read from `FA_SUPABASE_URL`.
    let supabaseURL: URL
    /// Publishable (anon) key sent as the `apikey` header.
    let supabasePublishableKey: String
    /// Optional FunctionAlps-controlled gateway (`api.functionalps.ch`). Nil until it exists.
    let apiBaseURL: URL?

    static func fromBundle(_ bundle: Bundle = .main) throws -> AppEnvironment {
        func string(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let nameRaw = string("FA_ENVIRONMENT_NAME"), let name = Name(rawValue: nameRaw) else {
            throw ConfigurationError.missing("FA_ENVIRONMENT_NAME")
        }
        guard let urlRaw = string("FA_SUPABASE_URL"), let url = URL(string: urlRaw), url.scheme == "https" else {
            throw ConfigurationError.missing("FA_SUPABASE_URL")
        }
        guard let key = string("FA_SUPABASE_PUBLISHABLE_KEY") else {
            throw ConfigurationError.missing("FA_SUPABASE_PUBLISHABLE_KEY")
        }
        let api = string("FA_API_BASE_URL").flatMap(URL.init(string:))
        return AppEnvironment(name: name, supabaseURL: url, supabasePublishableKey: key, apiBaseURL: api)
    }

    enum ConfigurationError: Error, Equatable {
        case missing(String)
    }
}
