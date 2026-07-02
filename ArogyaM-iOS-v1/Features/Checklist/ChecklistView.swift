import SwiftUI
import Combine

// MARK: - Models (/api/todos + /api/ai/daily-plan/*)

struct TodosResponse: Decodable, Sendable {
    let date: String?
    let templates: [TodoTemplate]?
    let completions: [TodoCompletion]?
}

struct TodoTemplate: Decodable, Sendable {
    let id: String?
    let title: String?
    let note: String?
    let time: String?
    let category: String?
    let cadence: String?
    let lastDone: String?

    var key: String { id ?? title ?? "" }
    var isCare: Bool { category == "care" }
}

struct TodoCompletion: Decodable, Sendable {
    let templateId: String?
    let completedAt: String?
}

struct PlanOverviewResponse: Decodable, Sendable {
    let topInsight: String?
    let status: String?
    let todayLog: PlanDaySummary?
}

struct PlanDaySummary: Decodable, Sendable {
    let totalCalories: Double?
    let totalProtein: Double?
    let totalCarbs: Double?
    let totalFat: Double?
    let waterIntake: Double?
    let workoutMinutes: Double?
    let sleep: PlanSleepSummary?
    let weight: Double?
}

struct PlanSleepSummary: Decodable, Sendable {
    let duration: Double?
    let quality: Double?
}

struct FoodPlanResponse: Decodable, Sendable {
    let foodPlan: FoodPlan?
    let status: String?
}

struct FoodPlan: Decodable, Sendable {
    let suggestions: [MealSuggestion]?
    let reasoning: String?
}

struct MealSuggestion: Decodable, Sendable {
    let name: String?
    let description: String?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let mealType: String?
    let isVegetarian: Bool?
    let ingredients: [String]?
}

struct WorkoutPlanResponse: Decodable, Sendable {
    let workoutPlan: PlanWorkout?
    let status: String?
}

struct PlanWorkout: Decodable, Sendable {
    let name: String?
    let description: String?
    let whyToday: String?
    let progressionTip: String?
    let exercises: [PlanExercise]?
}

struct PlanExercise: Decodable, Sendable {
    let name: String?
    let sets: Int?
    let reps: String?
    let phase: String?
    let durationMinutes: Double?
    let restSeconds: Int?
    let steps: [String]?
}

// MARK: - Care cadence (mirrors lib/careCadence.ts)

enum CareCycle {
    static func days(for cadence: String?) -> Int {
        switch cadence {
        case "weekly": return 7
        case "biweekly": return 14
        case "quarterly": return 91
        case "yearly": return 365
        default: return 30 // monthly
        }
    }

    static func label(for cadence: String?) -> String {
        switch cadence {
        case "weekly": return "Weekly"
        case "biweekly": return "Every 2 weeks"
        case "quarterly": return "Every 3 months"
        case "yearly": return "Yearly"
        default: return "Monthly"
        }
    }

    enum Status {
        case never
        case done(nextInDays: Int)
        case due
        case overdue(by: Int)
    }

    static func status(lastDone: String?, cadence: String?) -> Status {
        guard let lastDone, let then = DateUtil.date(fromKey: lastDone) else { return .never }
        let cycle = days(for: cadence)
        let ago = Int((Date().timeIntervalSince(then) / 86_400).rounded())
        if ago < cycle { return .done(nextInDays: cycle - ago) }
        let overdueBy = ago - cycle
        if overdueBy <= max(2, Int((Double(cycle) * 0.15).rounded())) { return .due }
        return .overdue(by: overdueBy)
    }
}

// MARK: - Store

@MainActor
final class ChecklistStore: ObservableObject {
    @Published var templates: [TodoTemplate] = []
    @Published var completedIds: Set<String> = []
    @Published var loadedOnce = false

    @Published var overview: PlanOverviewResponse?
    @Published var foodPlan: FoodPlan?
    @Published var workoutPlan: PlanWorkout?
    @Published var plansLoaded = false

    private let api = API.shared

    var todos: [TodoTemplate] { templates.filter { !$0.isCare } }
    var careItems: [TodoTemplate] { templates.filter { $0.isCare } }

    func load() async {
        if let res: TodosResponse = try? await api.getEnveloped("/api/todos", query: ["date": DateUtil.todayKey]) {
            templates = res.templates ?? []
            completedIds = Set((res.completions ?? []).compactMap { $0.templateId })
        }
        loadedOnce = true
    }

    func loadPlans() async {
        async let ov: PlanOverviewResponse? = try? await api.getEnveloped("/api/ai/daily-plan/overview")
        async let food: FoodPlanResponse? = try? await api.getEnveloped("/api/ai/daily-plan/food")
        async let workout: WorkoutPlanResponse? = try? await api.getEnveloped("/api/ai/daily-plan/workout")
        overview = await ov
        foodPlan = (await food)?.foodPlan
        workoutPlan = (await workout)?.workoutPlan
        plansLoaded = true
    }

