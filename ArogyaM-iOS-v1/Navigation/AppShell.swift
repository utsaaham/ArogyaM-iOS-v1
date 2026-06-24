import SwiftUI

enum AppTab: CaseIterable {
    case home, water, food, health
}

struct AppShell: View {
    @State private var tab: AppTab = .home
    @State private var showAI = false

    /// Scroll views pad their bottom content by this amount so it clears the bar.
    static let bottomBarInset: CGFloat = 124

    var body: some View {
        // Feature content — respects the safe area so scroll content sits
        // below the status bar / Dynamic Island.
        Group {
            switch tab {
            case .home:   HomeView()
            case .water:  WaterView()
            case .food:   FoodView()
            case .health: HealthSyncView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(tab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: tab)
        // Dark ambient background fills the whole screen, behind the status
        // bar and home indicator.
        .background(deepBackground.ignoresSafeArea())
        // Tab bar floats above the content as an overlay, so its width can
        // never stretch the content past the screen edges.
        .overlay(alignment: .bottom) {
            FloatingTabBar(selected: $tab) { showAI = true }
                .padding(.horizontal, 16)
                .padding(.bottom, -10)
        }
        .fullScreenCover(isPresented: $showAI) {
            AIAssistantView()
        }
    }

    // MARK: - Background

    private var deepBackground: some View {
        Theme.backgroundGradient
    }
}
