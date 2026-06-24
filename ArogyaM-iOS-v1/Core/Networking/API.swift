import Foundation

enum NetworkError: LocalizedError {
    case badURL
    case unauthorized
    case http(Int, String)
    case api(String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL. Check the address on the login screen."
        case .unauthorized: return "Your session has expired. Please log in again."
        case .http(let code, let msg): return "Server error \(code): \(msg)"
        case .api(let msg): return msg
        case .decoding(let msg): return "Couldn't read the server response. \(msg)"
        case .transport(let msg): return msg
        }
    }
}

/// Thin async HTTP client over `URLSession`, sharing `HTTPCookieStorage.shared`
/// so the NextAuth session cookie is carried automatically on every request and
/// persisted across launches. All app endpoints wrap data in the
/// `{ success, data, error }` envelope; NextAuth's own endpoints do not, so raw
/// helpers are exposed too.
///
/// `@MainActor` (matching the project's default isolation) so it can freely use
/// `Config` and the Codable model types without cross-actor friction; the actual
/// network I/O happens off-main inside `URLSession.data(for:)`.
@MainActor
final class API {
    static let shared = API()

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Low-level request

    enum Method: String { case GET, POST, PUT, DELETE }

    struct Body {
        var json: Data?
        var form: [String: String]?

        // Explicit nonisolated init so `Body()` can be used as a default
        // argument value (default args evaluate in a nonisolated context,
        // but this type is nested in a @MainActor class).
        nonisolated init(json: Data? = nil, form: [String: String]? = nil) {
            self.json = json
            self.form = form
        }
    }

    /// Performs a request against `Config.baseURL + path`. Returns raw data + response.
    func raw(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: Body = Body(),
        extraHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard var comps = URLComponents(string: Config.baseURL + path) else {
            throw NetworkError.badURL
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw NetworkError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let json = body.json {
            req.httpBody = json
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let form = body.form {
            req.httpBody = Self.encodeForm(form)
            req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw NetworkError.transport((error as NSError).localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw NetworkError.transport("No HTTP response")
        }
        return (data, http)
    }

    // MARK: - Enveloped helpers

    func getEnveloped<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let (data, http) = try await raw(.GET, path, query: query)
        return try decodeEnvelope(data, status: http.statusCode)
    }

    func postEnvelopedJSON<T: Decodable>(_ path: String, json: Data) async throws -> T {
        let (data, http) = try await raw(.POST, path, body: Body(json: json))
        return try decodeEnvelope(data, status: http.statusCode)
    }

    /// POST JSON and verify success without caring about the returned payload.
    func postExpectingSuccess(_ path: String, json: Data) async throws {
        let (data, http) = try await raw(.POST, path, body: Body(json: json))
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        if let env = try? JSONDecoder().decode(APIEnvelope<JSONValue>.self, from: data),
           env.success == false {
            throw NetworkError.api(env.error ?? "Request failed")
        }
        if http.statusCode >= 400 {
            throw NetworkError.http(http.statusCode, "Request failed")
        }
    }

    private func decodeEnvelope<T: Decodable>(_ data: Data, status: Int) throws -> T {
        if status == 401 { throw NetworkError.unauthorized }
        do {
            let env = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
            if env.success == false {
                throw NetworkError.api(env.error ?? "Request failed")
            }
            guard let value = env.data else {
                if status >= 400 {
                    throw NetworkError.http(status, env.error ?? "Request failed")
                }
                throw NetworkError.decoding("Missing data")
            }
            return value
        } catch let e as NetworkError {
            throw e
        } catch {
            if status >= 400 { throw NetworkError.http(status, "Request failed") }
            throw NetworkError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Form encoding

    private static func encodeForm(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}