    func toggle(_ template: TodoTemplate) async {
        let id = template.key
        guard !id.isEmpty else { return }
        let nowCompleted = !completedIds.contains(id)
        // Optimistic flip; reload on failure to resync.
        if nowCompleted { completedIds.insert(id) } else { completedIds.remove(id) }

        struct Payload: Encodable { let templateId: String; let date: String; let completed: Bool }
        let payload = Payload(templateId: id, date: DateUtil.todayKey, completed: nowCompleted)
        guard let body = try? JSONEncoder().encode(payload) else { return }
        do {
            try await api.postExpectingSuccess("/api/todos", json: body)
            if template.isCare { await load() } // refresh lastDone for cadence badges
        } catch {
            await load()
        }
    }
}

// MARK: - View

struct ChecklistView: View {
    enum Segment: String, CaseIterable {
        case todos = "To-dos"
        case care = "Care"
        case overview = "Overview"
        case food = "Food"
        case workout = "Workout"

        var icon: String {
            switch self {
            case .todos: return "checklist"
            case .care: return "scissors"
            case .overview: return "bolt.fill"
            case .food: return "flame.fill"
            case .workout: return "dumbbell.fill"
            }
        }
    }

    @StateObject private var store = ChecklistStore()
    @State private var section: Segment = .todos

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Checklist", subtitle: "Your daily to-dos and the care stuff we remember for you")
                    .padding(.top, 6)

                sectionPicker

