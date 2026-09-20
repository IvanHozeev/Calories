import Foundation
import SwiftData
import Observation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "CalorieStore")

@Observable
@MainActor
final class CalorieStore {
    private let context: ModelContext
    /// Хранилище настроек. Инжектится, чтобы тесты не трогали боевые UserDefaults приложения:
    /// юнит-тесты запускаются внутри процесса Calories.app, и `.standard` там — реальные данные пользователя.
    @ObservationIgnored private let defaults: UserDefaults
    /// Общий с виджетом контейнер. Тесты передают nil, чтобы не переписывать боевые данные виджета.
    @ObservationIgnored private let groupDefaults: UserDefaults?

    private(set) var entries: [FoodEntry] = []
    private(set) var customFoods: [FoodItem] = []
    private(set) var dishes: [Dish] = []
    private(set) var weightEntries: [WeightEntry] = []
    private(set) var goalRecords: [GoalRecord] = []
    private(set) var measurements: [BodyMeasurement] = []
    private(set) var fastDays: [FastDay] = []
    var dailyGoal: Int {
        // Кэш обязателен: adaptedTodayGoal (его читает кольцо на «Сегодня») считается только
        // в rebuildCaches(). Без этого цель меняется в графиках, но не в кольце — они расходятся,
        // пока что-нибудь другое не дёрнет пересчёт.
        didSet {
            defaults.set(dailyGoal, forKey: Keys.goal)
            stampDailyGoalPhase()
            rebuildCaches()
        }
    }
    /// Под какой кусок плана (фазу или брейк) записана `dailyGoal`.
    ///
    /// Норма без цикла хранится числом, и раньше она не замечала смены фазы:
    /// сушка кончалась, начиналось поддержание, а кольцо до первой правки
    /// профиля показывало дефицит. Теперь число действует только в той фазе,
    /// под которую его записали, — дальше норма идёт по формуле плана. Числом,
    /// а не формулой, его держат ради «замедлить»: та пишет сюда пересчитанное.
    private(set) var dailyGoalPhaseID: UUID?

    private func stampDailyGoalPhase() {
        dailyGoalPhaseID = plan?.phase(on: Date())?.id
        defaults.set(dailyGoalPhaseID?.uuidString, forKey: Keys.goalPhase)
    }
    private(set) var profile: UserProfile?
    private(set) var plan: Plan?
    /// Премиум куплен. Сам по себе не значит доступа: его даёт ещё и пробный период.
    private(set) var hasPurchasedPremium: Bool {
        didSet { defaults.set(hasPurchasedPremium, forKey: Keys.premium) }
    }

    /// Когда начался пробный период плана. Начинается один раз — при первом плане
    /// из онбординга — и заново не выдаётся, даже если план завершить и начать снова.
    private(set) var trialStartedAt: Date?

    /// Две недели, а не одна: первый вердикт «как идёт план» появляется примерно
    /// через две недели взвешиваний. Неделя кончалась бы раньше, чем человек
    /// увидит, за что платит.
    static let trialDays = 14

    var trialEndsAt: Date? {
        trialStartedAt.flatMap { Calendar.current.date(byAdding: .day, value: Self.trialDays, to: $0) }
    }

    var isTrialActive: Bool {
        guard let end = trialEndsAt else { return false }
        return Date() < end
    }

