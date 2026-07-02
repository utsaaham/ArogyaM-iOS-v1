import SwiftUI
import Combine

// MARK: - Store (/api/achievements — models live in AppModels.swift)

@MainActor
final class AchievementsStore: ObservableObject {
    @Published var data: AchievementsResponse?
    @Published var loadedOnce = false

    private let api = API.shared

    func load() async {
        data = try? await api.getEnveloped("/api/achievements")
        loadedOnce = true
    }
}

// MARK: - View

struct AchievementsView: View {
    @StateObject private var store = AchievementsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Achievements", subtitle: "Streaks, badges and XP").padding(.top, 6)
                levelCard
                streaksCard
                badgesCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    private var levelCard: some View {
        let percent = (store.data?.xpPercent ?? 0) / 100
        return VStack(spacing: 16) {
            ProgressRing(progress: percent, tint: Theme.gold, size: 150, lineWidth: 14) {
                VStack(spacing: 2) {
                    Text("Lv \(store.data?.level ?? 1)")
                        .font(Theme.number(30, .bold)).foregroundStyle(Theme.text)
                    Text("\(store.data?.xpTotal ?? 0) XP")
                        .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
            }
            if let into = store.data?.xpIntoLevel, let forLevel = store.data?.xpForCurrentLevel, forLevel > 0 {
                Text("\(into) / \(forLevel) XP to the next level")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassCard(padding: 22)
    }

    private var streaksCard: some View {
        let current = store.data?.achievements?.streaks?.current
        let tiles: [(icon: String, tint: Color, label: String, days: Int?)] = [
            ("flame.fill", Theme.orange, "Logging", current?.logging),
            ("drop.fill", Theme.cyan, "Water", current?.water),
            ("dumbbell.fill", Theme.red, "Workout", current?.workout),
            ("moon.zzz.fill", Theme.indigo, "Sleep", current?.sleep),
            ("fork.knife", Theme.green, "Calories", current?.calories),
            ("scalemass.fill", Theme.blue, "Weight", current?.weight),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("CURRENT STREAKS").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(spacing: 6) {
                        Image(systemName: tile.icon)
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(tile.tint)
                        Text("\(tile.days ?? 0)d")
                            .font(Theme.number(18, .bold)).foregroundStyle(Theme.text)
                        Text(tile.label).font(Theme.body(11)).foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var badgesCard: some View {
        let badges = store.data?.achievements?.badges ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("BADGES").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            if badges.isEmpty {
                Text(store.loadedOnce
                     ? "No badges yet. Keep logging — the first ones come quickly."
                     : "Loading…")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.gold.opacity(0.14)).frame(width: 44, height: 44)
                        Text(badge.icon ?? "🏅").font(.system(size: 22))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.name ?? "Badge")
                            .font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                        if let desc = badge.description, !desc.isEmpty {
                            Text(desc).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let earned = badge.earnedAt, earned.count >= 10 {
                        Text(String(earned.prefix(10)))
                            .font(Theme.body(11)).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
