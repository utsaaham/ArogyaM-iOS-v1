import Foundation

// All arogyamandiram API routes wrap payloads in { success, data, error, message }.
// These models are intentionally lenient (almost everything optional) so the app
// stays resilient to missing/extra fields across endpoints.

// MARK: - Envelope

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let error: String?
    let message: String?
}

// MARK: - User (/api/user, /api/auth/mobile login user)

struct AppUser: Decodable, Sendable {
    let id: String?
    let username: String?
    let email: String?
    let profile: UserProfile?
    let targets: UserTargets?
    let settings: UserSettings?
    let achievements: Achievements?
    let onboardingComplete: Bool?
}

struct UserProfile: Decodable, Sendable {
    let name: String?
    let gender: String?
    let height: Double?
    let weight: Double?
    let targetWeight: Double?
    let activityLevel: String?
    let goal: String?
    let avatarUrl: String?
}

struct UserTargets: Decodable, Sendable {
    let dailyCalories: Double?
    let dailyWater: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let idealWeight: Double?
    let dailyWorkoutMinutes: Double?
    let dailyCalorieBurn: Double?
    let sleepHours: Double?
    let dailySteps: Double?
    let idealDistance: Double?
}

struct UserSettings: Decodable, Sendable {
    let theme: String?
    let units: String?
    let customizations: Customizations?

    struct Customizations: Decodable, Sendable {
        let water: WaterCustom?
        struct WaterCustom: Decodable, Sendable {
            let quickAmountsMl: [Int]?
        }
    }
}

// MARK: - Achievements (/api/achievements)

/// `/api/achievements` wraps the real data under an `achievements` key and also
/// returns level/XP progress at the top level.
struct AchievementsResponse: Decodable, Sendable {
    let achievements: Achievements?
    let xpTotal: Int?
    let level: Int?
    let xpIntoLevel: Int?
    let xpForCurrentLevel: Int?
    let xpPercent: Double?
}

struct Achievements: Decodable, Sendable {
    let xpTotal: Int?
    let streaks: Streaks?
    let badges: [Badge]?
}

struct Streaks: Decodable, Sendable {
    let current: StreakSet?
    let best: StreakSet?
}

struct StreakSet: Decodable, Sendable {
    let logging: Int?
    let healthy: Int?
    let calories: Int?
    let water: Int?
    let workout: Int?
    let sleep: Int?
    let weight: Int?
    let steps: Int?
}

struct Badge: Decodable, Sendable {
    let id: String?
    let name: String?
    let description: String?
    let icon: String?
    let category: String?
    let earnedAt: String?
}

// MARK: - Daily log (/api/daily-log?date=)

struct DailyLog: Decodable, Sendable {
    let date: String?
    let weight: Double?
    let waterIntake: Double?
    let waterEntries: [WaterEntry]?
    let meals: [Meal]?
    let workouts: [WorkoutEntry]?
    let sleep: SleepEntry?
    let totalCalories: Double?
    let totalProtein: Double?
    let totalCarbs: Double?
    let totalFat: Double?
    let totalFiber: Double?
    let totalSugar: Double?
    let totalSodium: Double?
    let caloriesBurned: Double?
    let heartRate: Double?
    let steps: Double?
    let activeCalories: Double?
    let distanceKm: Double?
    let notes: String?
}

struct WaterEntry: Decodable, Sendable {
    let amount: Double?
    let time: String?
}

struct Meal: Decodable, Sendable {
    let name: String?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let quantity: Double?
    let unit: String?
    let mealType: String?
    let time: String?
}

struct WorkoutEntry: Decodable, Sendable {
    let exercise: String?
    let category: String?
    let duration: Double?
    let caloriesBurned: Double?
    let sets: Int?
    let reps: Int?
    let weight: Double?
    let notes: String?
}

struct SleepEntry: Decodable, Sendable {
    let bedtime: String?
    let wakeTime: String?
    let duration: Double?
    let quality: Int?
    let notes: String?
}

// MARK: - Water history (/api/water?days=)

struct WaterHistory: Decodable, Sendable {
    let history: [WaterHistoryPoint]?
    let count: Int?
    let period: String?
}

struct WaterHistoryPoint: Decodable, Sendable {
    let date: String?
    let waterIntake: Double?
}

struct WaterLogResult: Decodable, Sendable {
    let date: String?
    let waterIntake: Double?
    let added: Double?
}

// MARK: - Food search (/api/foods)

struct FoodSearchResponse: Decodable, Sendable {
    let foods: [FoodItem]?
}

struct FoodItem: Decodable, Sendable, Identifiable {
    let id: String?
    let name: String?
    let category: String?
    let calories: Double?     // per 100 g/ml
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let servingSize: Double?  // base, usually 100
    let servingUnit: String?  // "g" | "ml"
    let isVegetarian: Bool?
}

// MARK: - Health metrics (/api/health-metrics)

struct HealthMetricsResponse: Decodable, Sendable {
    let today: HealthToday?
}

struct HealthToday: Decodable, Sendable {
    let heartRate: Double?
    let steps: Double?
    let activeCalories: Double?
    let distanceKm: Double?
    let distance: Double?
}

// MARK: - AI orchestrator (/api/ai/orchestrator)

struct AIResult: Decodable, Sendable {
    let tool: String?
    let result: JSONValue?
}

// MARK: - Flexible JSON value (for dynamic AI results)

enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .null
        }
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.formatted()
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}
