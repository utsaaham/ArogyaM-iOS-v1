import SwiftUI
import Combine

@MainActor
final class HealthSyncStore: ObservableObject {
    @Published var payload: WeeklyHealthPayload?
    @Published var sources: [String] = []
    @Published var authorized = false
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var status: String?
    @Published var statusIsError = false

    private let api = API.shared

    var today: HealthSnapshot? { payload?.days.first { $0.today == true } }

    func start() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
            authorized = true
            await refresh()
        } catch {
            authorized = false
            setStatus("Health permission unavailable: \(error.localizedDescription)", error: true)
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let p = HealthKitService.shared.fetchWeeklyPayload()
        async let s = HealthKitService.shared.fetchConnectedSources()
        payload = await p
        sources = await s
        AutoSyncService.shared.noteRefreshed()
    }

    func sync() async {
        isSyncing = true
        defer { isSyncing = false }

        let result = await AutoSyncService.shared.syncNow()
        if result.sleep == 0 && result.workouts == 0 {
            setStatus("✅ All synced. No sleep or workouts to send today, but your snapshot made it home safe.", error: false)
        } else {
            setStatus("✅ Synced! \(result.sleep) sleep and \(result.workouts) workout\(result.workouts == 1 ? "" : "s") made the trip to ArogyaM.", error: false)
        }
    }

    private func setStatus(_ text: String, error: Bool) {
        status = text
        statusIsError = error
    }
}

struct HealthSyncView: View {
    @StateObject private var store = HealthSyncStore()
    @ObservedObject private var autoSync = AutoSyncService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Health Sync", subtitle: "Your body, in sync")
                    .padding(.top, 6)

                if !store.authorized && !store.isLoading {
                    permissionCard
                } else {
                    activityCard
                    sleepCard
                    if !(store.today?.workouts.isEmpty ?? true) { workoutsCard }
                    if !store.sources.isEmpty { sourcesCard }
                }

                if store.authorized { refreshButton }
                syncButton
                autoSyncStatus
                if let status = store.status { statusBanner(status) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .task { if store.payload == nil { await store.start() } }
    }

