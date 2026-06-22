import Foundation
import HealthKit

final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchWeeklyPayload() async -> WeeklyHealthPayload {
        let cal = Calendar.current
        let now = Date()
        // Indices 0…7: 0 = today, 1 = yesterday, …, 7 = 7 days ago.
        let dates: [Date] = (0...7).compactMap {
            $0 == 0 ? now : cal.date(byAdding: .day, value: -$0, to: now)
        }

        let days: [HealthSnapshot] = await withTaskGroup(of: (Int, HealthSnapshot).self) { group in
            for (i, d) in dates.enumerated() {
                let isToday = (i == 0)
                group.addTask { (i, await self.fetchSnapshot(for: d, isToday: isToday)) }
            }
            var collected = Array<HealthSnapshot?>(repeating: nil, count: dates.count)
            for await (i, s) in group { collected[i] = s }
            return collected.compactMap { $0 }
        }

        return WeeklyHealthPayload(
            extractedAt: Self.iso.string(from: Date()),
            days: days
        )
    }

    func fetchSnapshot(for date: Date, isToday: Bool = false) async -> HealthSnapshot {
        async let hr     = avgHeartRate(on: date)
        async let steps  = sum(.stepCount, unit: .count(), on: date)
        async let cals   = sum(.activeEnergyBurned, unit: .kilocalorie(), on: date)
        async let distM  = sum(.distanceWalkingRunning, unit: .meter(), on: date)
        async let sleepM = sleep(endingOn: date)
        async let work   = workouts(on: date)

        let hrVal    = await hr
        let stepsVal = await steps ?? 0
        let calsVal  = await cals ?? 0
        let distMVal = await distM ?? 0

        return HealthSnapshot(
            date: Self.isoDay.string(from: date),
            today: isToday ? true : nil,
            heart: HeartMetrics(avgBpm: hrVal),
            activity: ActivityMetrics(
                steps: Int(stepsVal.rounded()),
                activeCalories: Int(calsVal.rounded()),
                distanceKm: round((distMVal / 1000.0) * 100) / 100
            ),
            sleep: await sleepM,
            workouts: await work
        )
    }

    /// Returns unique connector names from both heart rate (Watch) and step count (Health/iPhone) sources.
    func fetchConnectedSources() async -> [String] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: weekAgo, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        async let hrNames = samplesNames(type: HKQuantityType(.heartRate), predicate: pred, sort: sort)
        async let stepNames = samplesNames(type: HKQuantityType(.stepCount), predicate: pred, sort: sort)

        return await hrNames.union(stepNames).sorted()
    }

    private func samplesNames(type: HKQuantityType, predicate: NSPredicate, sort: NSSortDescriptor) async -> Set<String> {
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100, sortDescriptors: [sort]) { _, samples, _ in
                var names = Set<String>()
                for sample in samples ?? [] {
                    names.insert(sample.sourceRevision.source.name)
                }
                cont.resume(returning: names)
            }
            store.execute(q)
        }
    }

    // MARK: - Per-day predicates

    private func dayPredicate(for date: Date) -> NSPredicate {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        // Clamp end to "now" for today so we don't query the future.
        return HKQuery.predicateForSamples(withStart: start, end: min(end, Date()))
    }

    // MARK: - Fetchers (per-day)

    private func avgHeartRate(on date: Date) async -> Int? {
        await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: dayPredicate(for: date),
                options: .discreteAverage
            ) { _, result, _ in
                let bpm = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                cont.resume(returning: bpm.map { Int($0.rounded()) })
            }
            store.execute(q)
        }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, on date: Date) async -> Double? {
        await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: dayPredicate(for: date),
                options: .cumulativeSum
            ) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Captures the sleep session that *ended* on `date` (window: noon prior-day → noon-of-date).
    private func sleep(endingOn date: Date) async -> SleepMetrics? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let start = cal.date(byAdding: .hour, value: -12, to: dayStart) ?? dayStart
        let endRaw = cal.date(byAdding: .hour, value: 12, to: dayStart) ?? date
        let end = min(endRaw, Date())
        guard end > start else { return nil }

        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let cats = samples as? [HKCategorySample], !cats.isEmpty else {
                    cont.resume(returning: nil); return
                }

                var awake = 0.0, core = 0.0, deep = 0.0, rem = 0.0
                for s in cats {
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += dur
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        core += dur
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep += dur
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem += dur
                    default:
                        break
                    }
                }

                let asleepTotal = core + deep + rem
                guard asleepTotal > 0 else { cont.resume(returning: nil); return }

                let asleepVals: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let asleepSamples = cats.filter { asleepVals.contains($0.value) }
                let bedtime = asleepSamples.first?.startDate
                let wake = asleepSamples.last?.endDate

                cont.resume(returning: SleepMetrics(
                    totalHours: round(asleepTotal / 3600 * 10) / 10,
                    stages: SleepStages(
                        awakeHours: round(awake / 3600 * 10) / 10,
                        coreHours: round(core / 3600 * 10) / 10,
                        deepHours: round(deep / 3600 * 10) / 10,
                        remHours: round(rem / 3600 * 10) / 10
                    ),
                    bedtime: bedtime.map { HealthKitService.iso.string(from: $0) },
                    wake: wake.map { HealthKitService.iso.string(from: $0) }
                ))
            }
            store.execute(q)
        }
    }

    private func workouts(on date: Date) async -> [WorkoutSummary] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: dayPredicate(for: date),
                limit: 50,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let out: [WorkoutSummary] = ((samples as? [HKWorkout]) ?? []).map { w in
                    let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    let dist = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .meter()) ?? 0
                    let hrAvg = w.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                    return WorkoutSummary(
                        uuid: w.uuid.uuidString,
                        type: Self.workoutName(w.workoutActivityType),
                        durationMin: Int((w.duration / 60).rounded()),
                        calories: Int(kcal.rounded()),
                        distanceKm: round((dist / 1000.0) * 100) / 100,
                        avgHeartRate: hrAvg.map { Int($0.rounded()) },
                        startedAt: Self.iso.string(from: w.startDate),
                        endedAt: Self.iso.string(from: w.endDate)
                    )
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: - Utilities

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .dance: return "Dance"
        case .functionalStrengthTraining: return "Strength"
        case .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .mixedCardio: return "Cardio"
        case .coreTraining: return "Core"
        case .pilates: return "Pilates"
        default: return "Workout"
        }
    }
}
