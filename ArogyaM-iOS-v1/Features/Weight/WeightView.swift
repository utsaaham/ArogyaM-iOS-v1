import SwiftUI
import Charts
import Combine

// MARK: - Models (/api/weight)

struct WeightHistoryResponse: Decodable, Sendable {
    let history: [WeightHistoryPoint]?
    let count: Int?
}

struct WeightHistoryPoint: Decodable, Sendable {
    let date: String?
    let weight: Double?
}

// MARK: - Store

@MainActor
final class WeightStore: ObservableObject {
    @Published var history: [WeightHistoryPoint] = []
    @Published var currentWeight: Double?
    @Published var targetWeight: Double?
    @Published var isSaving = false
    @Published var loadedOnce = false

    private let api = API.shared

    var trend: Double? {
        let weights = history.compactMap { $0.weight }
        guard let first = weights.first, let last = weights.last, weights.count >= 2 else { return nil }
        return last - first
    }

    func load() async {
        async let hist: WeightHistoryResponse? = try? await api.getEnveloped("/api/weight", query: ["days": "90"])
        async let user: AppUser? = try? await api.getEnveloped("/api/user")

        history = (await hist)?.history ?? []
        let u = await user
        currentWeight = history.last?.weight ?? u?.profile?.weight
        targetWeight = u?.profile?.targetWeight ?? u?.targets?.idealWeight
        loadedOnce = true
    }

    func log(_ weight: Double) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        struct Payload: Encodable { let date: String; let weight: Double }
        let payload = Payload(date: DateUtil.todayKey, weight: weight)
        guard let body = try? JSONEncoder().encode(payload) else { return false }
        do {
            try await api.postExpectingSuccess("/api/weight", json: body)
            await load()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - View

struct WeightView: View {
    @StateObject private var store = WeightStore()
    @State private var weightText = ""
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Weight", subtitle: "Small changes, big progress").padding(.top, 6)
                heroCard
                logCard
                if store.history.count >= 2 { chartCard }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text(store.currentWeight.map { String(format: "%.1f kg", $0) } ?? "— kg")
                    .font(Theme.number(40, .bold)).foregroundStyle(Theme.text)
                Text("current weight").font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 10) {
                if let target = store.targetWeight {
                    statPill(icon: "target", value: String(format: "%.1f kg", target), unit: "goal")
                    if let current = store.currentWeight {
                        let diff = current - target
                        statPill(
                            icon: diff > 0 ? "arrow.down.right" : "checkmark",
                            value: String(format: "%.1f kg", abs(diff)),
                            unit: diff > 0 ? "to lose" : "at/below goal"
                        )
                    }
                }
                if let trend = store.trend {
                    statPill(
                        icon: trend <= 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis",
                        value: String(format: "%+.1f kg", trend),
                        unit: "last 90 days"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassCard(padding: 22)
    }

    private func statPill(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(Theme.number(15, .bold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LOG TODAY'S WEIGHT").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            HStack(spacing: 10) {
                TextField("e.g. 72.5", text: $weightText)
                    .font(Theme.body(16))
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                Text("kg").font(Theme.body(15, .semibold)).foregroundStyle(Theme.textSecondary)
            }
            if saveFailed {
                Text("That didn't save. Enter a weight above zero and try again.")
                    .font(Theme.body(12)).foregroundStyle(Theme.rose)
            }
            PrimaryButton(title: "Save Weight", tint: Theme.blue, isLoading: store.isSaving, systemImage: "scalemass.fill") {
                Task {
                    saveFailed = false
                    guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 else {
                        saveFailed = true
                        return
                    }
                    if await store.log(value) {
                        weightText = ""
                    } else {
                        saveFailed = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAST 90 DAYS").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            Chart {
                ForEach(Array(store.history.enumerated()), id: \.offset) { _, point in
                    if let date = point.date, let kg = point.weight, let day = DateUtil.date(fromKey: date) {
                        LineMark(x: .value("Date", day), y: .value("Weight", kg))
                            .foregroundStyle(Theme.blue)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", day), y: .value("Weight", kg))
                            .foregroundStyle(Theme.blue)
                            .symbolSize(20)
                    }
                }
                if let target = store.targetWeight {
                    RuleMark(y: .value("Goal", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.green)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
