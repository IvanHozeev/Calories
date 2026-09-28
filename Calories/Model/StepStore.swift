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
    @ObservationIgnored private let history: ActivityHistory

    private(set) var stepsToday: Int = 0
    private(set) var distanceTodayKm: Double = 0
    private(set) var activeCaloriesToday: Int = 0
    private(set) var weekHistory: [ActivityDay] = []
    private(set) var monthHistory: [ActivityDay] = []
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
        self.history = ActivityHistory(defaults: defaults)
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
            HKQuantityType(.activeEnergyBurned),
            // Тренировки — ради объяснения, а не ради арифметики: их калории
            // уже сидят в активных, и складывать одно с другим нельзя.
            HKObjectType.workoutType(),
            // Сон — ради подъёма: время будильника iOS не отдаёт, а конец сна
            // отдаёт.
            HKCategoryType(.sleepAnalysis),
            // Сырой пульс — чтобы посчитать покой самим: готовую величину
            // пишут только часы Apple.
            HKQuantityType(.heartRate)
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
        fetchWorkouts(days: 90)
        fetchSleep(days: 90)
        fetchRestingPulse(days: 30)
    }

    /// Вся сохранённая активность — для экрана и для копии.
    var storedHistory: [ActivityDay] { history.days }

    /// Запоминает активные калории за сегодня: их «Здоровье» отдаёт отдельным
    /// запросом, и в истории шагов их нет.
    private func rememberActiveCaloriesToday(_ calories: Int) {
        guard calories > 0 else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let steps = history.steps(on: today) ?? stepsToday
        history.remember([ActivityDay(date: today, steps: steps, activeCalories: calories)])
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
                // Виджету кладём уже разрешённый цвет: он в своём процессе и
                // про недобранный макрос ничего не знает.
                self?.groupDefaults?.set(StepStore.widgetAccent(), forKey: "widget_accent")
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

    /// Записанные тренировки: чем человек занимался и сколько это длилось.
    ///
    /// Шаги не видят ни штангу, ни велотренажёр, ни баскетбол — день с залом
    /// выглядит в них как обычный. Калории тренировки при этом уже посчитаны в
    /// активных, поэтому прибавлять их ещё раз нельзя: отсюда тренировка идёт
    /// в историю названием и минутами, а не килокалориями.
    private func fetchWorkouts(days: Int) {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return }
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end),
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { [weak self] _, samples, _ in
            let workouts = (samples as? [HKWorkout]) ?? []
            // За день их может быть несколько: минуты складываем, а называем
            // день по самой длинной — «Баскетбол» понятнее, чем «Тренировки».
            var minutes: [Date: Int] = [:]
            var longest: [Date: (title: String, seconds: TimeInterval)] = [:]
            for workout in workouts {
                let day = calendar.startOfDay(for: workout.startDate)
                minutes[day, default: 0] += Int((workout.duration / 60).rounded())
                let title = Self.title(of: workout.workoutActivityType)
                if workout.duration > (longest[day]?.seconds ?? 0) {
                    longest[day] = (title, workout.duration)
                }
            }
            let days = minutes.map { day, total in
                ActivityDay(date: day, steps: 0, workoutMinutes: total, workoutTitle: longest[day]?.title)
            }
            guard !days.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.history.remember(days)
            }
        }
        healthStore.execute(query)
    }

    /// Какой цвет отдать виджету.
    ///
    /// «По макросу» виджет посчитать не может — макросы живут в дневнике, а не
    /// в общем контейнере, — поэтому приложение кладёт туда уже выбранный
    /// макрос. Пока дневник не пересобрался, остаётся прежнее значение.
    nonisolated static func widgetAccent(defaults: UserDefaults = .standard) -> String {
        let accent = defaults.string(forKey: AppAccent.defaultsKey).flatMap(AppAccent.init(rawValue:)) ?? .system
        guard accent == .focus else { return accent.rawValue }
        return defaults.string(forKey: "focus_macro") ?? AppAccent.kcal.rawValue
    }

    /// Записи, которые «Здоровье» считает сном, а не пребыванием в постели.
    nonisolated static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue
    ]

    /// Сон за последние дни: во сколько лёг, во сколько встал, сколько спал.
    private func fetchSleep(days: Int) {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return }
        let query = HKSampleQuery(
            sampleType: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end),
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { [weak self] _, samples, _ in
            let found = (samples as? [HKCategorySample]) ?? []
            let nights = SleepAnalysis.nights(from: SleepAnalysis.segments(
                asleep: found.filter { Self.asleepValues.contains($0.value) }
                    .map { SleepAnalysis.Segment(start: $0.startDate, end: $0.endDate) },
                inBed: found.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                    .map { SleepAnalysis.Segment(start: $0.startDate, end: $0.endDate) }))
            guard !nights.isEmpty else { return }
            let days = nights.map { night in
                ActivityDay(date: calendar.startOfDay(for: night.wake), steps: 0,
                            sleepHours: night.hours, wakeTime: night.wake, bedTime: night.bed)
            }
            Task { @MainActor [weak self] in
                self?.history.remember(days)
            }
        }
        healthStore.execute(query)
    }

    /// Пульс в покое по ночам — из часовых средних сырого пульса.
    ///
    /// Часами, а не пробами: браслет меряет пульс постоянно, и за месяц это
    /// десятки тысяч записей. Часовые средние HealthKit считает у себя, отдаёт
    /// семь сотен чисел, и дно ночи по ним видно не хуже.
    private func fetchRestingPulse(days: Int) {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return }
        var interval = DateComponents()
        interval.hour = 1
        let query = HKStatisticsCollectionQuery(
            quantityType: HKQuantityType(.heartRate),
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
            options: .discreteAverage,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: interval
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        query.initialResultsHandler = { [weak self] _, results, _ in
            var hours: [RestingPulse.Hour] = []
            results?.enumerateStatistics(from: start, to: end) { stats, _ in
                guard let average = stats.averageQuantity()?.doubleValue(for: unit) else { return }
                hours.append(RestingPulse.Hour(start: stats.startDate, average: average))
            }
            guard !hours.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Окно сна, если оно известно: тогда считаем дно именно по нему,
                // а не по формальной полуночи — люди ложатся по-разному.
                var windows: [Date: (bed: Date, wake: Date)] = [:]
                for day in self.history.days {
                    if let bed = day.bedTime, let wake = day.wakeTime {
                        windows[calendar.startOfDay(for: day.date)] = (bed, wake)
                    }
                }
                let byDay = RestingPulse.daily(from: hours, sleep: windows, calendar: calendar)
                guard !byDay.isEmpty else { return }
                self.history.remember(byDay.map {
                    ActivityDay(date: $0.key, steps: 0, restingPulse: $0.value)
                })
            }
        }
        healthStore.execute(query)
    }

    /// Во сколько человек встал в этот день, если «Здоровье» это знает.
    func wakeTime(on date: Date) -> Date? {
        let calendar = Calendar.current
        return history.days.first { calendar.isDate($0.date, inSameDayAs: date) }?.wakeTime
    }

    /// Сколько спал перед этим днём и насколько это меньше обычного.
    func sleep(on date: Date) -> (hours: Double, shortfall: Double)? {
        let calendar = Calendar.current
        guard let hours = history.days.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.sleepHours
        else { return nil }
        let usual = history.usualSleepHours() ?? hours
        return (hours, SleepAnalysis.shortfall(hours: hours, usual: usual))
    }

    /// Человеческое название вида тренировки.
    ///
    /// Разбираем только то, чем занимаются с браслетом; остальное — общее
    /// «Тренировка», потому что «HKWorkoutActivityType(rawValue: 63)» в
    /// интерфейсе не объяснение, а отговорка.
    nonisolated static func title(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                    return String(localized: "Бег")
        case .walking, .hiking:           return String(localized: "Ходьба")
        case .cycling:                    return String(localized: "Велосипед")
        case .swimming:                   return String(localized: "Плавание")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
                                          return String(localized: "Силовая")
        case .basketball:                 return String(localized: "Баскетбол")
        case .soccer:                     return String(localized: "Футбол")
        case .tennis:                     return String(localized: "Теннис")
        case .yoga:                       return String(localized: "Йога")
        case .highIntensityIntervalTraining:
                                          return String(localized: "Интервальная")
        case .elliptical, .rowing, .stairClimbing:
                                          return String(localized: "Кардио")
        default:                          return String(localized: "Тренировка")
        }
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
            var days: [ActivityDay] = []
            results?.enumerateStatistics(from: start, to: end) { stats, _ in
                let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                days.append(ActivityDay(date: stats.startDate, steps: steps))
            }
            let finalDays = days
            Task { @MainActor [weak self] in
                self?.monthHistory = Array(finalDays.suffix(30))
                self?.weekHistory = Array(finalDays.suffix(7))
                self?.updateDerivedStats()
                self?.updateGoalStreak()
                self?.history.rememberSteps(finalDays, source: self?.preferredSourceID)
            }
        }
        healthStore.execute(query)
    }
}
