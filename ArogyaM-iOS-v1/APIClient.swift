import Foundation

enum APIError: LocalizedError {
    case badURL
    case encoding(Error)
    case transport(Int, String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The server address looks off. Check it on the login screen."
        case .encoding(let e):
            return "Encoding error: \(e.localizedDescription)"
        case .transport(let code, let msg):
            switch code {
            case -1009: return "❌ No internet right now. Check your connection and try again."
            case -1004: return "❌ Couldn't reach the server. Is it up and running?"
            case -1003: return "❌ Server not found. Check the address on the login screen."
            case -1001: return "❌ That took too long and timed out. Give it another try."
            default:    return "❌ Error \(code): \(msg)"
            }
        case .http(let status, let body):
            if status == 401 { return "❌ The server said no (401). Check your Health API key in settings." }
            return "❌ HTTP \(status): \(body)"
        }
    }
}

struct APIClient {
    static let shared = APIClient()

    func send(_ payload: WeeklyHealthPayload) async throws {
        guard let endpoint = Config.sendDataURL, let url = URL(string: endpoint),
              let token = Config.bearerToken, !token.isEmpty else {
            throw APIError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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
