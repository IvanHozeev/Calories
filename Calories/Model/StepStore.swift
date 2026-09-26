@preconcurrency import HealthKit
import Foundation
import Observation
import WidgetKit

/// Откуда «Здоровье» берёт шаги: сам айфон, браслет, часы, стороннее приложение.
struct StepSource: Identifiable, Hashable, Sendable {
    /// Идентификатор приложения-источника — он же устойчивое имя в настройках.
    let id: String
    let name: String
}

@Observable
@MainActor
final class StepStore {
    @ObservationIgnored private let healthStore = HKHealthStore()
    /// См. комментарий в CalorieStore: тесты живут в процессе приложения, `.standard` там боевой.
    @ObservationIgnored private let defaults: UserDefaults
    /// Общий с виджетом контейнер. Тесты передают nil, чтобы не переписывать боевые данные виджета.
    @ObservationIgnored private let groupDefaults: UserDefaults?
    /// Куда складывается прочитанное из «Здоровья», чтобы оно пережило запуск
    /// и попало в резервную копию.
    @ObservationIgnored private let history: StepHistory

    private(set) var stepsToday: Int = 0
    private(set) var distanceTodayKm: Double = 0
    private(set) var activeCaloriesToday: Int = 0
    private(set) var weekHistory: [StepDay] = []
    private(set) var monthHistory: [StepDay] = []
    private(set) var isAuthorized: Bool = false
    private(set) var goalStreak: Int = 0
    private(set) var weeklyTotal: Int = 0
    private(set) var prevWeekAverage: Int = 0
    /// Источники шагов, которые есть в «Здоровье» у этого человека.
    private(set) var sources: [StepSource] = []

    /// Выбранный источник. nil — считать всё подряд, как было раньше.
    ///
    /// Выбор нужен потому, что HealthKit, в отличие от приложения «Здоровье»,
    /// источники не разводит: запрос суммы складывает и шаги айфона, и шаги
    /// браслета за один и тот же день. У человека с браслетом в кармане и
    /// телефоном там же день получался в полтора раза длиннее, чем был.
    /// «Здоровье» такое схлопывает по приоритету источников, а нам этот
    /// приоритет не отдают — значит, спрашиваем сами.
    var preferredSourceID: String? {
        didSet {
            guard preferredSourceID != oldValue else { return }
            defaults.set(preferredSourceID, forKey: Self.sourceKey)
            fetchAll()
        }
    }

    static let sourceKey = "step_source"

