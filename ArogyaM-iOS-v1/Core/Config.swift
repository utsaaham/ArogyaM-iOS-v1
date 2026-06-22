import Foundation

/// App configuration.
///
/// The server base URL is user-configurable (set on the login screen) and
/// persisted in `UserDefaults`. Optional health-push credentials may also come
/// from a bundled `.env` file (used only by the legacy HealthKit snapshot push);
/// their absence no longer crashes the app.
enum Config {

    // MARK: - Server base URL (user-configurable)

    private static let baseURLKey = "ArogyaM.baseURL"

    /// Default server URL shown on first launch. Editable on the login screen.
    static let defaultBaseURL = "http://192.168.1.194:30000"

    /// The active backend base URL (no trailing slash).
    static var baseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: baseURLKey)
            let value = (stored?.isEmpty == false ? stored : nil)
                ?? envValue(for: "BASE_URL")
                ?? defaultBaseURL
            return value.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(cleaned, forKey: baseURLKey)
        }
    }

    // MARK: - HealthKit snapshot push credentials

    private static let healthUserKey = "ArogyaM.healthUsername"
    private static let healthKeyKey = "ArogyaM.healthAPIKey"

    /// ArogyaM username used in the health-snapshots push URL.
    /// Prefers the in-app value, falls back to a bundled `.env` `USERNAME`.
    static var healthUsername: String? {
        if let v = UserDefaults.standard.string(forKey: healthUserKey), !v.isEmpty { return v }
        return envValue(for: "USERNAME")
    }

    /// Per-user Health Data API key (Bearer) from ArogyaM settings.
    static var bearerToken: String? {
        if let v = UserDefaults.standard.string(forKey: healthKeyKey), !v.isEmpty { return v }
        return envValue(for: "BEARER_TOKEN")
    }

    static func setHealthUsername(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespaces), forKey: healthUserKey)
    }
    static func setHealthAPIKey(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespaces), forKey: healthKeyKey)
    }

    /// Endpoint for the HealthKit weekly-snapshot push. `nil` when creds are absent.
    static var sendDataURL: String? {
        guard let user = healthUsername, !user.isEmpty else { return nil }
        return "\(baseURL)/api/health-snapshots/\(user)"
    }

    // MARK: - .env loading (optional, bundled)

    private static let values: [String: String] = loadEnvFile()

    private static func envValue(for key: String) -> String? {
        if let v = values[key], !v.isEmpty { return v }
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        return nil
    }

    private static func loadEnvFile() -> [String: String] {
        guard let url = envFileURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var dict: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if val.count >= 2,
               (val.hasPrefix("\"") && val.hasSuffix("\"")) ||
               (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            if !key.isEmpty { dict[key] = val }
        }
        return dict
    }

    private static func envFileURL() -> URL? {
        if let u = Bundle.main.url(forResource: ".env", withExtension: nil) { return u }
        if let u = Bundle.main.url(forResource: "", withExtension: "env") { return u }
        if let resURL = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(
            at: resURL, includingPropertiesForKeys: nil) {
            return items.first { $0.lastPathComponent == ".env" }
        }
        return nil
    }
}
