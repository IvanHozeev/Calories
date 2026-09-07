@preconcurrency import HealthKit
import Foundation
import Observation
import WidgetKit

struct StepDay: Identifiable {
    let date: Date
    let steps: Int
    var id: Date { date }
}

@Observable
@MainActor
final class StepStore {
    @ObservationIgnored private let healthStore = HKHealthStore()
    /// См. комментарий в CalorieStore: тесты живут в процессе приложения, `.standard` там боевой.
    @ObservationIgnored private let defaults: UserDefaults
    /// Общий с виджетом контейнер. Тесты передают nil, чтобы не переписывать боевые данные виджета.
    @ObservationIgnored private let groupDefaults: UserDefaults?

    private(set) var stepsToday: Int = 0
    private(set) var distanceTodayKm: Double = 0
    private(set) var activeCaloriesToday: Int = 0
    private(set) var weekHistory: [StepDay] = []
    private(set) var monthHistory: [StepDay] = []
    private(set) var isAuthorized: Bool = false
    private(set) var goalStreak: Int = 0
    private(set) var weeklyTotal: Int = 0
    private(set) var prevWeekAverage: Int = 0

    /// Что и когда мы в последний раз отдали виджету. Нужно, чтобы не дёргать
    /// его на каждое обновление HealthKit: у виджетов системный бюджет
    /// перестроений, и, потратив его на переход с 6540 шагов на 6547,
    /// приложение получает троттлинг — виджет начинает обновляться реже, чем
    /// нужно. То есть мы платим батареей за то, чтобы он работал хуже.
    @ObservationIgnored private var lastPushedSteps = 0
    @ObservationIgnored private var lastPushedGoalReached = false
    @ObservationIgnored private var lastPushedAt = Date.distantPast
    @ObservationIgnored private var lastPushedDay = Date.distantPast

    var stepGoal: Int {
        didSet {
            defaults.set(stepGoal, forKey: "step_goal")
            groupDefaults?.set(stepGoal, forKey: "widget_step_goal")
        }
    }

    init(
        defaults: UserDefaults = .standard,
        groupDefaults: UserDefaults? = UserDefaults(suiteName: CalorieStore.appGroup)
    ) {
        self.defaults = defaults
        self.groupDefaults = groupDefaults
        let goal = defaults.object(forKey: "step_goal") as? Int ?? 10_000
        self.stepGoal = goal
        groupDefaults?.set(goal, forKey: "widget_step_goal")
        requestAuthorization()
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
        ]
        healthStore.requestAuthorization(toShare: nil, read: types) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                self?.isAuthorized = success
                if success {
                    self?.fetchAll()
                    self?.setupObserver()
                }
            }
        }
    }

    private func setupObserver() {
        let type = HKQuantityType(.stepCount)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                self?.fetchStepsToday()
                self?.fetchDistanceToday()
            }
        }
        healthStore.execute(query)
        // Часовая, а не `.immediate`. Шагам секундная точность не нужна, и для
        // накопительных типов система всё равно режет частоту до часа — просить
        // большего значит заявлять намерение, которого у нас нет.
        healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }

    func fetchAll() {
        fetchStepsToday()
        fetchDistanceToday()
        fetchActiveCaloriesToday()
        fetchHistory(days: 30)
    }

    private func updateDerivedStats() {
        weeklyTotal = weekHistory.reduce(0) { $0 + $1.steps }
        let month = monthHistory
        guard month.count >= 14 else { prevWeekAverage = 0; return }
        let prevWeek = Array(month.dropLast(7).suffix(7))
        let nonZero = prevWeek.filter { $0.steps > 0 }
        prevWeekAverage = nonZero.isEmpty ? 0 : nonZero.reduce(0) { $0 + $1.steps } / nonZero.count
    }

    private func updateGoalStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sorted = monthHistory.sorted { $0.date > $1.date }
        var streak = 0
        var expected = today
        for day in sorted {
            let dayStart = calendar.startOfDay(for: day.date)
            guard dayStart == expected else { break }
            let steps = dayStart == today ? stepsToday : day.steps
            if steps >= stepGoal {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else {
                break
            }
        }
        goalStreak = streak
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
                self?.updateGoalStreak()
                // Число отдаём всегда — запись в общий контейнер ничего не стоит,
                // и когда система обновит виджет сама, она возьмёт свежее.
                // Дорого стоит только просьба перестроиться, её и экономим.
                self?.groupDefaults?.set(steps, forKey: "widget_steps_today")
                self?.refreshStepsWidgetIfWorthIt(steps: steps)
            }
        }
        healthStore.execute(query)
    }

    /// Стоит ли просить виджет перестроиться.
    ///
    /// Вынесено отдельной функцией без побочных эффектов, потому что вся суть
    /// здесь — в том, «когда именно», а проверить это иначе нечем.
    ///
    /// Достигнутая цель показывается сразу: ради неё на виджет и смотрят.
    /// В остальном ждём и заметного изменения, и паузы — сотня шагов это
    /// примерно минута ходьбы, и обновлять экран блокировки каждую минуту
    /// незачем.
    nonisolated static func shouldRefreshWidget(
        steps: Int,
        goal: Int,
        lastSteps: Int,
        lastGoalReached: Bool,
        lastPushedAt: Date,
        lastPushedDay: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        // Новый день — на виджете обязан появиться ноль, иначе он до первой
        // сотни шагов будет показывать вчерашний итог.
        if !calendar.isDate(lastPushedDay, inSameDayAs: now) { return true }
        if (steps >= goal) != lastGoalReached { return true }
        let movedEnough = abs(steps - lastSteps) >= 100
        let waitedEnough = now.timeIntervalSince(lastPushedAt) >= 600
        return movedEnough && waitedEnough
    }

    private func refreshStepsWidgetIfWorthIt(steps: Int) {
        let now = Date()
        guard Self.shouldRefreshWidget(
            steps: steps,
            goal: stepGoal,
            lastSteps: lastPushedSteps,
            lastGoalReached: lastPushedGoalReached,
            lastPushedAt: lastPushedAt,
            lastPushedDay: lastPushedDay,
            now: now
        ) else { return }
        lastPushedSteps = steps
        lastPushedGoalReached = steps >= stepGoal
        lastPushedAt = now
        lastPushedDay = now
        WidgetCenter.shared.reloadTimelines(ofKind: "StepsWidget")
    }

    private func fetchActiveCaloriesToday() {
        let type = HKQuantityType(.activeEnergyBurned)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let kcal = Int(result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            Task { @MainActor [weak self] in
                self?.activeCaloriesToday = kcal
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
                self?.groupDefaults?.set(km, forKey: "widget_distance_km")
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
                self?.updateDerivedStats()
                self?.updateGoalStreak()
            }
        }
        healthStore.execute(query)
    }
}