    // MARK: - Permission

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Label("Apple Health access needed", systemImage: "heart.slash.fill")
                .font(Theme.body(14, .semibold)).foregroundStyle(Theme.textSecondary)
            Button("Allow Health Access") { Task { await store.start() } }
                .font(Theme.body(14, .semibold)).foregroundStyle(Theme.emerald)
        }
        .frame(maxWidth: .infinity)
        .glassCard(tint: Theme.rose)
    }

    // MARK: - Activity card (steps · calories · distance · heart)

    private var activityCard: some View {
        let t = store.today
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader("Activity", icon: "figure.walk", tint: Theme.emerald, refreshing: store.isLoading)

            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 10) {
                metricCell("figure.walk", Theme.emerald, "Steps",
                           t.map { formatted($0.activity.steps) } ?? "···")
                metricCell("flame.fill", Theme.orange, "Calories",
                           t.map { "\($0.activity.activeCalories) kcal" } ?? "···")
                metricCell("map.fill", Theme.cyan, "Distance",
                           t.map { String(format: "%.2f km", $0.activity.distanceKm) } ?? "···")
                metricCell("heart.fill", Theme.pink, "Heart Rate",
                           t?.heart.avgBpm.map { "\($0) bpm" } ?? "···")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.emerald)
    }

    // MARK: - Sleep card

    private var sleepCard: some View {
        let sleep = store.today?.sleep
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader("Sleep", icon: "bed.double.fill", tint: Theme.violet, refreshing: store.isLoading)

            if let s = sleep, s.totalHours > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", s.totalHours))
                        .font(Theme.display(32, .bold)).foregroundStyle(Theme.text)
                    Text("hrs").font(Theme.body(14)).foregroundStyle(Theme.textMuted)
                    Spacer()
                    if let bed = s.bedtime, let wake = s.wake {
                        Text("\(shortTime(bed)) → \(shortTime(wake))")
                            .font(Theme.body(12)).foregroundStyle(Theme.textMuted)
                    }
                }

                // Stage bar
                let total = s.stages.coreHours + s.stages.deepHours + s.stages.remHours + s.stages.awakeHours
                if total > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            stageBar(fraction: s.stages.deepHours / total,
                                     color: Theme.violet, width: geo.size.width)
                            stageBar(fraction: s.stages.remHours / total,
                                     color: Theme.indigo, width: geo.size.width)
                            stageBar(fraction: s.stages.coreHours / total,
                                     color: Theme.cyan.opacity(0.8), width: geo.size.width)
                            stageBar(fraction: s.stages.awakeHours / total,
                                     color: Theme.textMuted.opacity(0.3), width: geo.size.width)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 8)

                    HStack(spacing: 12) {
                        stageLegend("Deep", s.stages.deepHours, Theme.violet)
                        stageLegend("REM", s.stages.remHours, Theme.indigo)
                        stageLegend("Core", s.stages.coreHours, Theme.cyan)
                        if s.stages.awakeHours > 0 {
                            stageLegend("Awake", s.stages.awakeHours, Theme.textMuted)
                        }
                    }
                }
            } else {
                Text("No sleep data yet. Go dream a little and check back tomorrow 🌙")
                    .font(Theme.body(13)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.violet)
    }

    // MARK: - Workouts card

    private var workoutsCard: some View {
        let workouts = store.today?.workouts ?? []
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader("Workouts", icon: "figure.run", tint: Theme.rose, refreshing: false)

            VStack(spacing: 8) {
                ForEach(workouts) { w in
                    HStack(spacing: 10) {
                        Image(systemName: workoutIcon(w.type))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.rose)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.type).font(Theme.body(13, .semibold)).foregroundStyle(Theme.text)
                            HStack(spacing: 6) {
                                Text("\(w.durationMin) min")
                                if w.calories > 0 { Text("·"); Text("\(w.calories) kcal") }
                                if w.distanceKm > 0 { Text("·"); Text(String(format: "%.2f km", w.distanceKm)) }
                                if let hr = w.avgHeartRate { Text("·"); Text("\(hr) bpm") }
                            }
                            .font(Theme.body(11)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.emerald)
                    }
                    .padding(.vertical, 4)
                    if w.id != workouts.last?.id {
                        Divider().background(Theme.textMuted.opacity(0.15))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.rose)
    }

    // MARK: - Sources card

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connected sources", systemImage: "sensor.fill")
                .font(Theme.body(14, .semibold)).foregroundStyle(Theme.textSecondary)
            ForEach(store.sources, id: \.self) { src in
                HStack(spacing: 8) {
                    Image(systemName: deviceIcon(src)).foregroundStyle(Theme.cyan).font(.system(size: 13))
                    Text(src).font(Theme.body(14)).foregroundStyle(Theme.text)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Refresh + sync buttons

    private var refreshButton: some View {
        Button { Task { await store.refresh() } } label: {
            HStack(spacing: 8) {
                if store.isLoading {
                    ProgressView().tint(Theme.emerald)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(store.isLoading ? "Refreshing…" : "Refresh Health Data")
                    .font(Theme.body(16, .semibold))
            }
            .foregroundStyle(Theme.emerald)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.emerald.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading)
    }

    private var syncButton: some View {
        PrimaryButton(
            title: store.isSyncing ? "Syncing…" : "Sync to ArogyaM",
            isLoading: store.isSyncing,
            systemImage: "arrow.up.heart.fill"
        ) { Task { await store.sync() } }
    }

    // MARK: - Status

    private var autoSyncStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text("Auto syncs every hour · Refreshed \(Self.ago(autoSync.lastRefreshed)) · Synced \(Self.ago(autoSync.lastSynced))")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private static func ago(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func statusBanner(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(13, .medium))
            .foregroundStyle(store.statusIsError ? Theme.rose : Theme.emerald)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((store.statusIsError ? Theme.rose : Theme.emerald).opacity(0.12)))
    }

    // MARK: - Helpers

    private func cardHeader(_ title: String, icon: String, tint: Color, refreshing: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(Theme.body(14, .semibold)).foregroundStyle(Theme.textSecondary)
            Spacer()
            if refreshing {
                ProgressView().tint(tint).scaleEffect(0.8)
            }
        }
    }

    private func metricCell(_ icon: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Theme.display(15, .bold)).foregroundStyle(Theme.text)
                HStack(spacing: 4) {
                    Text(label).font(Theme.body(11)).foregroundStyle(Theme.textMuted)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 9)).foregroundStyle(Theme.emerald)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.10)))
    }

    private func stageBar(fraction: Double, color: Color, width: CGFloat) -> some View {
        color.frame(width: max(0, CGFloat(fraction) * width))
    }

    private func stageLegend(_ label: String, _ hours: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(String(format: "%@ %.1fh", label, hours))
                .font(Theme.body(10)).foregroundStyle(Theme.textMuted)
        }
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        out.amSymbol = "am"; out.pmSymbol = "pm"
        return out.string(from: date)
    }

    private func workoutIcon(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("run"): return "figure.run"
        case let t where t.contains("walk"): return "figure.walk"
        case let t where t.contains("cycl") || t.contains("bike"): return "figure.outdoor.cycle"
        case let t where t.contains("swim"): return "figure.pool.swim"
        case let t where t.contains("yoga"): return "figure.yoga"
        case let t where t.contains("strength") || t.contains("lift"): return "dumbbell.fill"
        case let t where t.contains("hiit"): return "bolt.fill"
        default: return "figure.mixed.cardio"
        }
    }

    private func deviceIcon(_ name: String) -> String {
        let l = name.lowercased()
        if l.contains("watch") { return "applewatch" }
        if l.contains("phone") { return "iphone" }
        if l.contains("ipad") { return "ipad" }
        return "sensor.fill"
    }
}

