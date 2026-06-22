import SwiftUI
import Charts
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
                if !store.history.isEmpty { historyChart }
                if !store.recent.isEmpty { recentList }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            WaterRing(fraction: store.fraction, size: 178)
            VStack(spacing: 3) {
                Text("\(Int(store.todayIntake)) ml")
                    .font(Theme.number(36, .bold)).foregroundStyle(Theme.text)
                Text("of \(Int(store.goal)) ml goal")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }
            glassesRow
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassCard(padding: 22)
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

    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAST 14 DAYS").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            Chart(store.history, id: \.date) { point in
                BarMark(
                    x: .value("Day", point.date ?? ""),
                    y: .value("ml", point.waterIntake ?? 0)
                )
                .foregroundStyle(Theme.cyan.gradient)
                .cornerRadius(4)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().foregroundStyle(Theme.textMuted)
                }
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY'S LOG").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            ForEach(Array(store.recent.prefix(8).enumerated()), id: \.offset) { _, entry in
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(Theme.cyan).font(.system(size: 13))
                    Text("\(Int(entry.amount ?? 0)) ml").font(Theme.body(14, .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(entry.time ?? "").font(Theme.body(13)).foregroundStyle(Theme.textMuted)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Circular water ring (watchOS Water style): an animated wave fills a circle,
/// with the percentage shown in the centre and a soft ring around it.
struct WaterRing: View {
    var fraction: Double
    var size: CGFloat = 178
    @State private var phase = 0.0

    private var clamped: Double { max(0, min(fraction, 1)) }

    var body: some View {
        ZStack {
            Circle().fill(Theme.cyan.opacity(0.10))
            WaterWave(phase: phase, fillFraction: clamped)
                .fill(LinearGradient(colors: [Theme.cyan.opacity(0.7), Theme.cyan],
                                     startPoint: .top, endPoint: .bottom))
                .clipShape(Circle())
            Circle().strokeBorder(Theme.cyan.opacity(0.22), lineWidth: 2)
            Text("\(Int(clamped * 100))%")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(clamped > 0.45 ? .white : Theme.cyan)
                .shadow(color: .black.opacity(clamped > 0.45 ? 0.12 : 0), radius: 3, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.cyan.opacity(0.25), radius: 16, y: 8)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}

private struct WaterWave: Shape {
    var phase: Double
    var fillFraction: Double
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveHeight = rect.height * 0.02
        let baseY = rect.height * (1 - fillFraction)
        path.move(to: CGPoint(x: 0, y: baseY))
        for x in stride(from: 0.0, through: rect.width, by: 2) {
            let relativeX = x / rect.width
            let y = baseY + waveHeight * sin(phase + relativeX * .pi * 2.5)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
