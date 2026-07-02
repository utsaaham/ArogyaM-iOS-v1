import SwiftUI
import Combine

@MainActor
final class WaterStore: ObservableObject {
    @Published var todayIntake: Double = 0
    @Published var goal: Double = 2500
    @Published var quickAmounts: [Int] = [100, 250, 500, 750]
    @Published var history: [WaterHistoryPoint] = []
    @Published var recent: [WaterEntry] = []
    @Published var isAdding = false
    @Published var loadedOnce = false

    private let api = API.shared

    var fraction: Double { goal > 0 ? min(todayIntake / goal, 1) : 0 }
    var glassesDone: Int { Int((todayIntake / 250).rounded(.down)) }
    var glassesGoal: Int { max(1, Int((goal / 250).rounded())) }

    func load() async {
        let date = DateUtil.todayKey
        async let log: DailyLog? = try? await api.getEnveloped("/api/daily-log", query: ["date": date])
        async let user: AppUser? = try? await api.getEnveloped("/api/user")
        async let hist: WaterHistory? = try? await api.getEnveloped("/api/water", query: ["days": "14"])

        if let l = await log {
            todayIntake = l.waterIntake ?? 0
            recent = (l.waterEntries ?? []).reversed()
        }
        if let u = await user {
            goal = u.targets?.dailyWater ?? 2500
            if let q = u.settings?.customizations?.water?.quickAmountsMl, q.count == 4 {
                quickAmounts = q
            }
        }
        history = (await hist)?.history ?? []
        loadedOnce = true
    }

    func add(_ amount: Int) async {
        isAdding = true
        defer { isAdding = false }
        struct Payload: Encodable { let date: String; let amount: Int }
        let payload = Payload(date: DateUtil.todayKey, amount: amount)
        if let body = try? JSONEncoder().encode(payload),
           let result: WaterLogResult = try? await api.postEnvelopedJSON("/api/water", json: body) {
            todayIntake = result.waterIntake ?? (todayIntake + Double(amount))
        } else {
            todayIntake += Double(amount)
        }
        await load()
    }
}

struct WaterView: View {
    @StateObject private var store = WaterStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Water", subtitle: "Stay hydrated").padding(.top, 6)
                heroCard
                quickAdd
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    private var heroCard: some View {
        let remaining = max(0, store.goal - store.todayIntake)
        return VStack(spacing: 18) {
            WaterBottle(fraction: store.fraction, height: 190)

            VStack(spacing: 3) {
                Text("\(Int(store.todayIntake)) ml")
                    .font(Theme.number(36, .bold)).foregroundStyle(Theme.text)
                Text("of \(Int(store.goal)) ml goal")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 10) {
                statPill(icon: "flag.checkered", value: "\(Int(remaining))", unit: "ml left")
                statPill(icon: "drop.fill", value: "\(store.glassesDone)/\(store.glassesGoal)", unit: "glasses")
            }

            glassesRow
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassCard(padding: 22)
    }

    private func statPill(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(Theme.number(16, .bold)).foregroundStyle(Theme.text)
                Text(unit).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private var glassesRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<store.glassesGoal, id: \.self) { i in
                Image(systemName: i < store.glassesDone ? "drop.fill" : "drop")
                    .font(.system(size: 14))
                    .foregroundStyle(i < store.glassesDone ? Theme.cyan : Theme.track)
            }
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ADD").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            HStack(spacing: 10) {
                ForEach(store.quickAmounts, id: \.self) { amount in
                    Button { Task { await store.add(amount) } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            Text("\(amount)").font(Theme.number(16, .bold))
                            Text("ml").font(Theme.body(10))
                        }
                        .foregroundStyle(Theme.cyan)
                        .frame(maxWidth: .infinity).frame(height: 72)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.cyan.opacity(0.12)))
                    }
                    .buttonStyle(SpringyButtonStyle(scale: 0.94))
                    .disabled(store.isAdding)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

}

/// A proper water-bottle silhouette that fills from the bottom up according to
/// the day's hydration progress, with the percentage shown in the centre.
struct WaterBottle: View {
    var fraction: Double
    var height: CGFloat = 190

    private var clamped: Double { max(0, min(fraction, 1)) }

    var body: some View {
        ZStack {
            // Empty bottle outline
            Image(systemName: "waterbottle.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Theme.cyan.opacity(0.16))
            // Water that rises with progress
            Image(systemName: "waterbottle.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Theme.cyan)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: height * clamped)
                }
        }
        .frame(width: height * 0.62, height: height)
        .animation(.easeOut(duration: 0.5), value: clamped)
    }
}
