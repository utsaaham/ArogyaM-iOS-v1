import SwiftUI
import Combine

@MainActor
final class HomeStore: ObservableObject {
    @Published var user: AppUser?
    @Published var log: DailyLog?
    @Published var achievements: Achievements?
    @Published var health: HealthToday?
    @Published var vitals: VitalsResponse?
    @Published var level = 1
    @Published var xpInto = 0
    @Published var xpForLevel = 100
    @Published var isLoading = false
    @Published var loadedOnce = false

    private let api = API.shared

    func load() async {
        isLoading = true
        let date = DateUtil.todayKey
        async let u: AppUser? = try? await api.getEnveloped("/api/user")
        async let l: DailyLog? = try? await api.getEnveloped("/api/daily-log", query: ["date": date])
        async let a: AchievementsResponse? = try? await api.getEnveloped("/api/achievements")
        async let h: HealthMetricsResponse? = try? await api.getEnveloped("/api/health-metrics")
        async let v: VitalsResponse? = try? await api.getEnveloped("/api/scores")

        user = await u
        vitals = await v
        log = await l
        let ach = await a
        achievements = ach?.achievements
        level = ach?.level ?? ((ach?.achievements?.xpTotal ?? 0) / 100 + 1)
        xpInto = ach?.xpIntoLevel ?? ((ach?.achievements?.xpTotal ?? 0) % 100)
        xpForLevel = ach?.xpForCurrentLevel ?? 100
        health = (await h)?.today
        isLoading = false
        loadedOnce = true
    }
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var store = HomeStore()

