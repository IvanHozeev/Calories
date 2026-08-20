@preconcurrency import HealthKit
import Foundation
import Combine

struct StepDay: Identifiable {
    let date: Date
    let steps: Int
    var id: Date { date }
}

@MainActor
final class StepStore: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published private(set) var stepsToday: Int = 0
    @Published private(set) var distanceTodayKm: Double = 0
    @Published private(set) var weekHistory: [StepDay] = []
    @Published private(set) var monthHistory: [StepDay] = []
    @Published private(set) var isAuthorized: Bool = false

    @Published var stepGoal: Int {
        didSet {
            UserDefaults.standard.set(stepGoal, forKey: "step_goal")
            UserDefaults(suiteName: "group.calories.shared")?.set(stepGoal, forKey: "widget_step_goal")
        }
    }

    init() {
        let goal = UserDefaults.standard.object(forKey: "step_goal") as? Int ?? 10_000
        self.stepGoal = goal
        UserDefaults(suiteName: "group.calories.shared")?.set(goal, forKey: "widget_step_goal")
        requestAuthorization()
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning)
        ]
        healthStore.requestAuthorization(toShare: nil, read: types) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                self?.isAuthorized = success
                if success { self?.fetchAll() }
            }
        }
    }

    func fetchAll() {
        fetchStepsToday()
        fetchDistanceToday()
        fetchHistory(days: 30)
    }

    private func fetchStepsToday() {
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            Task { @MainActor [weak self] in
                self?.stepsToday = steps
                UserDefaults(suiteName: "group.calories.shared")?.set(steps, forKey: "widget_steps_today")
            }
        }
        healthStore.execute(query)
    }

    private func fetchDistanceToday() {
        let type = HKQuantityType(.distanceWalkingRunning)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let km = (result?.sumQuantity()?.doubleValue(for: .meter()) ?? 0) / 1000
            Task { @MainActor [weak self] in
                self?.distanceTodayKm = km
                UserDefaults(suiteName: "group.calories.shared")?.set(km, forKey: "widget_distance_km")
            }
        }
        healthStore.execute(query)
    }

    private func fetchHistory(days: Int) {
        let type = HKQuantityType(.stepCount)
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return }
        var interval = DateComponents()
        interval.day = 1
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: interval
        )
        query.initialResultsHandler = { [weak self] _, results, _ in
            var days: [StepDay] = []
            results?.enumerateStatistics(from: start, to: end) { stats, _ in
                let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                days.append(StepDay(date: stats.startDate, steps: steps))
            }
            let finalDays = days
            Task { @MainActor [weak self] in
                self?.monthHistory = finalDays
                self?.weekHistory = Array(finalDays.suffix(7))
            }
        }
        healthStore.execute(query)
    }
}