    /// Сколько полных дней пробного периода осталось. nil — его нет или он кончился.
    var trialDaysLeft: Int? {
        guard isTrialActive, let end = trialEndsAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: end)).day ?? 0
        return max(days, 0)
    }

    /// Доступ к платному: куплено или идёт пробный период. Запись меняет только покупку.
    var isPremium: Bool {
        get { hasPurchasedPremium || isTrialActive }
        set { hasPurchasedPremium = newValue }
    }

    /// Пробный период был и кончился, а покупки нет — пэйвол говорит об этом прямо.
    var trialEnded: Bool {
        trialStartedAt != nil && !isTrialActive && !hasPurchasedPremium
    }

    /// Что человек успел за пробный период: дни с записями и сдвиг веса по тренду.
    var trialSummary: (loggedDays: Int, weightChangeKg: Double?)? {
        guard let start = trialStartedAt, let end = trialEndsAt else { return nil }
        let from = Calendar.current.startOfDay(for: start)
        let days = entriesByDay.keys.filter { $0 >= from && $0 < end }.count
        var change: Double?
        if let plan, let trend = weightKg { change = trend - plan.startWeightKg }
        return (days, change)
    }

    func startTrialIfNeeded(now: Date = Date()) {
        guard trialStartedAt == nil else { return }
        trialStartedAt = now
        defaults.set(now, forKey: Keys.trialStarted)
    }

    // Кэшированные производные — перестраиваются в rebuildCaches() после каждого изменения данных
    private(set) var todayEntries: [FoodEntry] = []
    private(set) var consumedToday: Int = 0
    private(set) var macrosToday: Macros = .zero
    private(set) var days: [DaySummary] = []
    private(set) var lastSevenDays: [DaySummary] = []
    private(set) var historyDays: [DaySummary] = []
    private(set) var hasWeighedToday: Bool = false
    private(set) var adherence: PlanAdherence?
    /// Что было до сегодня: законченные сушки, наборы и поддержания.
    /// Без этой памяти нельзя ответить, когда снова можно сушиться.
    private(set) var phaseHistory: [PhaseRecord] = []
    /// Расход по факту за последние две недели — что говорят дневник и весы.
    private(set) var adaptiveTDEE: AdaptiveTDEE.Result?
    /// Он же, сглаженный между днями: цель не должна прыгать за каждым всплеском.
    private(set) var smoothedTDEE: Double?
    /// Считать ли норму от факта, а не от формулы. Включено, пока человек
    /// не выключил: формула ошибается на сотни калорий, и дефицит, в котором
    /// сидят, думая, что едят вдоволь, — цена этой ошибки.
    var usesAdaptiveTDEE: Bool {
        didSet {
            defaults.set(usesAdaptiveTDEE, forKey: Keys.usesAdaptiveTDEE)
            // Забыть, от какого расхода считали: переключение должно
            // пересчитать норму сразу, а не ждать завтрашнего дня.
            defaults.removeObject(forKey: Keys.goalSyncedTDEE)
            rebuildCaches()
        }
    }

    /// Расход, от которого считается норма: факт, если он есть и включён,
    /// иначе формула по профилю.
    var workingTDEE: Double {
        if usesAdaptiveTDEE, let smoothedTDEE { return smoothedTDEE }
        return profile?.tdee ?? Double(dailyGoal)
    }
    private(set) var streak: Int = 0
    private(set) var bestStreak: Int = 0
    private(set) var loggingStreak: Int = 0
    private(set) var proteinStreak: Int = 0
    private(set) var streakHistory: [(date: Date, hasEntries: Bool, onGoal: Bool)] = []
    private(set) var groupedTodayEntries: [(period: MealPeriod, entries: [FoodEntry])] = []
    /// Недавнее — съеденное и заведённое вперемешку, по давности.
    private(set) var recentFoods: [FoodItem] = []
    private(set) var recentDishes: [Dish] = []
    /// Свои продукты, которым каталог может дать витамины, а они ещё не взяты.
    ///
    /// Считается здесь, а не в строке списка: поиск по каталогу на каждую
    /// перерисовку — тот же капкан, что уже подтормаживал ввод в поиске.
    /// Своих продуктов немного, поэтому раз на изменение данных это дёшево.
    @ObservationIgnored private(set) var foodsOfferedVitamins: Set<UUID> = []
    private(set) var adaptedTodayGoal: Int = 0
    private(set) var calorieBankBonus: Int = 0

    // O(1) словари для быстрого поиска
    @ObservationIgnored private(set) var entriesByDay: [Date: [FoodEntry]] = [:]
    /// Категория по имени продукта. Строится один раз на обновление, потому что
    /// раньше каждая строка дневника при каждой перерисовке линейно прочёсывала
    /// и свои продукты, и встроенную базу — на каждое слово в названии приёма пищи.
    @ObservationIgnored private(set) var categoryByFoodName: [String: FoodCategory] = [:]
    /// Состав на 100 г по названию продукта или блюда. Записи дневника его не
    /// хранят — только калории и макросы, — поэтому за витаминами приходится
    /// возвращаться к тому, из чего запись сделана.
    @ObservationIgnored private(set) var nutrientProfilesByName: [String: NutrientProfile] = [:]
    /// Дни голодания множеством — их проверяют в каждом дне серии и банка.
    @ObservationIgnored private(set) var fastDates: Set<Date> = []
    @ObservationIgnored private(set) var goalsByDay: [Date: Int] = [:]
    // Кэш: день, на который уже залочены все прошлые цели — повторный вызов внутри дня бесплатен
    @ObservationIgnored private var goalLockedOnDay: Date? = nil
    /// Сутки, на которые собраны кэши. Всё «сегодняшнее» — consumedToday, groupedTodayEntries,
    /// streak — считается один раз в rebuildCaches(), поэтому после полуночи данные устаревают
    /// молча: приложение продолжает показывать вчерашний день, пока что-нибудь не дёрнет пересчёт.
    @ObservationIgnored private var cachesBuiltForDay: Date = Calendar.current.startOfDay(for: Date())

    nonisolated static let appGroup = "group.calories.shared"

    private enum Keys {
        static let goal = "daily_goal"
        static let adaptiveTDEE = "adaptive_tdee"
        static let adaptiveTDEEDay = "adaptive_tdee_day"
        static let usesAdaptiveTDEE = "use_adaptive_tdee"
        static let goalSyncedTDEE = "goal_synced_tdee"
        static let phaseHistory = "phase_history"
        static let goalPhase = "daily_goal_phase"
        static let profile = "user_profile"
        static let plan = "active_plan"
        static let premium = "is_premium"
        static let trialStarted = "plan_trial_started"
    }

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        groupDefaults: UserDefaults? = UserDefaults(suiteName: CalorieStore.appGroup)
    ) {
        self.context = context
        self.defaults = defaults
        self.groupDefaults = groupDefaults
        self.dailyGoal = defaults.object(forKey: Keys.goal) as? Int ?? 2000
        self.usesAdaptiveTDEE = defaults.object(forKey: Keys.usesAdaptiveTDEE) as? Bool ?? true
        self.phaseHistory = (defaults.data(forKey: Keys.phaseHistory))
            .flatMap { try? JSONDecoder().decode([PhaseRecord].self, from: $0) } ?? []
        self.profile = Self.loadProfile(from: defaults)
        let loadedPlan = Self.loadPlan(from: defaults)
        self.plan = loadedPlan
        // Норма, записанная до появления отметки, — норма идущей фазы: другой
        // у человека до сих пор и не было.
        if let stored = defaults.string(forKey: Keys.goalPhase).flatMap(UUID.init(uuidString:)) {
            self.dailyGoalPhaseID = stored
        } else {
            self.dailyGoalPhaseID = loadedPlan?.phase(on: Date())?.id
        }
        self.hasPurchasedPremium = defaults.bool(forKey: Keys.premium)
        self.trialStartedAt = defaults.object(forKey: Keys.trialStarted) as? Date
        refresh()
        lockPastGoals()
    }

    private static func loadProfile(from defaults: UserDefaults) -> UserProfile? {
        guard let data = defaults.data(forKey: Keys.profile) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private static func loadPlan(from defaults: UserDefaults) -> Plan? {
        guard let data = defaults.data(forKey: Keys.plan) else { return nil }
        return try? JSONDecoder().decode(Plan.self, from: data)
    }

    /// Перечитывает все данные из базы и перестраивает кэш.
    func refresh() {
        let entryDescriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        entries = (try? context.fetch(entryDescriptor)) ?? []

        let foodDescriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        customFoods = (try? context.fetch(foodDescriptor)) ?? []

        let measurementDescriptor = FetchDescriptor<BodyMeasurement>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        measurements = (try? context.fetch(measurementDescriptor)) ?? []

        let fastDescriptor = FetchDescriptor<FastDay>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fastDays = (try? context.fetch(fastDescriptor)) ?? []

#if DEBUG
        // Данные симулятора переживают прогоны UI-тестов, поэтому ввод дописывался
        // к прежнему: «40» превращалось в «4040». Чистить поля клавишами нельзя —
        // typeText с клавишей удаления в этом окружении не срабатывает.
        // Только для тестов и только в отладочной сборке.
        if UserDefaults.standard.bool(forKey: "ui_test_reset_measurements") {
            for measurement in measurements { context.delete(measurement) }
            do { try context.save() } catch { logger.error("context.save failed: \(error)") }
            measurements = []
        }
#endif

        let dishDescriptor = FetchDescriptor<Dish>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        dishes = (try? context.fetch(dishDescriptor)) ?? []

        let weightDescriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        weightEntries = (try? context.fetch(weightDescriptor)) ?? []

        let goalDescriptor = FetchDescriptor<GoalRecord>(sortBy: [SortDescriptor(\.date, order: .forward)])
        goalRecords = (try? context.fetch(goalDescriptor)) ?? []

        rebuildCaches()
    }

    /// Подтянуть норму плана к расходу, от которого её считают.
    ///
    /// План пересчитывает дневную норму от расхода, но записанное число живёт
    /// в фазе и само не меняется. Пока расход брали из формулы, это было верно:
    /// формула не двигается. Факт двигается — и норма должна идти за ним, иначе
    /// выходит ровно то, ради чего всё делалось: тратишь 4000, ешь 2700 и
    /// думаешь, что это поддержание.
    ///
    /// Синхронизируем только когда расход изменился: иначе правка «ставить N
    /// ккал/день» с экрана плана затиралась бы на каждой перестройке кэшей.
    private func syncGoalWithExpenditure() {
        guard let plan, profile != nil else { return }
        let expenditure = (workingTDEE / 5).rounded() * 5
        guard defaults.object(forKey: Keys.goalSyncedTDEE) as? Double != expenditure else { return }
        defaults.set(expenditure, forKey: Keys.goalSyncedTDEE)
        let target = plan.dailyCalorieTarget(for: Date(), tdee: workingTDEE)
        if target != dailyGoal { dailyGoal = target }
    }

    private func rebuildCaches() {
        let calendar = Calendar.current

        // Строим O(1)-словари один раз
        entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        // Свой продукт идёт последним и перекрывает одноимённый встроенный:
        // так же, как в прежнем поиске, где сначала смотрели свои.
        fastDates = Set(fastDays.map { calendar.startOfDay(for: $0.date) })
        categoryByFoodName = Dictionary(
            (FoodDatabase.items + customFoods).map { ($0.name, $0.foodCategory) },
            uniquingKeysWith: { _, own in own }
        )
        // Каталог отдаёт состав уже разобранным и не меняется, поэтому его
        // словарь строится один раз; поверх кладём свои продукты — они как раз
        // меняются, но их немного.
        var profiles = FoodCatalog.nutrientProfilesByName
        for food in customFoods where !food.micronutrients.isEmpty {
            profiles[food.name] = NutrientProfile(per100g: food.micronutrients)
        }
        // Блюда после продуктов: их состав считается по ингредиентам, а значит
        // словарь продуктов к этому моменту должен быть уже собран.
        for dish in dishes {
            guard let profile = DishNutrients.profile(of: dish.ingredients,
                                                      composition: { profiles[$0]?.per100g })
            else { continue }
            profiles[dish.name] = profile
        }
        nutrientProfilesByName = profiles
        // uniquingKeysWith, а не uniqueKeysWithValues: последняя форма падает на повторном
        // ключе. Две записи могут схлопнуться в один локальный день после смены часового пояса,
        // и это был бы краш на каждом запуске без возможности выбраться.
        goalsByDay = Dictionary(
            goalRecords.map { (calendar.startOfDay(for: $0.date), $0.goal) },
            uniquingKeysWith: { _, newer in newer }
        )
        // Агрегаты за сегодня — один проход по entries
        todayEntries = entries.filter { calendar.isDateInToday($0.date) }
        consumedToday = todayEntries.reduce(0) { $0 + $1.calories }
        macrosToday = todayEntries.reduce(Macros.zero) { $0 + $1.macros }

        // Сводки по дням — один проход по сгруппированному словарю
        // entries уже отсортированы по дате desc, порядок внутри группы сохраняется
        let allDays = entriesByDay.map { day, dayEntries in
            DaySummary(date: day, entries: dayEntries, goal: goal(for: day))
        }.sorted { $0.date > $1.date }
        days = allDays
        let pastDays = allDays.filter { !calendar.isDateInToday($0.date) }

        // Последние 7 дней включая пустые — O(7) через словарь
        lastSevenDays = (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let day = calendar.startOfDay(for: date)
            return DaySummary(date: day, entries: entriesByDay[day] ?? [], goal: goal(for: day))
        }

        // История: последние 6 дней (не сегодня) всегда + старые дни с записями
        // Set из 6 дат для O(1) исключения из pastDays
        let last6 = lastSevenDays.filter { !calendar.isDateInToday($0.date) }
        let last6Dates = Set(last6.map { $0.date })
        let olderDays = pastDays.filter { !last6Dates.contains($0.date) }
        historyDays = (last6 + olderDays).sorted { $0.date > $1.date }

        hasWeighedToday = weightEntries.contains { calendar.isDateInToday($0.date) }
        adherence = computePlanAdherence()

        let (currentStreak, bestStreakVal, currentLoggingStreak) = computeStreak()
        streak = currentStreak
        bestStreak = bestStreakVal
        loggingStreak = currentLoggingStreak

        let today14 = calendar.startOfDay(for: Date())
        proteinStreak = computeProteinStreak()

        streakHistory = (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today14) else { return nil }
            return (date, isDayLogged(date), isDayKept(date))
        }

        let grouped = Dictionary(grouping: todayEntries) { MealPeriod.period(for: $0.date) }
        // Группы упорядочены по реальному времени последней записи, а не по порядку
        // в MealPeriod. Иначе «Перекус» (23:00–05:00) уезжает в начало списка, хотя
        // записи в нём — с раннего утра, и день читается вперемешку.
        groupedTodayEntries = MealPeriod.allCases.compactMap { period in
            guard let entries = grouped[period], !entries.isEmpty else { return nil }
            return (period, entries.sorted { $0.date > $1.date })
        }
        .sorted { lhs, rhs in
            (lhs.entries.first?.date ?? .distantPast) > (rhs.entries.first?.date ?? .distantPast)
        }

        // Расход по факту: пересчитывается на каждой перестройке, а сглаженное
        // значение двигается раз в сутки — иначе одна запись еды дёргала бы
        // цель несколько раз за день.
        adaptiveTDEE = computeAdaptiveTDEE()
        let today = calendar.startOfDay(for: Date())
        if let estimate = adaptiveTDEE?.tdee {
            let storedDay = defaults.object(forKey: Keys.adaptiveTDEEDay) as? Date
            let stored = defaults.object(forKey: Keys.adaptiveTDEE) as? Double
            if storedDay == today {
                smoothedTDEE = stored ?? estimate
            } else {
                let next = AdaptiveTDEE.smoothed(previous: stored, estimate: estimate)
                smoothedTDEE = next
                defaults.set(next, forKey: Keys.adaptiveTDEE)
                defaults.set(today, forKey: Keys.adaptiveTDEEDay)
            }
        } else {
            smoothedTDEE = defaults.object(forKey: Keys.adaptiveTDEE) as? Double
        }

        syncGoalWithExpenditure()

        let adapted = computeAdaptedTodayGoal()
        adaptedTodayGoal = adapted
        calorieBankBonus = adapted - effectiveGoal(for: Date())

        // После словарей: «Недавнее» берёт из них категорию продукта.
        rebuildRecent()
        rebuildVitaminOffers()

        cachesBuiltForDay = calendar.startOfDay(for: Date())

        // День, к которому относятся числа: после полуночи виджет не должен
        // показывать вчерашнее съеденное, пока приложение не открыли.
        groupDefaults?.set(calendar.startOfDay(for: Date()), forKey: "widget_day")
        groupDefaults?.set(consumedToday, forKey: "widget_consumed_today")
        groupDefaults?.set(adaptedTodayGoal, forKey: "widget_goal_today")
        // Макросы виджету: съеденное и цели. Углеводы без цели — это минимум
        // RDA, а не «сколько влезет», поэтому подставляем его, а не ноль.
        groupDefaults?.set(macrosToday.protein, forKey: "widget_protein")
        groupDefaults?.set(macrosToday.fat, forKey: "widget_fat")
        groupDefaults?.set(macrosToday.carbs, forKey: "widget_carbs")
        groupDefaults?.set(proteinTarget ?? 0, forKey: "widget_protein_target")
        groupDefaults?.set(fatTarget ?? 0, forKey: "widget_fat_target")
        groupDefaults?.set(carbsTarget ?? MacroTargets.carbsMinimum, forKey: "widget_carbs_target")
    }

    /// Пересобирает кэши, если с момента последнего пересчёта сменились сутки.
    /// Дёшево, когда день тот же, поэтому вызывать можно на каждую активацию приложения.
    func refreshIfDayChanged() {
        guard Calendar.current.startOfDay(for: Date()) != cachesBuiltForDay else { return }
        refresh()
        lockPastGoals()
    }


    /// Как только день перестаёт быть сегодняшним, фиксирует его текущую (адаптированную!)  эффективную цель
    /// снапшотом. Обновляет goalRecords в памяти напрямую — без полного DB-перечита.
    func lockPastGoals() {
        let today = Calendar.current.startOfDay(for: Date())
        // Если сегодня уже лочили и goalsByDay покрывает все прошлые дни — выходим без O(n) скана
        if goalLockedOnDay == today {
            let entryDates = Set(entries.lazy.filter {
                Calendar.current.startOfDay(for: $0.date) < today
            }.map { Calendar.current.startOfDay(for: $0.date) })
            guard !entryDates.subtracting(goalsByDay.keys).isEmpty else { return }
        }
        let entryDates = Set(entries.map { Calendar.current.startOfDay(for: $0.date) })
        let datesToLock = entryDates.subtracting(goalsByDay.keys).filter { $0 < today }
        guard !datesToLock.isEmpty else { goalLockedOnDay = today; return }

        var newRecords: [GoalRecord] = []
        // По возрастанию даты и с немедленной записью в goalsByDay: adaptedGoal(for:)
        // читает цели предыдущих дней недели через goal(for:), то есть из этого же словаря.
        // Без сортировки порядок обхода Set недетерминирован, а без записи в словарь дни
        // одной пачки считали бы банк друг от друга по неадаптированной цели — и итог
        // зависел бы от того, когда пользователь открыл приложение, а не от данных.
        for date in datesToLock.sorted() {
            let lockedGoal = adaptedGoal(for: date)
            goalsByDay[date] = lockedGoal
            let record = GoalRecord(date: date, goal: lockedGoal)
            context.insert(record)
            newRecords.append(record)
        }
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        goalRecords = (goalRecords + newRecords).sorted { $0.date < $1.date }
        goalLockedOnDay = today
        rebuildCaches()
    }

    // MARK: - Замеры тела

    /// Последний сеанс замеров — по нему считается отчёт.
    var latestMeasurement: BodyMeasurement? { measurements.first }

    /// Предыдущий заполненный сеанс, чтобы показать динамику относительно него.
    var previousMeasurement: BodyMeasurement? {
        measurements.dropFirst().first
    }

    /// История одного обхвата от старых к новым — для графика.
    /// Пропущенные замеры (ноль) не берём: это «не мерил», а не «ноль сантиметров».
    func measurementHistory(_ site: MeasurementSite, side: BodySide = .right) -> [(date: Date, value: Double)] {
        measurements
            .compactMap { m -> (Date, Double)? in
                let v = site.isPaired ? m.value(site, side) : m.value(site)
                return v > 0 ? (m.date, v) : nil
            }
            .sorted { $0.0 < $1.0 }
            .map { (date: $0.0, value: $0.1) }
    }

    /// Сеанс замеров за сегодня. Если его ещё нет, заводит новый, унаследовав
    /// обхваты прошлого: снимают обычно одно-два места, а производные величины
    /// читаются по последнему сеансу целиком.
    func measurementForToday() -> BodyMeasurement {
        if let latest = latestMeasurement, Calendar.current.isDateInToday(latest.date) {
            return latest
        }
        let fresh = BodyMeasurement(date: Date())
        if let previous = latestMeasurement {
            fresh.copyValues(from: previous)
        }
        addMeasurement(fresh)
        return fresh
    }

    /// Отмечен ли день голоданием. Именно отметка, а не пустой день: забытый день
    /// и намеренное голодание выглядят в базе одинаково, и различить их больше нечем.
    func isFastDay(_ date: Date) -> Bool {
        fastDates.contains(Calendar.current.startOfDay(for: date))
    }

    func fastDay(on date: Date) -> FastDay? {
        let day = Calendar.current.startOfDay(for: date)
        return fastDays.first { Calendar.current.startOfDay(for: $0.date) == day }
    }

    /// Ближайшее голодание — сегодня или в пределах трёх дней — и советы, которые
    /// к месту именно сейчас. nil, когда голодания впереди нет или советовать
    /// пока рано.
    func fastingHint(now: Date = Date()) -> FastingHint? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0...FastingAdvice.earliestDaysBefore {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  let fast = fastDay(on: date) else { continue }
            let items = FastingAdvice.advice(for: fast.kind, daysBefore: offset)
            guard !items.isEmpty else { return nil }
            return FastingHint(date: date, kind: fast.kind, daysUntil: offset, items: items)
        }
        return nil
    }

    @discardableResult
    func markFastDay(_ date: Date = Date(), kind: FastKind) -> FastDay {
        if let existing = fastDay(on: date) {
            existing.kind = kind
            do { try context.save() } catch { logger.error("context.save failed: \(error)") }
            rebuildCaches()
            return existing
        }
        let day = FastDay(date: date, kind: kind)
        context.insert(day)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        fastDays = (fastDays + [day]).sorted { $0.date > $1.date }
        rebuildCaches()
        return day
    }

    func unmarkFastDay(_ date: Date = Date()) {
        guard let day = fastDay(on: date) else { return }
        context.delete(day)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        fastDays.removeAll { $0.id == day.id }
        rebuildCaches()
    }

    func addMeasurement(_ measurement: BodyMeasurement) {
        context.insert(measurement)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        measurements = (measurements + [measurement]).sorted { $0.date > $1.date }
    }

    func deleteMeasurement(_ measurement: BodyMeasurement) {
        context.delete(measurement)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        measurements.removeAll { $0.id == measurement.id }
    }

    func saveMeasurementEdits() {
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        measurements.sort { $0.date > $1.date }
    }

    // MARK: - Изменение данных
    // Живут здесь, а не в отдельном файле: им нужны сеттеры private(set)-свойств,
    // а Swift не пускает к ним через границу файла. Выносить пришлось бы ценой
    // открытия записи всему модулю — защита важнее размера файла.

    /// Сохраняет профиль и по умолчанию сразу пересчитывает дневную цель по калориям.
    func updateProfile(_ newProfile: UserProfile, syncDailyGoal: Bool = true) {
        profile = newProfile
        if let data = try? JSONEncoder().encode(newProfile) {
            defaults.set(data, forKey: Keys.profile)
        }
        if syncDailyGoal, let plan {
            // Норма плана — производная от TDEE, а он падает вместе с весом.
            // Раньше при выключенном цикле она замерзала на дате старта, и к середине
            // сушки дефицит незаметно съёживался до нуля. С включённым циклом такого
            // не было: там цель считалась заново на каждый день. Один и тот же план
            // вёл себя по-разному в зависимости от тумблера, который по смыслу
            // отвечает только за распределение калорий по дням недели.
            dailyGoal = plan.dailyCalorieTarget(tdee: workingTDEE)
        } else if syncDailyGoal, isPremium {
            // Премиум без плана — поддержание: режим задаётся планом, а вне
            // плана тело держат. Иначе выбранная когда-то цель профиля тихо
            // держала бы вечный дефицит.
            dailyGoal = Int(workingTDEE.rounded())
        } else if syncDailyGoal {
            dailyGoal = newProfile.calorieTarget
        } else {
            // Профиль участвует в adherence через tdee — пересчитать надо в любом случае.
            rebuildCaches()
        }
    }

    /// Запускает план — считает точную дневную норму под срок/целевой вес и делает её текущей целью.
    ///
    /// Гейт премиума живёт здесь, а не только в UI: раньше единственной защитой была
    /// проверка `isPremium` в тулбаре профиля, и любой новый экран мог случайно выдать
    /// платную фичу бесплатно. Уже сохранённый план продолжает работать — отбирать
    /// у пользователя то, что он настроил, мы не будем.
    func startPlan(_ newPlan: Plan) {
        guard isPremium else {
            logger.warning("startPlan вызван без активного премиума — игнорируем")
            return
        }
        plan = newPlan
        if let data = try? JSONEncoder().encode(newPlan) {
            defaults.set(data, forKey: Keys.plan)
        }
        if let profile {
            dailyGoal = newPlan.dailyCalorieTarget(tdee: workingTDEE)
        }
        rebuildCaches()
    }

    /// Восстанавливает дневник из копии, полностью заменяя нынешние данные.
    ///
    /// Именно заменяя, а не сливая. Слияние звучит безопаснее, но у него нет
    /// определённого ответа на простой вопрос: что делать с записью, которая
    /// есть и там и там, но отличается. Замена предсказуема, а подтверждение
    /// спрашивается на экране — там же, где человек видит, за какое число копия.
    ///
    /// План кладём в обход `startPlan`: тот закрыт премиумом, а после переустановки
    /// флаг премиума ещё не поднят, и настроенный план молча пропал бы.
    /// Восстановление возвращает то, что у человека было, а не то, на что он
    /// имеет право прямо сейчас.
    func restore(from backup: CaloriesBackup) {
        for entry in entries { context.delete(entry) }
        for food in customFoods { context.delete(food) }
        for dish in dishes { context.delete(dish) }
        for weight in weightEntries { context.delete(weight) }
        for record in goalRecords { context.delete(record) }
        for measurement in measurements { context.delete(measurement) }
        for day in fastDays { context.delete(day) }

        for item in backup.entries {
            context.insert(FoodEntry(
                name: item.name, calories: item.calories,
                macros: Macros(protein: item.protein, fat: item.fat, carbs: item.carbs),
                grams: item.grams, date: item.date))
        }
        for item in backup.weights {
            context.insert(WeightEntry(weightKg: item.weightKg, date: item.date))
        }
        for item in backup.goalHistory {
            context.insert(GoalRecord(date: item.date, goal: item.goal))
        }
        for item in backup.products {
            let food = FoodItem(
                name: item.name, caloriesPer100g: item.caloriesPer100g,
                protein: item.protein, fat: item.fat, carbs: item.carbs,
                defaultGrams: item.defaultGrams,
                category: item.category.flatMap(FoodCategory.init(rawValue:)) ?? .other)
            if let micronutrients = item.micronutrients { food.micronutrients = micronutrients }
            food.catalogID = item.catalogID
            food.updatedAt = item.updatedAt
            context.insert(food)
        }
        for item in backup.dishes {
            context.insert(Dish(name: item.name, ingredients: item.ingredients, createdAt: item.createdAt))
        }
        for item in backup.measurements ?? [] {
            context.insert(BodyMeasurement(
                date: item.date,
                neckCm: item.neck, chestCm: item.chest, shouldersCm: item.shoulders,
                waistCm: item.waist, beltCm: item.belt, pelvisCm: item.pelvis, glutesCm: item.glutes,
                bicepsLeftCm: item.bicepsLeft, bicepsRightCm: item.bicepsRight,
                forearmLeftCm: item.forearmLeft, forearmRightCm: item.forearmRight,
                wristLeftCm: item.wristLeft, wristRightCm: item.wristRight,
                thighLeftCm: item.thighLeft, thighRightCm: item.thighRight,
                quadLeftCm: item.quadLeft, quadRightCm: item.quadRight,
                calfLeftCm: item.calfLeft, calfRightCm: item.calfRight))
        }
        for item in backup.fastDays ?? [] {
            context.insert(FastDay(
                date: item.date,
                kind: FastKind(rawValue: item.kind) ?? .dry,
                startedAt: item.startedAt, endedAt: item.endedAt))
        }

        do { try context.save() } catch { logger.error("restore save failed: \(error)") }

        if let restoredProfile = backup.profile {
            profile = restoredProfile
            if let data = try? JSONEncoder().encode(restoredProfile) {
                defaults.set(data, forKey: Keys.profile)
            }
        }
        if let restoredPlan = backup.plan {
            plan = restoredPlan
            if let data = try? JSONEncoder().encode(restoredPlan) {
                defaults.set(data, forKey: Keys.plan)
            }
        } else {
            plan = nil
            defaults.removeObject(forKey: Keys.plan)
        }
        dailyGoal = backup.dailyGoal

        refresh()
    }

    /// Завершает план и возвращает дневную цель к обычному расчёту по профилю.
    /// С какого дня идёт нынешнее поддержание: с конца прошлой фазы, а если
    /// её не было — со дня, когда появился профиль и начался дневник.
    var maintenanceSince: Date? {
        guard plan == nil else { return nil }
        if let last = phaseHistory.max(by: { $0.endDate < $1.endDate })?.endDate { return last }
        return entries.map(\.date).min() ?? weightEntries.map(\.date).min()
    }

    /// Процент жира по последним замерам. nil, когда метод по обхватам ещё
    /// не включился: оценка по ИМТ для советов про фазы слишком груба.
    var measuredBodyFatPercent: Double? {
        guard let profile, profile.navyBodyFat(from: latestMeasurement) != nil else { return nil }
        return profile.bodyFatPercentage(from: latestMeasurement)
    }

    /// Что делать дальше — сушиться, набирать или ещё постоять.
    func phaseAdvice(bodyFatPercent: Double?, now: Date = Date()) -> PhaseAdvice.Recommendation {
        PhaseAdvice.recommend(history: phaseHistory,
                              maintenanceSince: maintenanceSince,
                              bodyFatPercent: bodyFatPercent,
                              today: now)
    }

    /// Записать закончившийся план в историю. Вызывается при завершении плана,
    /// а не при каждой правке: история — про прожитое, а не про задуманное.
    private func rememberFinishedPlan(_ finished: Plan, now: Date = Date()) {
        let end = min(now, finished.endDate)
        guard end > finished.startDate else { return }
        // Намерение всей фазы — то, чем план был по сути: сушка с брейком
        // внутри остаётся сушкой.
        let intent = finished.phases.first(where: { $0.intent == .cut })?.intent
            ?? finished.phases.first?.intent ?? .maintenance
        let record = PhaseRecord(intent: intent,
                                 startDate: finished.startDate,
                                 endDate: end,
                                 startWeightKg: finished.startWeightKg,
                                 endWeightKg: weightTrend(on: end))
        phaseHistory.append(record)
        if let data = try? JSONEncoder().encode(phaseHistory) {
            defaults.set(data, forKey: Keys.phaseHistory)
        }
    }

    func cancelPlan() {
        if let plan { rememberFinishedPlan(plan) }
        plan = nil
        defaults.removeObject(forKey: Keys.plan)
        // Без плана у премиума идёт поддержание: режим — это план, а вне
        // плана тело держат, а не гонят в вечный дефицит по настройке профиля.
        if isPremium {
            dailyGoal = Int(workingTDEE.rounded())
        } else if let profile {
            dailyGoal = profile.calorieTarget
        }
        rebuildCaches()
    }

    /// Делает сегодня рефидом, забирая его у самого высокого из оставшихся дней недели.
    func moveRefeed(to date: Date = Date()) {
        guard let plan else { return }
        let moved = plan.movingRefeed(to: date)
        guard moved != plan else { return }
        savePlanKeepingGoal(moved)
    }

    /// Ставит диет-брейк с ближайшей недели плана.
    func startDietBreak(weeks: Int, from date: Date = Date()) {
        guard let plan else { return }
        let updated = plan.startingDietBreak(from: date, weeks: weeks)
        guard updated != plan else { return }
        savePlanKeepingGoal(updated)
    }

    /// Убирает поставленный руками брейк, пока он не начался.
    func cancelPendingDietBreak(on date: Date = Date()) {
        guard let plan else { return }
        let updated = plan.cancelingPendingDietBreak(on: date)
        guard updated != plan else { return }
        savePlanKeepingGoal(updated)
    }

    /// Возвращает рефид этой недели на его обычный день.
    func undoRefeedMove(on date: Date = Date()) {
        guard var plan, plan.canUndoRefeedMove(on: date) else { return }
        plan.refeedMove = nil
        savePlanKeepingGoal(plan)
    }

    /// Сохраняет план, не трогая `dailyGoal`. Перенос рефида меняет только
    /// раскладку по дням — пересчитанную «замедлить» норму он затирать не должен.
    private func savePlanKeepingGoal(_ newPlan: Plan) {
        plan = newPlan
        if let data = try? JSONEncoder().encode(newPlan) {
            defaults.set(data, forKey: Keys.plan)
        }
        rebuildCaches()
    }

    /// Пересчитывает срок плана под новую дату финиша (в любую сторону).
    func reschedulePlan(to newEndDate: Date) {
        guard let plan else { return }
        startPlan(plan.rescheduled(toEnd: newEndDate))
    }

    func add(name: String, calories: Int, macros: Macros = Macros(protein: 0, fat: 0, carbs: 0), grams: Double? = nil, date: Date = Date()) {
        let entry = FoodEntry(name: name, calories: calories, macros: macros, grams: grams, date: date)
        context.insert(entry)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        entries = ([entry] + entries).sorted { $0.date > $1.date }
        rebuildCaches()
        // Прошлая дата — нужно залочить цель; сегодняшняя — нет
        if Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date()) {
            lockPastGoals()
        }
    }

    func delete(entry: FoodEntry) {
        context.delete(entry)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        entries.removeAll { $0.id == entry.id }
        rebuildCaches()
        // Удаление не может породить новый незалоченный день — лочить не нужно
    }

    func updateEntry(_ entry: FoodEntry, name: String, calories: Int, macros: Macros, grams: Double?, date: Date) {
        entry.name = name
        entry.calories = calories
        entry.macros = macros
        entry.grams = grams
        entry.date = date
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        entries.sort { $0.date > $1.date }
        rebuildCaches()
        lockPastGoals()
    }

    /// Категории всех продуктов, вошедших в приём пищи.
    ///
    /// Сама запись их не хранит: приём пищи собирается из нескольких продуктов,
    /// и одной категории у него нет. Зато имя склеено из названий через запятую —
    /// по нему состав и восстанавливается. Длинное имя обрезается многоточием,
    /// поэтому последний кусок может не совпасть ни с чем: тогда он просто
    /// пропускается, а не портит остальные значки.
    /// Повторы схлопываются: курица с говядиной — это одно мясо, а не две вилки.
    /// Категории ингредиентов блюда — тем же способом, что и у приёма пищи,
    /// только состав здесь известен точно, а не восстанавливается из имени.
    func foodCategories(of dish: Dish) -> [FoodCategory] {
        var seen: Set<FoodCategory> = []
        var found: [FoodCategory] = []
        for ingredient in dish.ingredients {
            guard let match = category(ofProductNamed: ingredient.foodName),
                  seen.insert(match).inserted else { continue }
            found.append(match)
        }
        return found
    }

    private func category(ofProductNamed name: String) -> FoodCategory? {
        categoryByFoodName[name]
    }

    func foodCategories(forEntryNamed name: String) -> [FoodCategory] {
        var seen: Set<FoodCategory> = []
        var found: [FoodCategory] = []
        for part in name.components(separatedBy: ", ") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "…"))
            guard !trimmed.isEmpty else { continue }
            guard let match = category(ofProductNamed: trimmed),
                  seen.insert(match).inserted else { continue }
            found.append(match)
        }
        return found
    }

    func addCustomFood(name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double, category: FoodCategory = .other, defaultGrams: Double = 100, micronutrients: Micronutrients = Micronutrients(), catalogID: Int? = nil) {
        let food = FoodItem(name: name, caloriesPer100g: caloriesPer100g, protein: protein, fat: fat, carbs: carbs, defaultGrams: defaultGrams, category: category)
        if !micronutrients.isEmpty { food.micronutrients = micronutrients }
        food.catalogID = catalogID
        food.updatedAt = Date()
        context.insert(food)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods = (customFoods + [food]).sorted { $0.name < $1.name }
        rebuildCaches()
    }

    /// Есть ли уже такой продукт среди своих. По названию: у продукта из базы
    /// и у своей копии разные идентификаторы, а человек различает их по имени.
    func isInMyFoods(_ food: FoodItem) -> Bool {
        customFoods.contains { $0.name == food.name }
    }

    /// Кладёт продукт из базы в свои — целиком, с категорией, порцией
    /// и витаминами.
    ///
    /// Прежняя копия переносила только калории и БЖУ: продукт из базы с
    /// витаминами превращался в свой без единого витамина и в категории
    /// «прочее» — то есть сохранение отнимало ровно то, ради чего его брали.
    func saveToMyFoods(_ food: FoodItem) {
        guard !isInMyFoods(food) else { return }
        addCustomFood(name: food.name,
                      caloriesPer100g: food.caloriesPer100g,
                      protein: food.protein, fat: food.fat, carbs: food.carbs,
                      category: food.foodCategory,
                      defaultGrams: food.defaultGrams > 0 ? food.defaultGrams : 100,
                      micronutrients: food.micronutrients,
                      catalogID: food.catalogID)
    }

    func deleteCustomFood(_ food: FoodItem) {
        context.delete(food)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods.removeAll { $0.id == food.id }
        rebuildCaches()
    }

    func updateCustomFood(_ food: FoodItem, name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double, category: FoodCategory = .other, defaultGrams: Double = 100, micronutrients: Micronutrients = Micronutrients(), catalogID: Int? = nil) {
        food.micronutrients = micronutrients
        food.catalogID = catalogID
        food.updatedAt = Date()
        food.defaultGrams = defaultGrams
        food.foodCategory = category
        food.name = name
        food.caloriesPer100g = caloriesPer100g
        food.protein = protein
        food.fat = fat
        food.carbs = carbs
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods.sort { $0.name < $1.name }
        rebuildCaches()
    }

    func setDefaultGrams(_ food: FoodItem, grams: Double) {
        food.defaultGrams = grams
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
    }

    func addDish(name: String, ingredients: [DishIngredient], servingGrams: Double = 0) {
        let dish = Dish(name: name, ingredients: ingredients)
        dish.defaultServingGrams = servingGrams
        dish.updatedAt = Date()
        context.insert(dish)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        dishes = [dish] + dishes
        rebuildCaches()
    }

    func updateDish(_ dish: Dish, name: String, ingredients: [DishIngredient], servingGrams: Double = 0) {
        dish.name = name
        dish.ingredients = ingredients
        dish.defaultServingGrams = servingGrams
        dish.updatedAt = Date()
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        rebuildCaches()
    }

    func deleteDish(_ dish: Dish) {
        context.delete(dish)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        dishes.removeAll { $0.id == dish.id }
        rebuildCaches()
    }

    func addWeight(_ kg: Double, date: Date = Date()) {
        let entry = WeightEntry(weightKg: kg, date: date)
        context.insert(entry)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        weightEntries = (weightEntries + [entry]).sorted { $0.date < $1.date }
        rebuildCaches()
        if var p = profile {
            p.weightKg = kg
            updateProfile(p, syncDailyGoal: false)
        }
    }

    func deleteWeight(_ entry: WeightEntry) {
        context.delete(entry)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        weightEntries.removeAll { $0.id == entry.id }
        rebuildCaches()
    }

    /// Недавнее — выводится из фактических записей дневника, а не из списка имён,
    /// который приходилось сопоставлять с каталогами. Продукт из Open Food Facts или
    /// со сканера штрихкода ни в своих продуктах, ни во встроенной базе не лежит,
    /// поэтому в «Недавнем» он раньше не появлялся вовсе.
    ///
    /// Берём только записи с указанным весом: без него пересчитать на 100 г нельзя,
    /// а быстрые записи «столько-то калорий» переиспользовать всё равно нечего.
    /// Недавнее — это и съеденное, и заведённое.
    ///
    /// Раньше сюда попадало только съеденное из дневника, и свежесозданный
    /// продукт было не найти: в списке по категориям он лежит среди тех, что
    /// завели полгода назад. Но заводят продукт ровно тогда, когда собираются
    /// им пользоваться, — значит он такой же недавний, как только что съеденный.
    ///
    /// Считается в `rebuildCaches`, а не в геттере. Вычисляемым оно пробегало всю
    /// историю дневника и создавало объекты SwiftData на каждую перерисовку —
    /// то есть на каждое нажатие клавиши в поиске, и экран добавления заметно
    /// подтормаживал на вводе.
    private func rebuildRecent() {
        let dishNames = Set(dishes.map(\.name))
        var seen = Set<String>()

        // Сперва только даты и ссылки: объекты дорого создавать, а нужны они
        // лишь для верхушки списка.
        var candidates: [(date: Date, entry: FoodEntry?, food: FoodItem?)] = []
        for entry in entries {
            guard let grams = entry.grams, grams > 0 else { continue }
            guard !dishNames.contains(entry.name), !seen.contains(entry.name) else { continue }
            seen.insert(entry.name)
            candidates.append((entry.date, entry, nil))
        }
        for food in customFoods {
            guard let updatedAt = food.updatedAt, !seen.contains(food.name) else { continue }
            seen.insert(food.name)
            candidates.append((updatedAt, nil, food))
        }

        recentFoods = candidates
            .sorted { $0.date > $1.date }
            .prefix(Self.recentLimit)
            .map { candidate in
                if let food = candidate.food { return food }
                let entry = candidate.entry!
                let factor = 100 / (entry.grams ?? 100)
                return FoodItem(
                    name: entry.name,
                    caloriesPer100g: Int((Double(entry.calories) * factor).rounded()),
                    protein: entry.protein * factor,
                    fat: entry.fat * factor,
                    carbs: entry.carbs * factor,
                    defaultGrams: entry.grams ?? 100,
                    // Недавнее пересобирается из записей дневника, а они категорию
                    // не хранят. Без этой строки весь список показывал «Другое».
                    category: categoryByFoodName[entry.name] ?? .other
                )
            }

        var seenDishes = Set<String>()
        var dishCandidates: [(date: Date, dish: Dish)] = []
        for entry in entries {
            guard !seenDishes.contains(entry.name) else { continue }
            guard let dish = dishes.first(where: { $0.name == entry.name }) else { continue }
            seenDishes.insert(entry.name)
            dishCandidates.append((entry.date, dish))
        }
        for dish in dishes where !seenDishes.contains(dish.name) {
            seenDishes.insert(dish.name)
            dishCandidates.append((dish.updatedAt ?? dish.createdAt, dish))
        }
        recentDishes = dishCandidates
            .sorted { $0.date > $1.date }
            .prefix(Self.recentLimit)
            .map(\.dish)
    }

    /// Кому из своих продуктов каталог может одолжить витамины.
    ///
    /// Точное совпадение по названию не считаем: там состав и так подтягивается
    /// сам, и предлагать нечего. Смысл только в непохожих названиях — «Творог
    /// мой» против «Творог 5%», — где связь может найти только поиск.
    private func rebuildVitaminOffers() {
        var offered: Set<UUID> = []
        for food in customFoods {
            guard food.catalogID == nil, food.micronutrients.isEmpty else { continue }
            guard nutrientProfilesByName[food.name] == nil else { continue }
            if !FoodCatalog.candidates(forName: food.name, limit: 1).isEmpty {
                offered.insert(food.id)
            }
        }
        foodsOfferedVitamins = offered
    }

    /// Сколько строк держим в «Недавнем». Больше — это уже не «недавнее»,
    /// а второй список всего подряд, по которому снова надо искать глазами.
    static let recentLimit = 8

    /// Последняя по дате запись веса.
    var latestWeight: WeightEntry? {
        weightEntries.last
    }

    /// Записи веса за последние N дней, от старого к новому.
    func weightHistory(lastDays count: Int) -> [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -count, to: Date()) ?? .distantPast
        let cutoffStart = Calendar.current.startOfDay(for: cutoff)
        return weightEntries.filter { $0.date >= cutoffStart }
    }
}
