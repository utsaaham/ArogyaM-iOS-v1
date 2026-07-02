import Foundation

struct WeeklyHealthPayload: Codable, Sendable {
    let extractedAt: String
    let days: [HealthSnapshot]
}

struct HealthSnapshot: Codable, Sendable {
    let date: String
    let today: Bool?
    let heart: HeartMetrics
    let activity: ActivityMetrics
    let sleep: SleepMetrics?
    let workouts: [WorkoutSummary]
    let vitals: VitalsMetrics?
}

struct HeartMetrics: Codable, Sendable {
    let avgBpm: Int?
    let restingBpm: Int?
    let hrvSdnnMs: Double?
}

/// Recovery signals for the server-side readiness score. All optional —
/// availability depends on hardware (wrist temperature needs an Apple Watch
/// Series 8+ worn during sleep).
struct VitalsMetrics: Codable, Sendable {
    let respiratoryRate: Double?
    let wristTempC: Double?
    let vo2Max: Double?

    var isEmpty: Bool {
        respiratoryRate == nil && wristTempC == nil && vo2Max == nil
    }
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
