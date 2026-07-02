import SwiftUI
import Charts
import Combine

// MARK: - Store

@MainActor
final class VitalsStore: ObservableObject {
    @Published var vitals: VitalsResponse?
    @Published var isLoading = false
    @Published var loadedOnce = false

    private let api = API.shared

    func load() async {
        isLoading = true
        vitals = try? await api.getEnveloped("/api/scores")
        isLoading = false
        loadedOnce = true
    }
}

// MARK: - View

struct VitalsView: View {
    @StateObject private var store = VitalsStore()
    @State private var trendMetric: TrendMetric = .readiness
    @State private var trendRange: TrendRange = .week

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Vitals", subtitle: "Your daily scores").padding(.top, 6)

                if store.isLoading && !store.loadedOnce {
                    ProgressView().tint(Theme.teal).padding(.top, 100)
                } else if let v = store.vitals {
                    readinessHero(v)
                    guidanceBanner(v.guidance)
                    scoreGrid(v)
                    if let zones = v.strain?.zones, zones.contains(where: { ($0.minutes ?? 0) > 0 }) {
                        zonesCard(zones)
                    }
                    trendsCard(v)
                    if let insights = v.insights, !insights.isEmpty {
                        insightsCard(insights)
                    }
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    // MARK: - Readiness hero

    private func readinessHero(_ v: VitalsResponse) -> some View {
        let score = v.readiness?.score
        let tint = Theme.scoreColor(score)
        return VStack(spacing: 16) {
            ProgressRing(progress: (score ?? 0) / 100, tint: tint, size: 196, lineWidth: 17) {
                VStack(spacing: 2) {
                    Text(score.map { "\(Int($0.rounded()))" } ?? "···")
                        .font(Theme.number(62, .heavy))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("READINESS")
                        .font(Theme.body(11, .bold)).tracking(1.6)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 8)

            if let drivers = v.readiness?.drivers, !drivers.isEmpty {
                VStack(spacing: 4) {
                    ForEach(drivers, id: \.self) { d in
                        Text(d)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            if let comps = v.readiness?.components?.filter({ $0.score != nil }), !comps.isEmpty {
                componentBars(comps, tint: tint)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
    }

    private func componentBars(_ comps: [VitalsScoreComponent], tint: Color) -> some View {
        VStack(spacing: 9) {
            ForEach(comps) { c in
                HStack(spacing: 10) {
                    Text(c.label ?? c.key ?? "")
                        .font(Theme.body(12, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.scoreColor(c.score))
                                .frame(width: max(5, geo.size.width * ((c.score ?? 0) / 100)))
                        }
                    }
                    .frame(height: 7)
                    Text("\(Int((c.score ?? 0).rounded()))")
                        .font(Theme.number(12, .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Guidance

    private func guidanceBanner(_ g: VitalsGuidance?) -> some View {
        let band = g?.band
        let tint = Theme.guidanceColor(band)
        let (icon, title): (String, String) = {
            switch band {
            case "push": return ("figure.run", "Push today")
            case "maintain": return ("scalemass.fill", "Maintain")
            case "recover": return ("leaf.fill", "Take it easier")
            case "rest": return ("bed.double.fill", "Rest up")
            default: return ("sparkles", "Today")
            }
        }()
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.display(17, .bold)).foregroundStyle(Theme.text)
                Text(g?.reason ?? "Sync your Apple Health data to unlock daily guidance.")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, padding: 16)
    }

    // MARK: - Strain / Sleep / Stress grid

    private func scoreGrid(_ v: VitalsResponse) -> some View {
        HStack(spacing: 12) {
            smallScoreCard(
                title: "Strain", icon: "flame.fill", tint: Theme.blue,
                value: v.strain?.score.map { "\(Int($0.rounded()))" } ?? "···",
                caption: "load today"
            )
            smallScoreCard(
                title: "Sleep", icon: "moon.zzz.fill", tint: Theme.indigo,
                value: v.sleep?.score.map { "\(Int($0.rounded()))" } ?? "···",
                caption: "last night"
            )
            smallScoreCard(
                title: "Stress", icon: "waveform.path", tint: Theme.stressColor(v.stress?.level),
                value: (v.stress?.level ?? "···").capitalized,
                caption: "estimate",
                valueIsText: true
            )
        }
    }

    private func smallScoreCard(
        title: String, icon: String, tint: Color,
        value: String, caption: String, valueIsText: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                Text(title).font(Theme.body(12, .semibold)).foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(valueIsText ? Theme.display(21, .bold) : Theme.number(30, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(Theme.body(11)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    // MARK: - HR zones

    private func zonesCard(_ zones: [HRZoneMinutes]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("HEART RATE ZONES")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(zones.filter { ($0.minutes ?? 0) > 0 }) { z in
                        GlassChip(
                            text: "\(z.zone ?? "Z?") · \(Int((z.minutes ?? 0).rounded())) min",
                            tint: Theme.blue
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    // MARK: - Trends

    enum TrendMetric: String, CaseIterable, Identifiable {
        case readiness = "Readiness"
        case strain = "Strain"
        case sleep = "Sleep"
        case stress = "Stress"
        case hrv = "HRV"
        case rhr = "Resting HR"

        var id: String { rawValue }

        var tint: Color {
            switch self {
            case .readiness: return Theme.green
            case .strain: return Theme.blue
            case .sleep: return Theme.indigo
            case .stress: return Theme.amber
            case .hrv: return Theme.teal
            case .rhr: return Theme.rose
            }
        }

        var isPercentScale: Bool {
            switch self {
            case .hrv, .rhr: return false
            default: return true
            }
        }

        func value(from p: VitalsTrendPoint) -> Double? {
            switch self {
            case .readiness: return p.readiness
            case .strain: return p.strain
            case .sleep: return p.sleep
            case .stress: return p.stress
            case .hrv: return p.hrvSdnnMs
            case .rhr: return p.restingHeartRate
            }
        }
    }

    enum TrendRange: String, CaseIterable {
        case week = "7D"
        case month = "1M"

        var days: Int { self == .week ? 7 : 30 }
    }

    private struct TrendChartPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private func trendPoints(_ v: VitalsResponse) -> [TrendChartPoint] {
        (v.trends ?? [])
            .suffix(trendRange.days)
            .compactMap { p in
                guard let key = p.date, let d = DateUtil.date(fromKey: key),
                      let value = trendMetric.value(from: p) else { return nil }
                return TrendChartPoint(date: d, value: value)
            }
    }

    private func trendsCard(_ v: VitalsResponse) -> some View {
        let points = trendPoints(v)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                caption("TRENDS")
                Spacer()
                Picker("Range", selection: $trendRange) {
                    ForEach(TrendRange.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TrendMetric.allCases) { m in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                trendMetric = m
                            }
                        } label: {
                            Text(m.rawValue)
                                .font(Theme.body(13, .semibold))
                                .foregroundStyle(trendMetric == m ? .white : Theme.textSecondary)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(
                                    Capsule().fill(trendMetric == m ? m.tint : Theme.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if points.count >= 2 {
                if trendMetric.isPercentScale {
                    trendChart(points).chartYScale(domain: 0...100)
                } else {
                    trendChart(points)
                }
            } else {
                Text("A few more days of data and your \(trendMetric.rawValue.lowercased()) trend will bloom here.")
                    .font(Theme.body(13)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func trendChart(_ points: [TrendChartPoint]) -> some View {
        Chart(points) { p in
                    AreaMark(
                        x: .value("Day", p.date),
                        y: .value(trendMetric.rawValue, p.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [trendMetric.tint.opacity(0.28), trendMetric.tint.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Day", p.date),
                        y: .value(trendMetric.rawValue, p.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(trendMetric.tint)

                    if p.date == points.last?.date {
                        PointMark(
                            x: .value("Day", p.date),
                            y: .value(trendMetric.rawValue, p.value)
                        )
                        .symbolSize(70)
                        .foregroundStyle(trendMetric.tint)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: trendRange == .week ? 7 : 5)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(Theme.body(10))
                        AxisGridLine().foregroundStyle(Theme.hairline)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(Theme.body(10))
                        AxisGridLine().foregroundStyle(Theme.hairline)
                    }
                }
                .frame(height: 180)
                .animation(.easeInOut(duration: 0.3), value: trendMetric)
    }

    // MARK: - Insights

    private func insightsCard(_ insights: [HabitInsight]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("WHAT MOVES YOUR SCORES")
            ForEach(insights) { i in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: (i.delta ?? 0) >= 0 ? "arrow.up.heart.fill" : "arrow.down.heart.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle((i.delta ?? 0) >= 0 ? Theme.green : Theme.rose)
                        .frame(width: 22)
                    Text(i.text ?? "")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    // MARK: - Empty / footer

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.teal)
            Text("No scores yet")
                .font(Theme.display(18, .bold)).foregroundStyle(Theme.text)
            Text("Your scores are waiting on data. Open Health Sync in the More tab, let it do its thing, and Readiness, Strain, Sleep and Stress will light up here the very same day ✨")
                .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard(padding: 20)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
    }
}
