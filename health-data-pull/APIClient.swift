import Foundation

enum APIError: LocalizedError {
    case badURL
    case encoding(Error)
    case transport(Int, String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Bad URL — check Config.sendDataURL"
        case .encoding(let e):
            return "Encoding error: \(e.localizedDescription)"
        case .transport(let code, let msg):
            switch code {
            case -1009: return "❌ No network connection (code -1009)"
            case -1004: return "❌ Cannot connect to server (code -1004)"
            case -1003: return "❌ Server not found — check Config.baseURL (code -1003)"
            case -1001: return "❌ Request timed out (code -1001)"
            default:    return "❌ Error \(code): \(msg)"
            }
        case .http(let status, let body):
            if status == 401 { return "❌ Unauthorised (401) — bearer token mismatch" }
            return "❌ HTTP \(status): \(body)"
        }
    }
}

struct APIClient {
    static let shared = APIClient()

    func send(_ payload: WeeklyHealthPayload) async throws {
        guard let url = URL(string: Config.sendDataURL) else {
            throw APIError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Config.bearerToken)", forHTTPHeaderField: "Authorization")

        do {
            req.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw APIError.encoding(error)
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            let ns = error as NSError
            throw APIError.transport(ns.code, ns.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw APIError.http(http.statusCode, body)
        }
    }
}
