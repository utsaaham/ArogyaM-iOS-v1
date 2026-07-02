import Foundation
import Combine
import BackgroundTasks

/// Keeps Apple Health data flowing to ArogyaM on its own: refreshes the
/// 8-day HealthKit payload and pushes it to the server once an hour — from a
/// foreground timer while the app is open, and via BGAppRefreshTask when the
/// system grants background time. Also the single place that remembers when
/// data was last refreshed and last synced, so the UI can show it.
@MainActor
final class AutoSyncService: ObservableObject {
    static let shared = AutoSyncService()

    static let taskIdentifier = "com.kethan.ArogyaM-iOS-v1.healthsync"
    static let interval: TimeInterval = 3600

    private static let refreshedKey = "ArogyaM.lastRefreshed"
    private static let syncedKey = "ArogyaM.lastSynced"

    @Published var lastRefreshed: Date?
    @Published var lastSynced: Date?
    @Published var isSyncing = false

    private var timer: Timer?
    private let api = API.shared

    init() {
        lastRefreshed = UserDefaults.standard.object(forKey: Self.refreshedKey) as? Date
        lastSynced = UserDefaults.standard.object(forKey: Self.syncedKey) as? Date
    }

    /// Called once the user is inside the app: catches up immediately if the
    /// last sync is stale, then keeps checking while the app stays open.
    func start() {
        Task { await syncIfStale() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await AutoSyncService.shared.syncIfStale() }
        }
    }

    func syncIfStale() async {
        let stale = lastSynced.map { Date().timeIntervalSince($0) >= Self.interval } ?? true
        guard stale, !isSyncing else { return }
        await syncNow()
    }

    /// Full cycle: fetch the 8-day payload from HealthKit, push the snapshot,
    /// and post today's sleep and workouts to the daily log.
    @discardableResult
    func syncNow() async -> (sleep: Int, workouts: Int) {
        isSyncing = true
        defer { isSyncing = false }

        let payload = await HealthKitService.shared.fetchWeeklyPayload()
        noteRefreshed()

        try? await APIClient.shared.send(payload)

        var sleepCount = 0
        var workoutCount = 0
        if let today = payload.days.first(where: { $0.today == true }) {
            if let sleep = today.sleep, sleep.totalHours > 0,
               let bedtime = sleep.bedtime, let wake = sleep.wake {
                let quality = max(1, min(5, Int((sleep.totalHours / 2).rounded())))
                struct SleepBody: Encodable {
                    let date: String; let bedtime: String; let wakeTime: String
                    let duration: Double; let quality: Int; let notes: String
                }
                let body = SleepBody(date: today.date, bedtime: bedtime, wakeTime: wake,
                                     duration: sleep.totalHours, quality: quality,
                                     notes: "Synced from Apple Health")
                if let data = try? JSONEncoder().encode(body),
                   (try? await api.postExpectingSuccess("/api/sleep", json: data)) != nil {
                    sleepCount = 1
                }
            }

            for w in today.workouts {
                struct WorkoutBody: Encodable {
                    let date: String
                    let workout: Inner
                    struct Inner: Encodable {
                        let exercise: String; let category: String
                        let duration: Int; let caloriesBurned: Int
                        let source: String; let notes: String
                    }
                }
                let body = WorkoutBody(date: today.date, workout: .init(
                    exercise: w.type, category: Self.category(for: w.type),
                    duration: w.durationMin, caloriesBurned: w.calories,
                    source: "device", notes: "Apple Health"
                ))
                if let data = try? JSONEncoder().encode(body),
                   (try? await api.postExpectingSuccess("/api/workouts", json: data)) != nil {
                    workoutCount += 1
                }
            }
        }

        noteSynced()
        scheduleBackgroundRefresh()
        return (sleepCount, workoutCount)
    }

    func noteRefreshed() {
        lastRefreshed = Date()
        UserDefaults.standard.set(lastRefreshed, forKey: Self.refreshedKey)
    }

    func noteSynced() {
        lastSynced = Date()
        UserDefaults.standard.set(lastSynced, forKey: Self.syncedKey)
    }

    static func category(for type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("run") || t.contains("walk") || t.contains("cycl")
            || t.contains("hik") || t.contains("cardio") || t.contains("elliptical")
            || t.contains("row") || t.contains("hiit"):
            return "cardio"
        case let t where t.contains("strength"):
            return "strength"
        case let t where t.contains("yoga") || t.contains("pilates"):
            return "flexibility"
        case let t where t.contains("core"):
            return "core"
        default:
            return "other"
        }
    }

    // MARK: - Background refresh

    /// Must run before the app finishes launching.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let work = Task { @MainActor in
                await AutoSyncService.shared.syncNow()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
