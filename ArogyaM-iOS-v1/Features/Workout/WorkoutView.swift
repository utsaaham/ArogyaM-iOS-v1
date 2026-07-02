import SwiftUI
import Charts
import Combine

// MARK: - Models (/api/workouts)

struct WorkoutHistoryResponse: Decodable, Sendable {
    let history: [WorkoutHistoryPoint]?
}

struct WorkoutHistoryPoint: Decodable, Sendable {
    let date: String?
    let caloriesBurned: Double?
    let duration: Double?
    let count: Int?
}

// MARK: - Store

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var todayWorkouts: [WorkoutEntry] = []
    @Published var goalMinutes: Double = 30
    @Published var history: [WorkoutHistoryPoint] = []
    @Published var isSaving = false
    @Published var loadedOnce = false

    private let api = API.shared

    var todayMinutes: Double { todayWorkouts.reduce(0) { $0 + ($1.duration ?? 0) } }
    var todayCalories: Double { todayWorkouts.reduce(0) { $0 + ($1.caloriesBurned ?? 0) } }
    var fraction: Double { goalMinutes > 0 ? min(todayMinutes / goalMinutes, 1) : 0 }

    func load() async {
        async let log: DailyLog? = try? await api.getEnveloped("/api/daily-log", query: ["date": DateUtil.todayKey])
        async let user: AppUser? = try? await api.getEnveloped("/api/user")
        async let hist: WorkoutHistoryResponse? = try? await api.getEnveloped("/api/workouts", query: ["days": "7"])

        todayWorkouts = (await log)?.workouts ?? []
        if let target = (await user)?.targets?.dailyWorkoutMinutes, target > 0 { goalMinutes = target }
        history = (await hist)?.history ?? []
        loadedOnce = true
    }

    func log(exercise: String, category: String, duration: Double?, calories: Double?,
             sets: Int?, reps: Int?, weight: Double?) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        struct WorkoutPayload: Encodable {
            let exercise: String
            let category: String
            let duration: Double?
            let caloriesBurned: Double?
            let sets: Int?
            let reps: Int?
            let weight: Double?
        }
        struct Payload: Encodable {
            let date: String
            let workout: WorkoutPayload
        }
        let payload = Payload(
            date: DateUtil.todayKey,
            workout: WorkoutPayload(exercise: exercise, category: category, duration: duration,
                                    caloriesBurned: calories, sets: sets, reps: reps, weight: weight)
        )
        guard let body = try? JSONEncoder().encode(payload) else { return false }
        do {
            try await api.postExpectingSuccess("/api/workouts", json: body)
            await load()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - View

struct WorkoutView: View {
    private static let categories = ["cardio", "strength", "yoga", "sports", "other"]

    @StateObject private var store = WorkoutStore()
    @State private var exercise = ""
    @State private var category = "cardio"
    @State private var durationText = ""
    @State private var caloriesText = ""
    @State private var setsText = ""
    @State private var repsText = ""
    @State private var weightText = ""
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Workout", subtitle: "Every session counts").padding(.top, 6)
                heroCard
                logCard
                if !store.todayWorkouts.isEmpty { todayCard }
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
            ProgressRing(progress: store.fraction, tint: Theme.red, size: 150, lineWidth: 14) {
                VStack(spacing: 2) {
                    Text("\(Int(store.todayMinutes))")
                        .font(Theme.number(32, .bold)).foregroundStyle(Theme.text)
                    Text("of \(Int(store.goalMinutes)) min")
                        .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 10) {
                statPill(icon: "flame.fill", value: "\(Int(store.todayCalories))", unit: "kcal burned")
                statPill(icon: "figure.run", value: "\(store.todayWorkouts.count)", unit: "sessions")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassCard(padding: 22)
    }

    private func statPill(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.red)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(Theme.number(16, .bold)).foregroundStyle(Theme.text)
                Text(unit).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LOG A WORKOUT").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)

            TextField("Exercise (e.g. Running, Bench press)", text: $exercise)
                .font(Theme.body(15))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.categories, id: \.self) { cat in
                        let selected = category == cat
                        Button { category = cat } label: {
                            Text(cat.capitalized)
                                .font(Theme.body(13, .semibold))
                                .foregroundStyle(selected ? Theme.red : Theme.textSecondary)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(Capsule().fill(selected ? Theme.red.opacity(0.12) : Theme.surface))
                        }
                        .buttonStyle(SpringyButtonStyle(scale: 0.95))
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                numberField("Minutes", text: $durationText)
                numberField("kcal (optional)", text: $caloriesText)
            }
            if category == "strength" {
                HStack(spacing: 10) {
                    numberField("Sets", text: $setsText)
                    numberField("Reps", text: $repsText)
                    numberField("Weight kg", text: $weightText)
                }
            }

            if saveFailed {
                Text("That didn't save. Check the exercise name and minutes, then try again.")
                    .font(Theme.body(12)).foregroundStyle(Theme.rose)
            }

            PrimaryButton(title: "Save Workout", tint: Theme.red, isLoading: store.isSaving, systemImage: "dumbbell.fill") {
                Task {
                    saveFailed = false
                    let name = exercise.trimmingCharacters(in: .whitespaces)
                    let duration = Double(durationText)
                    let reps = Int(repsText)
                    guard !name.isEmpty, (duration ?? 0) > 0 || (reps ?? 0) > 0 else {
                        saveFailed = true
                        return
                    }
                    let ok = await store.log(
                        exercise: name, category: category, duration: duration,
                        calories: Double(caloriesText), sets: Int(setsText), reps: reps,
                        weight: Double(weightText)
                    )
                    if ok {
                        exercise = ""; durationText = ""; caloriesText = ""
                        setsText = ""; repsText = ""; weightText = ""
                    } else {
                        saveFailed = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func numberField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(Theme.body(15))
            .keyboardType(.decimalPad)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            ForEach(Array(store.todayWorkouts.enumerated()), id: \.offset) { _, workout in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.red.opacity(0.12)).frame(width: 38, height: 38)
                        Image(systemName: "figure.run")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.red)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.exercise ?? "Workout")
                            .font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                        Text(workoutDetail(workout))
                            .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func workoutDetail(_ w: WorkoutEntry) -> String {
        var parts: [String] = []
        if let d = w.duration, d > 0 { parts.append("\(Int(d)) min") }
        if let s = w.sets, let r = w.reps, s > 0, r > 0 { parts.append("\(s) × \(r)") }
        if let kg = w.weight, kg > 0 { parts.append("\(Int(kg)) kg") }
        if let c = w.caloriesBurned, c > 0 { parts.append("\(Int(c)) kcal") }
        return parts.isEmpty ? (w.category?.capitalized ?? "Logged") : parts.joined(separator: " · ")
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAST 7 DAYS").font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
            Chart {
                ForEach(Array(store.history.enumerated()), id: \.offset) { _, point in
                    if let date = point.date {
                        BarMark(
                            x: .value("Day", String(date.suffix(5))),
                            y: .value("Minutes", point.duration ?? 0)
                        )
                        .foregroundStyle(Theme.red.gradient)
                        .cornerRadius(4)
                    }
                }
                RuleMark(y: .value("Goal", store.goalMinutes))
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
}