    private var targets: UserTargets? { store.user?.targets ?? auth.currentUser?.targets }
    private var name: String {
        (store.user?.profile?.name ?? auth.currentUser?.profile?.name ?? "there")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                if store.isLoading && !store.loadedOnce {
                    ProgressView().tint(Theme.teal).padding(.top, 80)
                } else {
                    if store.vitals?.readiness?.score != nil { vitalsGlanceCard }
                    streakCard
                    calorieCard
                    statsGrid
                    waterHeroCard
                    wearablesGrid
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    // MARK: - Vitals glance

    private var vitalsGlanceCard: some View {
        let score = store.vitals?.readiness?.score
        let band = store.vitals?.guidance?.band
        let tint = Theme.scoreColor(score)
        return HStack(spacing: 16) {
            ProgressRing(progress: (score ?? 0) / 100, tint: tint, size: 74, lineWidth: 9) {
                Text(score.map { "\(Int($0.rounded()))" } ?? "···")
                    .font(Theme.number(22, .heavy)).foregroundStyle(Theme.text)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Readiness").font(Theme.display(17, .bold)).foregroundStyle(Theme.text)
                    if let band {
                        Text(band.capitalized)
                            .font(Theme.body(11, .bold))
                            .foregroundStyle(Theme.guidanceColor(band))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.guidanceColor(band).opacity(0.15)))
                    }
                }
                Text(store.vitals?.guidance?.reason ?? "Fresh scores, made just for you.")
                    .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .glassCard(tint: tint, padding: 16)
    }

    // MARK: - Header

    private var headerCard: some View {
        let level = store.level
        let inLevel = store.xpForLevel > 0 ? Double(store.xpInto) / Double(store.xpForLevel) : 0
        return VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(Theme.body(15, .medium)).foregroundStyle(Theme.textSecondary)
                    Text("\(name) 👋").font(Theme.display(28, .bold)).foregroundStyle(Theme.text)
                    HStack(spacing: 5) {
                        Circle().fill(Theme.teal).frame(width: 6, height: 6)
                        Text("AROGYAMANDIRAM")
                            .font(Theme.body(10, .bold)).tracking(1.4)
                            .foregroundStyle(Theme.teal)
                    }
                    .padding(.top, 4)
                }
                Spacer()
                avatar
            }
            Divider().overlay(Theme.hairline)
            VStack(spacing: 6) {
                HStack {
                    Text("Level \(level)").font(Theme.body(12, .medium)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(store.xpInto) / \(store.xpForLevel) XP").font(Theme.body(12, .bold)).foregroundStyle(Theme.teal)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.teal, Theme.blue],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * inLevel))
                    }
                }
                .frame(height: 6)
            }
        }
        .glassCard(padding: 18)
    }

    private var avatar: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.display(22, .bold)).foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(
                LinearGradient(colors: [Theme.teal, Theme.blue],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    // MARK: - Streaks

    private var streakCard: some View {
        let c = store.achievements?.streaks?.current
        let b = store.achievements?.streaks?.best
        // All streak types, paired with their best. Only show ones that are
        // actually active (current >= 1).
        let items: [(String, Int, Int)] = [
            ("Active", c?.logging ?? 0, b?.logging ?? 0),
            ("Healthy", c?.healthy ?? 0, b?.healthy ?? 0),
            ("Food", c?.calories ?? 0, b?.calories ?? 0),
            ("Water", c?.water ?? 0, b?.water ?? 0),
            ("Workouts", c?.workout ?? 0, b?.workout ?? 0),
            ("Sleep", c?.sleep ?? 0, b?.sleep ?? 0),
            ("Weight", c?.weight ?? 0, b?.weight ?? 0),
            ("Steps", c?.steps ?? 0, b?.steps ?? 0),
        ].filter { $0.1 >= 1 }
        return VStack(alignment: .leading, spacing: 12) {
            caption("ACTIVE STREAKS")
            if items.isEmpty {
                Text("No streaks yet. Log one little thing today and we'll start a fire 🔥")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                            streakChip(label: it.0, current: it.1, best: it.2)
                        }
                    }
                }
            }
            dayDots
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func streakChip(label: String, current: Int, best: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.orange.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: "flame.fill").font(.system(size: 14)).foregroundStyle(Theme.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 4) {
                    Text("\(current)d").font(Theme.number(15, .bold)).foregroundStyle(Theme.text)
                    Text("Best \(best)d").font(Theme.body(10)).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }

    private var dayDots: some View {
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        let todayIdx = (Calendar.current.component(.weekday, from: Date()) + 5) % 7  // Mon=0
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Text(labels[i])
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(i == todayIdx ? Theme.green : Theme.textMuted)
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(i == todayIdx ? Theme.green.opacity(0.15) : Theme.surface)
                    )
            }
        }
    }

    // MARK: - Calories + macros

    private var calorieCard: some View {
        let consumed = store.log?.totalCalories ?? 0
        let goal = targets?.dailyCalories ?? 2000
        let remaining = max(0, goal - consumed)
        let pct = goal > 0 ? consumed / goal : 0
        return VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    caption("TODAY'S CALORIES")
                    Text(Int(consumed).formatted())
                        .font(Theme.number(44, .bold)).foregroundStyle(Theme.text)
                    Text("kcal consumed").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        Text("\(Int(remaining).formatted())").font(Theme.number(15, .bold)).foregroundStyle(Theme.text)
                        Text("kcal left").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 6)
                    Text("of \(Int(goal).formatted()) kcal goal").font(Theme.body(11)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                ProgressRing(progress: pct, tint: Theme.orange, size: 104, lineWidth: 11) {
                    Text("\(Int(pct * 100))%").font(Theme.number(17, .bold)).foregroundStyle(Theme.text)
                }
            }
            VStack(spacing: 10) {
                macro("Protein", store.log?.totalProtein, targets?.protein ?? 150, "g", Theme.purple)
                macro("Carbs", store.log?.totalCarbs, targets?.carbs ?? 255, "g", Theme.orange)
                macro("Fat", store.log?.totalFat, targets?.fat ?? 85, "g", Theme.pink)
                macro("Sugar", store.log?.totalSugar, 50, "g", Theme.gold)
                macro("Sodium", store.log?.totalSodium, 2300, "mg", Theme.blue)
            }
        }
        .glassCard(padding: 18)
    }

    private func macro(_ label: String, _ value: Double?, _ goal: Double, _ unit: String, _ tint: Color) -> some View {
        MacroBar(label: label, value: value ?? 0, goal: goal, tint: tint, unit: unit)
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let waterGoal = targets?.dailyWater ?? 2500
        let water = store.log?.waterIntake ?? 0
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard("drop.fill", Theme.cyan, "\(String(format: "%.1f", water / 1000)) L", "Water",
                     "of \(String(format: "%.1f", waterGoal / 1000)) L target")
            statCard("flame.fill", Theme.pink, "\(Int(store.log?.caloriesBurned ?? 0))", "Burned",
                     "\(store.log?.workouts?.count ?? 0) workouts")
            statCard("fork.knife", Theme.orange, "\(store.log?.meals?.count ?? 0)", "Meals",
                     "\(Int(store.log?.totalCalories ?? 0).formatted()) kcal logged")
            statCard("moon.fill", Theme.indigo,
                     store.log?.sleep?.duration.map { String(format: "%.1f h", $0) } ?? "···", "Sleep",
                     "of \(Int(targets?.sleepHours ?? 8))h target")
        }
    }

    private func statCard(_ icon: String, _ tint: Color, _ value: String, _ label: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                .padding(.bottom, 2)
            Text(value).font(Theme.number(22, .bold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Theme.body(13, .semibold)).foregroundStyle(Theme.text)
            Text(sub).font(Theme.body(11)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 15)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
    }

    // MARK: - Water hero

    private var waterHeroCard: some View {
        let goal = targets?.dailyWater ?? 2500
        let intake = store.log?.waterIntake ?? 0
        let remaining = max(0, goal - intake)
        let pct = goal > 0 ? min(intake / goal, 1) : 0
        return VStack(spacing: 14) {
            caption("HYDRATION")
            ZStack(alignment: .bottom) {
                Image(systemName: "waterbottle.fill")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(Theme.cyan.opacity(0.16))
                Image(systemName: "waterbottle.fill")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(Theme.cyan)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: 96 * pct)
                    }
            }
            .frame(height: 110)
            VStack(spacing: 2) {
                Text("\(String(format: "%.1f", remaining / 1000)) L remaining")
                    .font(Theme.display(18, .bold)).foregroundStyle(Theme.text)
                Text("of \(String(format: "%.1f", goal / 1000)) L goal")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
    }

    // MARK: - Wearables grid

    private var wearablesGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let steps = store.health?.steps ?? store.log?.steps
        let hr = store.health?.heartRate ?? store.log?.heartRate
        let active = store.health?.activeCalories ?? store.log?.activeCalories
        let dist = store.health?.distanceKm ?? store.log?.distanceKm
        return LazyVGrid(columns: columns, spacing: 12) {
            wearableCard("figure.walk", Theme.green, "Steps", steps.map { Int($0).formatted() })
            wearableCard("heart.fill", Theme.red, "Heart Rate", hr.map { "\(Int($0)) bpm" })
            wearableCard("bolt.heart.fill", Theme.orange, "Active Cal", active.map { "\(Int($0)) kcal" })
            wearableCard("location.fill", Theme.cyan, "Distance", dist.map { String(format: "%.2f km", $0) })
        }
    }

    private func wearableCard(_ icon: String, _ tint: Color, _ label: String, _ value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(value == nil ? Theme.textMuted : tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.body(13, .semibold)).foregroundStyle(Theme.text)
                Text(value ?? "No data").font(value == nil ? Theme.body(12) : Theme.number(15, .bold))
                    .foregroundStyle(value == nil ? Theme.textMuted : tint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 15)
    }

}
