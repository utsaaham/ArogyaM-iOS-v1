import SwiftUI
import HealthKit

struct ContentView: View {
    let healthStore = HKHealthStore()
    @State private var heartRate: Double = 0
    @State private var steps: Double = 0
    @State private var calories: Double = 0
    @State private var distance: Double = 0
    @State private var sleepHours: Double = 0
    @State private var workouts: [HKWorkout] = []
    @State private var sendStatus: String = ""

    var todayPredicate: NSPredicate {
        HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date())
    }

    var body: some View {
        NavigationView {
            List {
                Section("Today's Stats") {
                    Text("❤️ Heart Rate: \(Int(heartRate)) BPM")
                    Text("👟 Steps: \(Int(steps))")
                    Text("🔥 Calories: \(Int(calories)) kcal")
                    Text("📏 Distance: \(String(format: "%.2f", distance)) km")
                    Text("😴 Sleep: \(String(format: "%.1f", sleepHours)) hrs")
                }

                Section("Today's Workouts") {
                    if workouts.isEmpty {
                        Text("No workouts today").foregroundColor(.gray)
                    } else {
                        ForEach(workouts, id: \.uuid) { workout in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workoutName(workout.workoutActivityType)).font(.headline)
                                HStack {
                                    Text("🕐 \(Int(workout.duration / 60)) min")
                                    Spacer()
                                    Text("🔥 \(Int(workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)) kcal")
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !sendStatus.isEmpty {
                    Section {
                        Text(sendStatus)
                    }
                }
            }
            .navigationTitle("Today's Health")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") { requestPermissionsAndSend() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") { sendToAPI() }
                        .bold()
                }
            }
        }
        .onAppear { requestPermissionsAndSend() }
    }

    // MARK: - Send JSON to server
    func sendToAPI() {
        let payload: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "heartRate": Int(heartRate),
            "steps": Int(steps),
            "calories": Int(calories),
            "distanceKm": round(distance * 100) / 100,
            "sleepHours": round(sleepHours * 10) / 10,
            "workouts": workouts.map { w in
                [
                    "type": workoutName(w.workoutActivityType),
                    "durationMin": Int(w.duration / 60),
                    "calories": Int(w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                ] as [String: Any]
            }
        ]

        guard let url = URL(string: Config.serverURL),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        sendStatus = "Sending..."

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    let code = (error as NSError).code
                    switch code {
                    case -1009: sendStatus = "❌ No network / local network blocked (code -1009)"
                    case -1004: sendStatus = "❌ Cannot connect to server — is node server.js running? (code -1004)"
                    case -1003: sendStatus = "❌ Server not found — check IP in Config.swift (code -1003)"
                    case -1001: sendStatus = "❌ Request timed out (code -1001)"
                    default:    sendStatus = "❌ Error \(code): \(error.localizedDescription)"
                    }
                    return
                }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        sendStatus = "✅ Sent!"
                    } else if http.statusCode == 401 {
                        sendStatus = "❌ Unauthorised (401) — bearer token mismatch"
                    } else {
                        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
                        sendStatus = "❌ HTTP \(http.statusCode): \(body)"
                    }
                }
            }
        }.resume()
    }

    // MARK: - Permissions
    func requestPermissionsAndSend() {
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, _ in
            if success {
                fetchHeartRate(); fetchSteps(); fetchCalories()
                fetchDistance(); fetchSleep(); fetchWorkouts()
                // Allow HealthKit queries time to complete before sending
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    sendToAPI()
                }
            }
        }
    }

    // MARK: - Fetch
    func fetchHeartRate() {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: todayPredicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                DispatchQueue.main.async { self.heartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min")) }
            }
        }
        healthStore.execute(query)
    }

    func fetchSteps() {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: todayPredicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { self.steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0 }
        }
        healthStore.execute(query)
    }

    func fetchCalories() {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: todayPredicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { self.calories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0 }
        }
        healthStore.execute(query)
    }

    func fetchDistance() {
        let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: todayPredicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { self.distance = (result?.sumQuantity()?.doubleValue(for: .meter()) ?? 0) / 1000.0 }
        }
        healthStore.execute(query)
    }

    func fetchSleep() {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: todayPredicate, limit: 10, sortDescriptors: [sort]) { _, samples, _ in
            let total = samples?.compactMap { $0 as? HKCategorySample }
                .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
            DispatchQueue.main.async { self.sleepHours = total / 3600.0 }
        }
        healthStore.execute(query)
    }

    func fetchWorkouts() {
        let type = HKObjectType.workoutType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: todayPredicate, limit: 20, sortDescriptors: [sort]) { _, samples, _ in
            DispatchQueue.main.async { self.workouts = (samples as? [HKWorkout]) ?? [] }
        }
        healthStore.execute(query)
    }

    func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .dance: return "Dance"
        case .functionalStrengthTraining: return "Strength"
        default: return "Workout"
        }
    }
}
