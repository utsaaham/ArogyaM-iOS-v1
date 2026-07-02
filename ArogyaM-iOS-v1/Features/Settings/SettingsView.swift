import SwiftUI
import Combine

// MARK: - Store

@MainActor
final class SettingsStore: ObservableObject {
    @Published var user: AppUser?
    @Published var loadedOnce = false

    private let api = API.shared

    func load() async {
        user = try? await api.getEnveloped("/api/user")
        loadedOnce = true
    }
}

// MARK: - View

struct SettingsView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Settings", subtitle: "Your profile and targets").padding(.top, 6)
                profileCard
                targetsCard
                remindersCard
                serverCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROFILE").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            infoRow(icon: "person.fill", tint: Theme.blue, label: "Name",
                    value: store.user?.profile?.name ?? store.user?.username ?? "—")
            infoRow(icon: "envelope.fill", tint: Theme.teal, label: "Email",
                    value: store.user?.email ?? "—")
            if let height = store.user?.profile?.height, height > 0 {
                infoRow(icon: "ruler.fill", tint: Theme.indigo, label: "Height", value: "\(Int(height)) cm")
            }
            if let weight = store.user?.profile?.weight, weight > 0 {
                infoRow(icon: "scalemass.fill", tint: Theme.blue, label: "Weight",
                        value: String(format: "%.1f kg", weight))
            }
            if let goal = store.user?.profile?.goal, !goal.isEmpty {
                infoRow(icon: "target", tint: Theme.green, label: "Goal",
                        value: goal.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            Text("Edit your profile, targets and checklist on the web app — changes show up here right away.")
                .font(Theme.body(12)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var targetsCard: some View {
        let targets = store.user?.targets
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY TARGETS").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                targetTile(icon: "flame.fill", tint: Theme.orange, label: "Calories",
                           value: targets?.dailyCalories.map { "\(Int($0)) kcal" } ?? "—")
                targetTile(icon: "drop.fill", tint: Theme.cyan, label: "Water",
                           value: targets?.dailyWater.map { "\(Int($0)) ml" } ?? "—")
                targetTile(icon: "moon.zzz.fill", tint: Theme.indigo, label: "Sleep",
                           value: targets?.sleepHours.map { "\(Int($0)) h" } ?? "—")
                targetTile(icon: "dumbbell.fill", tint: Theme.red, label: "Workout",
                           value: targets?.dailyWorkoutMinutes.map { "\(Int($0)) min" } ?? "—")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func targetTile(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(Theme.number(15, .bold)).foregroundStyle(Theme.text)
                Text(label).font(Theme.body(11)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private var remindersCard: some View {
        NavigationLink {
            RemindersView()
                .background(Theme.backgroundGradient)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.teal.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                    Text("Water, meal and checklist nudges from Kiki")
                        .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14)
        }
        .buttonStyle(SpringyButtonStyle(scale: 0.98))
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SERVER").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            Text(Config.baseURL)
                .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func infoRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 22)
            Text(label).font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value).font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}
