import SwiftUI
import Charts
import Combine

// MARK: - Models (/api/sleep)

struct SleepHistoryResponse: Decodable, Sendable {
    let history: [SleepHistoryPoint]?
}

struct SleepHistoryPoint: Decodable, Sendable {
    let date: String?
    let sleep: SleepEntry?
}

// MARK: - Store

@MainActor
final class SleepStore: ObservableObject {
    @Published var todaySleep: SleepEntry?
    @Published var goalHours: Double = 8
    @Published var history: [SleepHistoryPoint] = []
    @Published var isSaving = false
    @Published var loadedOnce = false

    private let api = API.shared

    var lastNightHours: Double { todaySleep?.duration ?? 0 }
    var fraction: Double { goalHours > 0 ? min(lastNightHours / goalHours, 1) : 0 }

    func load() async {
        async let log: DailyLog? = try? await api.getEnveloped("/api/daily-log", query: ["date": DateUtil.todayKey])
        async let user: AppUser? = try? await api.getEnveloped("/api/user")
        async let hist: SleepHistoryResponse? = try? await api.getEnveloped("/api/sleep", query: ["days": "14"])

        todaySleep = (await log)?.sleep
        if let target = (await user)?.targets?.sleepHours, target > 0 { goalHours = target }
        history = ((await hist)?.history ?? []).reversed()
        loadedOnce = true
    }

    func save(bedtime: Date, wakeTime: Date, quality: Int) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm"

        let cal = Calendar.current
        let bed = cal.dateComponents([.hour, .minute], from: bedtime)
        let wake = cal.dateComponents([.hour, .minute], from: wakeTime)
        var minutes = (wake.hour! * 60 + wake.minute!) - (bed.hour! * 60 + bed.minute!)
        if minutes <= 0 { minutes += 24 * 60 } // slept past midnight
        let duration = (Double(minutes) / 60 * 10).rounded() / 10

        struct Payload: Encodable {
            let date: String
            let bedtime: String
            let wakeTime: String
            let duration: Double
            let quality: Int
        }
        let payload = Payload(
            date: DateUtil.todayKey,
            bedtime: fmt.string(from: bedtime),
            wakeTime: fmt.string(from: wakeTime),
            duration: duration,
            quality: quality
        )
        guard let body = try? JSONEncoder().encode(payload) else { return false }
        do {
            try await api.postExpectingSuccess("/api/sleep", json: body)
            await load()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - View

struct SleepView: View {
    @StateObject private var store = SleepStore()
    @State private var bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quality = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Sleep", subtitle: "Rest well, recover better").padding(.top, 6)
                heroCard
                logCard
                if !store.history.isEmpty { historyCard }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .task { if !store.loadedOnce { await store.load() } }
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            ProgressRing(progress: store.fraction, tint: Theme.indigo, size: 150, lineWidth: 14) {
                VStack(spacing: 2) {
                    Text(hoursLabel(store.lastNightHours))
                        .font(Theme.number(28, .bold)).foregroundStyle(Theme.text)
                    Text("of \(hoursLabel(store.goalHours))")
                        .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
            }

            if let sleep = store.todaySleep {
                HStack(spacing: 10) {
                    detailPill(icon: "moon.fill", value: sleep.bedtime ?? "—", unit: "bedtime")
                    detailPill(icon: "sun.max.fill", value: sleep.wakeTime ?? "—", unit: "wake up")
                    detailPill(icon: "star.fill", value: "\(sleep.quality ?? 0)/5", unit: "quality")
                }
            } else {
                Text("No sleep logged for last night yet")
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassCard(padding: 22)
    }

    private func detailPill(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.indigo)
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
            Text("LOG LAST NIGHT").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bedtime").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wake up").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How did you sleep?").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Button { quality = star } label: {
                            Image(systemName: star <= quality ? "star.fill" : "star")
                                .font(.system(size: 22))
                                .foregroundStyle(star <= quality ? Theme.gold : Theme.track)
                        }
                        .buttonStyle(SpringyButtonStyle())
                    }
                }
            }

            PrimaryButton(title: "Save Sleep", tint: Theme.indigo, isLoading: store.isSaving, systemImage: "moon.zzz.fill") {
                Task { _ = await store.save(bedtime: bedtime, wakeTime: wakeTime, quality: quality) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAST 14 DAYS").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            Chart {
                ForEach(Array(store.history.enumerated()), id: \.offset) { _, point in
                    if let date = point.date, let hours = point.sleep?.duration {
                        BarMark(
                            x: .value("Day", String(date.suffix(5))),
                            y: .value("Hours", hours)
                        )
                        .foregroundStyle(Theme.indigo.gradient)
                        .cornerRadius(4)
                    }
                }
                RuleMark(y: .value("Goal", store.goalHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(Theme.body(9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func hoursLabel(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int(((hours - Double(h)) * 60).rounded())
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
