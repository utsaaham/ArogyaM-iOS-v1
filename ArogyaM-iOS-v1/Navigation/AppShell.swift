import SwiftUI

enum AppTab: CaseIterable {
    case home, vitals, checklist, more
}

struct AppShell: View {
    @State private var tab: AppTab = .home
    @State private var visited: Set<AppTab> = [.home]
    @State private var showAI = false

    /// Scroll views pad their bottom content by this amount so it clears the bar.
    static let bottomBarInset: CGFloat = 124

    var body: some View {
        // Each tab builds lazily on first visit, then stays alive — switching
        // tabs just cross-fades opacity instead of tearing the page down,
        // rebuilding it, and refetching its data every time.
        ZStack {
            ZStack {
                pane(.home) { HomeView() }
                pane(.vitals) { VitalsView() }
                pane(.checklist) { ChecklistView() }
                pane(.more) { MoreView() }
            }
            .animation(.easeInOut(duration: 0.18), value: tab)

            // Tab bar layer ignores the keyboard, so typing slides the
            // keyboard over the bar instead of pushing it up the screen.
            VStack {
                Spacer()
                FloatingTabBar(selected: selectedTab) { showAI = true }
                    .padding(.horizontal, 16)
                    .padding(.bottom, -10)
            }
            .ignoresSafeArea(.keyboard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient)
        .fullScreenCover(isPresented: $showAI) {
            AIAssistantView()
        }
        .task {
            AutoSyncService.shared.start()
            await NotificationService.shared.bootstrap()
        }
    }

    /// Marks tabs visited as they're selected so their pane mounts once.
    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { tab },
            set: { newTab in
                visited.insert(newTab)
                tab = newTab
            }
        )
    }

    @ViewBuilder
    private func pane<Content: View>(_ t: AppTab, @ViewBuilder content: () -> Content) -> some View {
        if visited.contains(t) {
            content()
                .opacity(tab == t ? 1 : 0)
                .allowsHitTesting(tab == t)
        }
    }
}
