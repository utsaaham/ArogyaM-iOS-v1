import SwiftUI

struct ContentView: View {
    @State private var payload: WeeklyHealthPayload?
    @State private var status: String = ""
    @State private var isBusy: Bool = false
    @State private var connectedDevices: [String] = []

    private var todayDay: HealthSnapshot? {
        payload?.days.first(where: { $0.today == true })
    }

    private var pastDays: [HealthSnapshot] {
        (payload?.days ?? []).filter { $0.today != true }
    }

    var body: some View {
        NavigationStack {
            List {
                if !status.isEmpty {
                    Section { Text(status).bold() }
                }

                Section("Connectors") {
                    if connectedDevices.isEmpty {
                        Text("No connectors detected").foregroundStyle(.secondary)
                    } else {
                        ForEach(connectedDevices, id: \.self) { device in
                            Label(device, systemImage: deviceIcon(for: device))
                        }
                    }
                }

                Section {
                    DaySnapshotDetail(snapshot: todayDay, todayLabels: true)
                } header: {
                    SectionHeader(
                        title: "Today",
                        subtitle: formatDay(todayDay?.date)
                    )
                }

                Section {
                    if !pastDays.isEmpty {
                        ForEach(pastDays, id: \.date) { day in
                            DisclosureGroup(formatDay(day.date)) {
                                DaySnapshotDetail(snapshot: day, todayLabels: false)
                            }
                        }
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(
                        title: "Last Week",
                        subtitle: "Extracted · past 7 days"
                    )
                }
            }
            .navigationTitle("Rhythm")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") { Task { await refresh() } }
                        .disabled(isBusy)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") { Task { await send() } }
                        .bold()
                        .disabled(isBusy || payload == nil)
                }
            }
        }
        .task { await initialLoad() }
    }

    private func initialLoad() async {
        status = "Requesting permission…"
        do {
            try await HealthKitService.shared.requestAuthorization()
        } catch {
            status = "❌ Auth error: \(error.localizedDescription)"
            return
        }
        await refresh()
    }

    private func refresh() async {
        isBusy = true
        status = "Loading…"
        async let p = HealthKitService.shared.fetchWeeklyPayload()
        async let devices = HealthKitService.shared.fetchConnectedSources()
        self.payload = await p
        self.connectedDevices = await devices
        status = "⌚ Week extracted (today + 7 prior days)"
        isBusy = false
    }

    private func send() async {
        guard let p = payload else {
            status = "❌ Nothing to send — tap Refresh first"
            return
        }
        isBusy = true
        status = "Sending…"
        do {
            try await APIClient.shared.send(p)
            status = "⌚ Week of data sent"
        } catch {
            status = error.localizedDescription
        }
        isBusy = false
    }

    private func deviceIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("watch") { return "applewatch" }
        if lower.contains("iphone") || lower.contains("phone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("health") { return "heart.fill" }
        return "sensor.fill"
    }
}

private struct DaySnapshotDetail: View {
    let snapshot: HealthSnapshot?
    let todayLabels: Bool

    var body: some View {
        if let bpm = snapshot?.heart.avgBpm {
            MetricRow(icon: "heart.fill", tint: .red,
                      label: "Heart Rate" + (todayLabels ? " (avg today)" : " (avg)"),
                      value: "\(bpm) BPM")
        } else if snapshot != nil {
            MetricRow(icon: "heart.fill", tint: .red, label: "Heart Rate", value: "—")
        } else {
            Text("—").foregroundStyle(.secondary)
        }

        MetricRow(icon: "figure.walk", tint: .green,
                  label: "Steps",
                  value: "\(snapshot?.activity.steps ?? 0)")
        MetricRow(icon: "flame.fill", tint: .orange,
                  label: "Active Calories",
                  value: "\(snapshot?.activity.activeCalories ?? 0) kcal")
        MetricRow(icon: "location.fill", tint: .blue,
                  label: "Distance",
                  value: "\(String(format: "%.2f", snapshot?.activity.distanceKm ?? 0)) km")

        if let sleep = snapshot?.sleep {
            DisclosureGroup {
                Text("· Core: \(String(format: "%.1f", sleep.stages.coreHours)) hrs")
                Text("· Deep: \(String(format: "%.1f", sleep.stages.deepHours)) hrs")
                Text("· REM: \(String(format: "%.1f", sleep.stages.remHours)) hrs")
                Text("· Awake: \(String(format: "%.1f", sleep.stages.awakeHours)) hrs")
            } label: {
                MetricRow(icon: "moon.zzz.fill", tint: .indigo,
                          label: "Sleep",
                          value: "\(String(format: "%.1f", sleep.totalHours)) hrs")
            }
        } else if snapshot != nil {
            MetricRow(icon: "moon.zzz.fill", tint: .indigo, label: "Sleep", value: "—")
        }

        if let workouts = snapshot?.workouts, !workouts.isEmpty {
            let totalKcal = workouts.reduce(0) { $0 + $1.calories }
            DisclosureGroup {
                ForEach(workouts) { w in
                    WorkoutRow(workout: w)
                }
            } label: {
                MetricRow(icon: "figure.run", tint: .pink,
                          label: "Workouts",
                          value: "\(totalKcal) kcal")
            }
        } else if snapshot != nil {
            MetricRow(icon: "figure.run", tint: .pink, label: "Workouts", value: "None")
        }
    }
}

private struct MetricRow: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.type).font(.headline)
            HStack {
                Text("🕐 \(workout.durationMin) min")
                Spacer()
                Text("🔥 \(workout.calories) kcal")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if workout.distanceKm > 0 {
                Text("📏 \(String(format: "%.2f", workout.distanceKm)) km")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let hr = workout.avgHeartRate {
                Text("❤️ \(hr) BPM avg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .padding(.vertical, 6)
    }
}

private let dayParser: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let dayDisplay: DateFormatter = {
    let f = DateFormatter()
    f.timeZone = .current
    f.dateFormat = "EEE, MMM d"
    return f
}()

private func formatDay(_ iso: String?) -> String {
    guard let iso, let date = dayParser.date(from: iso) else { return "—" }
    return dayDisplay.string(from: date)
}
