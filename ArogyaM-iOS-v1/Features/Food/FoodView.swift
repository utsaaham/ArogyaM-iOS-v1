import SwiftUI
import Combine

@MainActor
final class FoodStore: ObservableObject {
    @Published var query = ""
    @Published var results: [FoodItem] = []
    @Published var log: DailyLog?
    @Published var targets: UserTargets?
    @Published var isSearching = false
    @Published var loadedOnce = false

    private let api = API.shared
    private var searchTask: Task<Void, Never>?

    var meals: [Meal] { log?.meals ?? [] }

    func loadToday() async {
        async let l: DailyLog? = try? await api.getEnveloped("/api/daily-log", query: ["date": DateUtil.todayKey])
        async let u: AppUser? = try? await api.getEnveloped("/api/user")
        log = await l
        targets = (await u)?.targets
        loadedOnce = true
    }

    func search(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            isSearching = true
            defer { isSearching = false }
            let resp: FoodSearchResponse? = try? await api.getEnveloped("/api/foods", query: ["q": q])
            if Task.isCancelled { return }
            results = resp?.foods ?? []
        }
    }

    func logMeal(_ food: FoodItem, grams: Double, mealType: String) async {
        let base = food.servingSize ?? 100
        let factor = base > 0 ? grams / base : 1
        struct MealBody: Encodable {
            let date: String
            let meal: Inner
            struct Inner: Encodable {
                let name: String; let calories: Double; let protein: Double
                let carbs: Double; let fat: Double; let quantity: Double
                let unit: String; let mealType: String; let isCustom: Bool
                let foodId: String?
            }
        }
        let meal = MealBody.Inner(
            name: food.name ?? "Food",
            calories: (food.calories ?? 0) * factor,
            protein: (food.protein ?? 0) * factor,
            carbs: (food.carbs ?? 0) * factor,
            fat: (food.fat ?? 0) * factor,
            quantity: grams, unit: food.servingUnit ?? "g",
            mealType: mealType, isCustom: false, foodId: food.id
        )
        let body = MealBody(date: DateUtil.todayKey, meal: meal)
        if let data = try? JSONEncoder().encode(body) {
            try? await api.postExpectingSuccess("/api/daily-log/meal", json: data)
        }
        await loadToday()
    }
}

struct FoodView: View {
    @StateObject private var store = FoodStore()
    @State private var selected: FoodItem?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Food", subtitle: "Search & log meals").padding(.top, 6)
                summaryCard
                searchBar
                if store.isSearching {
                    ProgressView().tint(Theme.orange).padding(.top, 10)
                } else if !store.results.isEmpty {
                    resultsCard
                } else {
                    loggedCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .task { if !store.loadedOnce { await store.loadToday() } }
        .sheet(item: $selected) { food in
            LogMealSheet(food: food) { grams, mealType in
                Task { await store.logMeal(food, grams: grams, mealType: mealType) }
                selected = nil
            }
            .presentationDetents([.height(360)])
        }
    }

    private var summaryCard: some View {
        let consumed = store.log?.totalCalories ?? 0
        let goal = store.targets?.dailyCalories ?? 2000
        let pct = goal > 0 ? consumed / goal : 0
        return HStack(spacing: 18) {
            ProgressRing(progress: pct, tint: Theme.orange, size: 92, lineWidth: 10) {
                VStack(spacing: 0) {
                    Text("\(Int(consumed))").font(Theme.number(20, .bold)).foregroundStyle(Theme.text)
                    Text("kcal").font(Theme.body(10)).foregroundStyle(Theme.textMuted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int(consumed)) / \(Int(goal)) kcal")
                    .font(Theme.display(17, .bold)).foregroundStyle(Theme.text)
                MacroBar(label: "Protein", value: store.log?.totalProtein ?? 0,
                         goal: store.targets?.protein ?? 150, tint: Theme.purple)
                MacroBar(label: "Carbs", value: store.log?.totalCarbs ?? 0,
                         goal: store.targets?.carbs ?? 255, tint: Theme.orange)
                MacroBar(label: "Fat", value: store.log?.totalFat ?? 0,
                         goal: store.targets?.fat ?? 85, tint: Theme.pink)
            }
        }
        .glassCard(padding: 16)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
            TextField("Search foods…", text: $store.query)
                .font(Theme.body(16)).foregroundStyle(Theme.text)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .onChange(of: store.query) { _, q in store.search(q) }
            if !store.query.isEmpty {
                Button { store.query = ""; store.results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5)))
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            ForEach(store.results.prefix(20)) { food in
                Button { selected = food } label: { foodRow(food) }
                    .buttonStyle(.plain)
                if food.id != store.results.prefix(20).last?.id {
                    Divider().overlay(Theme.hairline).padding(.leading, 14)
                }
            }
        }
        .glassCard(padding: 0)
    }

    private func foodRow(_ food: FoodItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name ?? "Food").font(Theme.body(15, .medium)).foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(Int(food.calories ?? 0)) kcal · per \(Int(food.servingSize ?? 100))\(food.servingUnit ?? "g")")
                    .font(Theme.body(12)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.orange).font(.system(size: 22))
        }
        .padding(14)
    }

    private var loggedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logged today").font(Theme.body(13, .semibold)).tracking(0.6).foregroundStyle(Theme.textMuted)
            if store.meals.isEmpty {
                Text("Nothing logged yet, and that's okay. Search above, or just tell Kiki “ate 2 eggs and toast” and she'll handle the rest 💛")
                    .font(Theme.body(13)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                ForEach(Array(store.meals.enumerated()), id: \.offset) { _, meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name ?? "Food").font(Theme.body(15, .medium)).foregroundStyle(Theme.text)
                            Text("\((meal.mealType ?? "").capitalized) · \(Int(meal.quantity ?? 0))\(meal.unit ?? "g")")
                                .font(Theme.body(12)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Text("\(Int(meal.calories ?? 0)) kcal")
                            .font(Theme.number(14, .bold)).foregroundStyle(Theme.orange)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }
}

private struct LogMealSheet: View {
    let food: FoodItem
    var onAdd: (Double, String) -> Void

    @State private var grams: Double = 100
    @State private var mealType = "lunch"
    private let mealTypes = ["breakfast", "lunch", "dinner", "snack"]

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(Theme.track).frame(width: 40, height: 5).padding(.top, 8)
            VStack(spacing: 4) {
                Text(food.name ?? "Food").font(Theme.display(20, .bold)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                let factor = (food.servingSize ?? 100) > 0 ? grams / (food.servingSize ?? 100) : 1
                Text("\(Int((food.calories ?? 0) * factor)) kcal")
                    .font(Theme.number(16, .bold)).foregroundStyle(Theme.orange)
            }

            Picker("Meal", selection: $mealType) {
                ForEach(mealTypes, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                stepper("-") { grams = max(10, grams - 10) }
                VStack(spacing: 0) {
                    Text("\(Int(grams))").font(Theme.number(28, .bold)).foregroundStyle(Theme.text)
                    Text(food.servingUnit ?? "g").font(Theme.body(12)).foregroundStyle(Theme.textMuted)
                }.frame(width: 90)
                stepper("+") { grams += 10 }
            }

            PrimaryButton(title: "Add to Log", tint: Theme.orange, systemImage: "plus") {
                onAdd(grams, mealType)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .background(Theme.bg)
    }

    private func stepper(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol == "+" ? "plus" : "minus")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.orange)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Theme.orange.opacity(0.12)))
        }.buttonStyle(.plain)
    }
}