                switch section {
                case .todos: todosSection
                case .care: careSection
                case .overview: overviewSection
                case .food: foodSection
                case .workout: workoutSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.load()
            await store.loadPlans()
        }
        .task { if !store.loadedOnce { await store.load() } }
        .task(id: section) {
            if !store.plansLoaded, [.overview, .food, .workout].contains(section) {
                await store.loadPlans()
            }
        }
    }

    // MARK: Section picker

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Segment.allCases, id: \.self) { s in
                    let selected = section == s
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { section = s }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: s.icon).font(.system(size: 12, weight: .semibold))
                            Text(s.rawValue).font(Theme.body(14, .semibold))
                        }
                        .foregroundStyle(selected ? Theme.purple : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(selected ? Theme.purple.opacity(0.14) : Theme.card)
                        )
                        .overlay {
                            Capsule().strokeBorder(selected ? Theme.purple.opacity(0.3) : Theme.hairline, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(SpringyButtonStyle(scale: 0.95))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: To-dos

    private var todosSection: some View {
        VStack(spacing: 10) {
            if store.loadedOnce && store.todos.isEmpty {
                emptyCard(icon: "checklist",
                          text: "No to-dos yet. Add some in Settings → Reminders on the web app.")
            }
            ForEach(store.todos, id: \.key) { todo in
                todoRow(todo)
            }
        }
    }

    private func todoRow(_ todo: TodoTemplate) -> some View {
        let done = store.completedIds.contains(todo.key)
        return Button { Task { await store.toggle(todo) } } label: {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(done ? Theme.green : Theme.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title ?? "Untitled")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(done ? Theme.textMuted : Theme.text)
                        .strikethrough(done, color: Theme.textMuted)
                    if let note = todo.note, !note.isEmpty {
                        Text(note).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let time = todo.time, !time.isEmpty {
                    GlassChip(text: time, tint: Theme.indigo, systemImage: "clock")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14)
        }
        .buttonStyle(SpringyButtonStyle(scale: 0.98))
    }

    // MARK: Care

    private var careSection: some View {
        VStack(spacing: 10) {
            if store.loadedOnce && store.careItems.isEmpty {
                emptyCard(icon: "scissors",
                          text: "No care routines yet. Things like haircuts and dentist visits live here.")
            }
            ForEach(store.careItems, id: \.key) { item in
                careRow(item)
            }
        }
    }

    private func careRow(_ item: TodoTemplate) -> some View {
        let doneToday = store.completedIds.contains(item.key)
        let status = CareCycle.status(lastDone: item.lastDone, cadence: item.cadence)
        return Button { Task { await store.toggle(item) } } label: {
            HStack(spacing: 14) {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(doneToday ? Theme.green : Theme.textMuted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Untitled")
                        .font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        Text(CareCycle.label(for: item.cadence))
                            .font(Theme.body(11, .medium)).foregroundStyle(Theme.textMuted)
                        careBadge(status, doneToday: doneToday)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14)
        }
        .buttonStyle(SpringyButtonStyle(scale: 0.98))
    }

    @ViewBuilder
    private func careBadge(_ status: CareCycle.Status, doneToday: Bool) -> some View {
        if doneToday {
            GlassChip(text: "Done today", tint: Theme.green, systemImage: "checkmark")
        } else {
            switch status {
            case .never:
                GlassChip(text: "Never done", tint: Theme.textMuted)
            case .done(let nextInDays):
                GlassChip(text: "Next in \(nextInDays)d", tint: Theme.green, systemImage: "checkmark")
            case .due:
                GlassChip(text: "Due now", tint: Theme.amber, systemImage: "clock")
            case .overdue(let by):
                GlassChip(text: "Overdue \(by)d", tint: Theme.rose, systemImage: "exclamationmark.circle")
            }
        }
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewSection: some View {
        if let insight = store.overview?.topInsight, !insight.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.gold)
                Text(insight).font(Theme.body(14)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }

        if let log = store.overview?.todayLog {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile(icon: "flame.fill", tint: Theme.orange, label: "Calories",
                         value: "\(Int(log.totalCalories ?? 0)) kcal")
                StatTile(icon: "fork.knife", tint: Theme.green, label: "Protein",
                         value: "\(Int(log.totalProtein ?? 0)) g")
                StatTile(icon: "drop.fill", tint: Theme.cyan, label: "Water",
                         value: "\(Int(log.waterIntake ?? 0)) ml")
                StatTile(icon: "dumbbell.fill", tint: Theme.red, label: "Workout",
                         value: "\(Int(log.workoutMinutes ?? 0)) min")
            }
        }

        if store.plansLoaded && store.overview?.topInsight == nil && store.overview?.todayLog == nil {
            emptyCard(icon: "moon.stars.fill",
                      text: "No overview yet. Kiki writes today's plan overnight — check back soon.")
        } else if !store.plansLoaded {
            loadingCard
        }
    }

    // MARK: Food plan

    @ViewBuilder
    private var foodSection: some View {
        if let meals = store.foodPlan?.suggestions, !meals.isEmpty {
            let order = ["breakfast", "lunch", "dinner", "snack"]
            let grouped = Dictionary(grouping: meals) { ($0.mealType ?? "snack").lowercased() }
            ForEach(order.filter { grouped[$0] != nil }, id: \.self) { type in
                VStack(alignment: .leading, spacing: 8) {
                    Text(type.uppercased())
                        .font(Theme.body(11, .semibold)).tracking(0.8).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array((grouped[type] ?? []).enumerated()), id: \.offset) { _, meal in
                        mealCard(meal)
                    }
                }
            }
            if let reasoning = store.foodPlan?.reasoning, !reasoning.isEmpty {
                Text(reasoning).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 14)
            }
        } else if store.plansLoaded {
            emptyCard(icon: "fork.knife",
                      text: "No meal plan yet. Kiki cooks one up overnight — check back soon.")
        } else {
            loadingCard
        }
    }

    private func mealCard(_ meal: MealSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(meal.name ?? "Meal").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                if meal.isVegetarian == true {
                    GlassChip(text: "Veg", tint: Theme.green)
                }
            }
            if let desc = meal.description, !desc.isEmpty {
                Text(desc).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                GlassChip(text: "\(Int(meal.calories ?? 0)) kcal", tint: Theme.orange, systemImage: "flame.fill")
                GlassChip(text: "P \(Int(meal.protein ?? 0))g", tint: Theme.green)
                GlassChip(text: "C \(Int(meal.carbs ?? 0))g", tint: Theme.cyan)
                GlassChip(text: "F \(Int(meal.fat ?? 0))g", tint: Theme.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    // MARK: Workout plan

    @ViewBuilder
    private var workoutSection: some View {
        if let plan = store.workoutPlan {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.name ?? "Today's workout")
                    .font(Theme.display(17, .bold)).foregroundStyle(Theme.text)
                if let desc = plan.description, !desc.isEmpty {
                    Text(desc).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let why = plan.whyToday, !why.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.purple)
                        Text(why).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            ForEach(Array((plan.exercises ?? []).enumerated()), id: \.offset) { i, ex in
                exerciseRow(index: i + 1, ex)
            }
        } else if store.plansLoaded {
            emptyCard(icon: "dumbbell.fill",
                      text: "No workout plan yet. Kiki builds one overnight — check back soon.")
        } else {
            loadingCard
        }
    }

    private func exerciseRow(index: Int, _ ex: PlanExercise) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.red.opacity(0.12)).frame(width: 34, height: 34)
                Text("\(index)").font(Theme.number(15, .bold)).foregroundStyle(Theme.red)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ex.name ?? "Exercise").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                Text(exerciseDetail(ex)).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if let phase = ex.phase, !phase.isEmpty {
                GlassChip(text: phase.capitalized, tint: Theme.indigo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    private func exerciseDetail(_ ex: PlanExercise) -> String {
        var parts: [String] = []
        if let sets = ex.sets, sets > 0 {
            if let reps = ex.reps, !reps.isEmpty {
                parts.append("\(sets) × \(reps)")
            } else {
                parts.append("\(sets) sets")
            }
        } else if let reps = ex.reps, !reps.isEmpty {
            parts.append(reps)
        }
        if let mins = ex.durationMinutes, mins > 0 { parts.append("\(Int(mins)) min") }
        if let rest = ex.restSeconds, rest > 0 { parts.append("rest \(rest)s") }
        return parts.isEmpty ? "As prescribed" : parts.joined(separator: " · ")
    }

    // MARK: Shared bits

    private func emptyCard(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassCard()
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading…").font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard()
    }
}
