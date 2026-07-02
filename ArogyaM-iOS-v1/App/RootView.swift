import SwiftUI

/// Top-level auth gate: splash while restoring the session, then either the
/// login screen or the main app shell.
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        ZStack {
            Theme.backgroundGradient
            if auth.isCheckingSession {
                SplashView()
            } else if auth.isAuthenticated {
                AppShell()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: auth.isCheckingSession)
        .task { await auth.restoreSession() }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("Kiki")
                .resizable().scaledToFit()
                .frame(width: 120, height: 120)
            Text("ArogyaM")
                .font(Theme.display(34, .bold))
                .foregroundStyle(Theme.text)
            ProgressView().tint(Theme.emerald)
        }
    }
}
