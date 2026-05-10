import Foundation

struct WeeklyHealthPayload: Codable, Sendable {
    let extractedAt: String
    let today: HealthSnapshot
    let previousDays: [HealthSnapshot]
}

struct HealthSnapshot: Codable, Sendable {
    let date: String
    let heart: HeartMetrics
    let activity: ActivityMetrics
    let sleep: SleepMetrics?
    let workouts: [WorkoutSummary]
}

struct HeartMetrics: Codable, Sendable {
    let avgBpm: Int?
}

struct ActivityMetrics: Codable, Sendable {
    let steps: Int
    let activeCalories: Int
    let distanceKm: Double
}

struct SleepMetrics: Codable, Sendable {
    let totalHours: Double
    let stages: SleepStages
    let bedtime: String?
    let wake: String?
}

struct SleepStages: Codable, Sendable {
    let awakeHours: Double
    let coreHours: Double
    let deepHours: Double
    let remHours: Double
}

struct WorkoutSummary: Codable, Identifiable, Sendable {
    let uuid: String
    let type: String
    let durationMin: Int
    let calories: Int
    let distanceKm: Double
    let avgHeartRate: Int?
    let startedAt: String
    let endedAt: String

    var id: String { uuid }
}