    /// Источники, попавшие в выборку, в «здоровьевом» виде — для предикатов.
    @ObservationIgnored private var healthSources: [HKSource] = []

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
        self.history = StepHistory(defaults: defaults)
        self.preferredSourceID = defaults.string(forKey: Self.sourceKey)
        let goal = defaults.object(forKey: "step_goal") as? Int ?? 10_000
        self.stepGoal = goal
        groupDefaults?.set(goal, forKey: "widget_step_goal")
        // Доступ к «Здоровью» спрашивает онбординг, отдельным шагом с объяснением.
        // Раньше системное окно выскакивало при самом первом запуске, поверх
        // приветствия, — без единого слова, зачем приложению шаги. После
        // онбординга запрос повторяется на каждом запуске: окна он больше не
        // показывает, а только поднимает чтение, если доступ дали. Кроме случая,
        // когда в онбординге ответили «не сейчас», — тогда ждём, пока человек
        // сам откроет шаги.
        // Показывать есть что ещё до ответа «Здоровья»: сохранённая история
        // не зависит ни от доступа, ни от сети. Свежие цифры её потом
        // перекроют, а пустой экран в ожидании запроса никому не нужен.
        let stored = history.days
        if !stored.isEmpty {
            monthHistory = Array(stored.suffix(30))
            weekHistory = Array(stored.suffix(7))
            stepsToday = stored.last.flatMap {
                Calendar.current.isDateInToday($0.date) ? $0.steps : nil
            } ?? 0
            updateDerivedStats()
            updateGoalStreak()
        }
        if defaults.bool(forKey: "onboarding_completed"), !defaults.bool(forKey: Self.deferredKey) {
            requestAuthorization()
        }
    }

    static let deferredKey = "health_access_deferred"

    /// Ответ «не сейчас» в онбординге: без спроса окно доступа больше не всплывает.
    func deferAuthorization() {
        defaults.set(true, forKey: Self.deferredKey)
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        defaults.set(false, forKey: Self.deferredKey)
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
        fetchSources()
        fetchStepsToday()
        fetchDistanceToday()
        fetchActiveCaloriesToday()
        // Читаем заметно больше, чем показываем. Данные с браслета доезжают в
        // «Здоровье» с опозданием и задним числом: спросив только последний
        // месяц, мы бы так и не увидели дни, которые синхронизировались уже
        // после того, как их прочитали нулями.
        fetchHistory(days: 90)
    }

    /// Вся сохранённая активность — для экрана и для копии.
    var storedHistory: [StepDay] { history.days }

    /// Запоминает активные калории за сегодня: их «Здоровье» отдаёт отдельным
    /// запросом, и в истории шагов их нет.
    private func rememberActiveCaloriesToday(_ calories: Int) {
        guard calories > 0 else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let steps = history.steps(on: today) ?? stepsToday
        history.remember([StepDay(date: today, steps: steps, activeCalories: calories)])
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

    /// Отбор проб за отрезок — с оглядкой на выбранный источник.
    private func samplePredicate(from start: Date, to end: Date) -> NSPredicate {
        let period = HKQuery.predicateForSamples(withStart: start, end: end)
        guard let preferredSourceID,
              let source = healthSources.first(where: { $0.bundleIdentifier == preferredSourceID })
        else { return period }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            period, HKQuery.predicateForObjects(from: [source])
        ])
    }

    /// Спрашивает «Здоровье», кто вообще пишет сюда шаги.
    private func fetchSources() {
        let query = HKSourceQuery(sampleType: HKQuantityType(.stepCount),
                                  samplePredicate: nil) { [weak self] _, found, _ in
            let sources = (found ?? []).sorted { $0.name < $1.name }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.healthSources = sources
                self.sources = sources.map { StepSource(id: $0.bundleIdentifier, name: $0.name) }
                // Источник мог пропасть — переставили телефон, снесли
                // приложение браслета. Молча считать после этого ноль нельзя:
                // возвращаемся к «всем источникам».
                if let id = self.preferredSourceID, !sources.contains(where: { $0.bundleIdentifier == id }) {
                    self.preferredSourceID = nil
                }
            }
        }
        healthStore.execute(query)
    }

    private func fetchStepsToday() {
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = samplePredicate(from: start, to: Date())
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
                self?.groupDefaults?.set(Calendar.current.startOfDay(for: Date()), forKey: "widget_steps_day")
                self?.groupDefaults?.set(steps, forKey: "widget_steps_today")
                // Цвет акцента виджету: он в своём процессе и настроек не видит.
                self?.groupDefaults?.set(AppAccent.current.rawValue, forKey: "widget_accent")
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
        let predicate = samplePredicate(from: start, to: Date())
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let kcal = Int(result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            Task { @MainActor [weak self] in
                self?.activeCaloriesToday = kcal
                self?.rememberActiveCaloriesToday(kcal)
            }
        }
        healthStore.execute(query)
    }

    private func fetchDistanceToday() {
        let type = HKQuantityType(.distanceWalkingRunning)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = samplePredicate(from: start, to: Date())
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
            quantitySamplePredicate: samplePredicate(from: start, to: end),
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
                self?.monthHistory = Array(finalDays.suffix(30))
                self?.weekHistory = Array(finalDays.suffix(7))
                self?.updateDerivedStats()
                self?.updateGoalStreak()
                self?.history.remember(finalDays)
            }
        }
        healthStore.execute(query)
    }
}
