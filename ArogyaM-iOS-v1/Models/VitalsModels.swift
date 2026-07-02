import Foundation

// Models for GET /api/scores — the Vitals daily score engine
// (Readiness, Strain, Sleep, Stress + guidance, trends, insights).
// Lenient like the rest of AppModels: everything optional so the app
// survives missing signals and older/newer server builds.

struct VitalsResponse: Decodable, Sendable {
    let date: String?
    let readiness: ReadinessScore?
    let strain: StrainScore?
    let sleep: SleepScore?
    let stress: StressScore?
    let guidance: VitalsGuidance?
    let trends: [VitalsTrendPoint]?
    let insights: [HabitInsight]?
    let journal: VitalsJournal?
}

struct VitalsScoreComponent: Decodable, Sendable, Identifiable {
    let key: String?
    let label: String?
    let score: Double?
    let note: String?

    var id: String { key ?? label ?? UUID().uuidString }
}

struct ReadinessScore: Decodable, Sendable {
    let score: Double?
    let components: [VitalsScoreComponent]?
    let drivers: [String]?
}

struct StrainScore: Decodable, Sendable {
    let score: Double?
    let zones: [HRZoneMinutes]?
    let components: [VitalsScoreComponent]?
}

struct HRZoneMinutes: Decodable, Sendable, Identifiable {
    let zone: String?
    let minutes: Double?

    var id: String { zone ?? UUID().uuidString }
}

struct SleepScore: Decodable, Sendable {
    let score: Double?
    let components: [VitalsScoreComponent]?
}

struct StressScore: Decodable, Sendable {
    let level: String?       // "low" | "moderate" | "high"
    let score: Double?       // 0-100 internal index
    let components: [VitalsScoreComponent]?
}

struct VitalsGuidance: Decodable, Sendable {
    let band: String?        // "push" | "maintain" | "recover" | "rest"
    let reason: String?
}

struct VitalsTrendPoint: Decodable, Sendable, Identifiable {
    let date: String?
    let readiness: Double?
    let strain: Double?
    let sleep: Double?
    let stress: Double?
    let hrvSdnnMs: Double?
    let restingHeartRate: Double?
    let vo2Max: Double?

    var id: String { date ?? UUID().uuidString }
}

struct HabitInsight: Decodable, Sendable, Identifiable {
    let habit: String?
    let metric: String?
    let delta: Double?
    let text: String?
    let sampleWith: Int?
    let sampleWithout: Int?

    var id: String { "\(habit ?? "?")-\(metric ?? "?")" }
}

struct VitalsJournal: Decodable, Sendable {
    let habits: [String]?
    let mood: Double?
}
