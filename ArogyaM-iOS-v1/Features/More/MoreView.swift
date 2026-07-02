import SwiftUI

/// The "More" tab — a glass launcher for the pages that don't live on the
/// main bar. Each destination gets a big tactile card that pushes the full
/// page inside its own navigation stack.
struct MoreView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SectionTitle(title: "More", subtitle: "Everything else, one tap away")
                        .padding(.top, 6)

                    destinationCard(
                        title: "Sleep",
                        subtitle: "Log last night and see how you have been resting",
                        icon: "moon.zzz.fill",
                        tint: Theme.indigo
                    ) {
                        SleepView()
                    }

                    destinationCard(
                        title: "Water",
                        subtitle: "Stay hydrated with quick-add logging",
                        icon: "drop.fill",
                        tint: Theme.cyan
                    ) {
                        WaterView()
                    }

                    destinationCard(
                        title: "Food",
                        subtitle: "Search foods, log meals and track macros",
                        icon: "fork.knife",
                        tint: Theme.orange
                    ) {
                        FoodView()
                    }

                    destinationCard(
                        title: "Workout",
                        subtitle: "Log sessions and watch your training add up",
                        icon: "dumbbell.fill",
                        tint: Theme.red
                    ) {
                        WorkoutView()
                    }

                    destinationCard(
                        title: "Weight",
                        subtitle: "Track your weight against your goal",
                        icon: "scalemass.fill",
                        tint: Theme.blue
                    ) {
                        WeightView()
                    }

                    destinationCard(
                        title: "Achievements",
                        subtitle: "Streaks, badges and your XP level",
                        icon: "trophy.fill",
                        tint: Theme.gold
                    ) {
                        AchievementsView()
                    }

                    destinationCard(
                        title: "Health Sync",
                        subtitle: "Pull Apple Health data and push it to ArogyaM",
                        icon: "heart.text.square.fill",
                        tint: Theme.rose
                    ) {
                        HealthSyncView()
                    }

                    destinationCard(
                        title: "Project",
                        subtitle: "ArogyaM is open source — peek under the hood",
                        icon: "chevron.left.forwardslash.chevron.right",
                        tint: Theme.purple
                    ) {
                        ProjectView()
                    }

                    destinationCard(
                        title: "Settings",
                        subtitle: "Profile, targets and reminder nudges",
                        icon: "gearshape.fill",
                        tint: Theme.textSecondary
                    ) {
                        SettingsView()
                    }

                    logoutButton
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, AppShell.bottomBarInset)
            }
            .scrollIndicators(.hidden)
            .background(Theme.backgroundGradient)
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive) { auth.logout() } label: {
            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(Theme.body(16, .semibold)).foregroundStyle(Theme.rose)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.rose.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func destinationCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .background(Theme.backgroundGradient)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.display(18, .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: tint, padding: 16)
        }
        .buttonStyle(SpringyButtonStyle(scale: 0.97))
    }
}
