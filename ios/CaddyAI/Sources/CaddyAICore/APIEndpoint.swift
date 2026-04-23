import Foundation

/// URL construction for backend requests. Pulled into CaddyAICore so
/// we can exercise it from Linux CI — `APIClient` in the app target
/// depends on Foundation-only behaviour anyway.
///
/// We deliberately avoid `URL.appendingPathComponent` because it
/// treats its argument as a path component and percent-encodes `?`
/// into `%3F`, silently breaking any request that carries a query
/// string. Instead we split path and query via `URLComponents`.
public enum APIEndpoint {
    public enum Error: Swift.Error, Equatable {
        case invalidBaseURL(String)
        case couldNotBuildURL(String)
    }

    public static func url(
        base: URL,
        path: String,
        query: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw Error.invalidBaseURL(base.absoluteString)
        }
        let basePath = components.path
        let joined: String
        if path.hasPrefix("/") {
            joined = basePath.hasSuffix("/")
                ? String(basePath.dropLast()) + path
                : basePath + path
        } else if path.isEmpty {
            joined = basePath
        } else {
            joined = basePath.hasSuffix("/") ? basePath + path : basePath + "/" + path
        }
        components.path = joined
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw Error.couldNotBuildURL(path)
        }
        return url
    }
}
