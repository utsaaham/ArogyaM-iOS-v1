import Foundation
import SwiftUI
import Combine

/// Drives authentication against arogyamandiram's existing NextAuth endpoints
/// (no backend changes). Relies on `HTTPCookieStorage.shared` (via the `API`
/// actor's session) to carry and persist the session-token cookie.
@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var isLoading = false
    @Published var isCheckingSession = true
    @Published var errorMessage: String?

    private let api = API.shared

    private struct CSRF: Decodable { let csrfToken: String }

    /// Called on launch — restores the session from the persisted cookie.
    func restoreSession() async {
        isCheckingSession = true
        await verify()
        isCheckingSession = false
    }

    /// NextAuth credentials sign-in: csrf -> callback -> verify.
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // 1. CSRF token (NextAuth's own JSON, not enveloped)
            let (csrfData, csrfHTTP) = try await api.raw(.GET, "/api/auth/csrf")
            guard csrfHTTP.statusCode == 200,
                  let csrf = try? JSONDecoder().decode(CSRF.self, from: csrfData).csrfToken else {
                errorMessage = "Couldn't reach the server. Check the address and try again."
                return
            }

            // 2. Credentials callback — NextAuth sets the session cookie on success.
            _ = try await api.raw(
                .POST,
                "/api/auth/callback/credentials",
                body: .init(form: [
                    "csrfToken": csrf,
                    "email": email,
                    "password": password,
                    "json": "true",
                    "callbackUrl": Config.baseURL,
                ]),
                extraHeaders: ["X-Auth-Return-Redirect": "1"]
            )

            // 3. Verify the session is valid and load the user.
            if await loadUser() {
                isAuthenticated = true
            } else {
                errorMessage = "Invalid email or password."
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        clearCookies()
        currentUser = nil
        isAuthenticated = false
    }

    func setServerURL(_ url: String) {
        Config.baseURL = url
    }

    // MARK: - Helpers

    private func verify() async {
        if await loadUser() {
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
    }

    /// Returns true if a valid session loaded the current user.
    private func loadUser() async -> Bool {
        do {
            let user: AppUser = try await api.getEnveloped("/api/user")
            currentUser = user
            return true
        } catch {
            return false
        }
    }

    private func clearCookies() {
        guard let host = URL(string: Config.baseURL)?.host else { return }
        let store = HTTPCookieStorage.shared
        for cookie in store.cookies ?? [] {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            if host == domain || host.hasSuffix(domain) || domain.hasSuffix(host) {
                store.deleteCookie(cookie)
            }
        }
    }
}
