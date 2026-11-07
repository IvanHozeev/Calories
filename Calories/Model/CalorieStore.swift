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
    @ObservationIgnored let defaults: UserDefaults
    /// Общий с виджетом контейнер. Тесты передают nil, чтобы не переписывать боевые данные виджета.
    @ObservationIgnored let groupDefaults: UserDefaults?

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

    /// Откуда взялась дневная норма — и, значит, что с ней делать, когда
    /// изменится расход.
    ///
    /// Норма идёт за расходом: он измеряется по дневнику и весам, и застывшее
    /// число быстро перестаёт значить то, что обещает. Но «идёт за расходом» —
    /// не то же самое, что «возвращается к плановой»: человек, принявший на
    /// экране плана предложение есть больше, выбрал темп, а не одно число, и
    /// подтянувшиеся шаги не должны отменять его выбор.
    enum GoalSource: String {
        /// Плановая норма фазы: столько, сколько велит заданный темп.
        case plan
        /// Принятый пересчёт «ставить N ккал/день»: столько, сколько нужно,
        /// чтобы прийти к цели фазы в срок от сегодняшнего веса.
        case recalibrated
        /// Своё число, вписанное руками. Формулы за ним нет, и трогать его
        /// нельзя: это не расчёт, который можно повторить.
        case manual
    }

    private(set) var dailyGoalSource: GoalSource = .plan

    private func setGoalSource(_ source: GoalSource) {
        dailyGoalSource = source
        defaults.set(source.rawValue, forKey: Keys.goalSource)
    }

    private func stampDailyGoalPhase() {
        dailyGoalPhaseID = plan?.phase(on: Date())?.id
        defaults.set(dailyGoalPhaseID?.uuidString, forKey: Keys.goalPhase)
    }
    var profile: UserProfile?
    var plan: Plan?
    /// Премиум куплен. Сам по себе не значит доступа: его даёт ещё и пробный период.
    var hasPurchasedPremium: Bool {
        didSet {
            defaults.set(hasPurchasedPremium, forKey: Keys.premium)
            // И в общую группу — сразу, а не до следующего пересчёта дня:
            // покупку совершают в одном приложении, а открыться она должна
            // в обоих, пока человек ещё помнит, за что платил.
            groupDefaults?.set(hasPurchasedPremium || isTrialActive, forKey: "shared_is_premium")
        }
    }

    /// Когда начался пробный период плана. Начинается один раз — при первом плане
    /// из онбординга — и заново не выдаётся, даже если план завершить и начать снова.
    var trialStartedAt: Date?

    /// Что сейчас в зале: разгрузка, тип дня, объём недели. nil — соседнего
    /// приложения нет или оно молчит.
    ///
    /// Снимок держим в памяти, а не читаем при каждом обращении: к нему
    /// ходят и вердикт недели, и подсказки дня, а меняется он несколько раз
    /// в сутки.
    private(set) var gymState: GymBridge.State?

    /// Имя сегодняшней тяжёлой тренировки — или nil, когда день лёгкий,
    /// это отдых, или о дне ничего не известно.
    var gymHeavyDayName: String? {
        guard GymBridge.isHeavyDay(gymState) == true else { return nil }
        return GymBridge.todayName(gymState)
    }

    /// Перечитать снимок из зала. Зовётся там же, где права: тренировку
    /// закрывают в соседнем приложении, пока мы в фоне.
    func refreshGymState() {
        gymState = GymBridge.read(defaults: groupDefaults)
    }

    /// Перечитать права, пришедшие от соседа.
    ///
    /// Вызывается при запуске и при каждом возвращении в приложение: покупку
    /// совершают в GymLogger, пока мы в фоне, и узнать об этом иначе неоткуда.
    func refreshSharedEntitlements() {
        let bundle = (groupDefaults?.bool(forKey: "shared_is_bundle") ?? false)
            || (groupDefaults?.bool(forKey: "gym_is_bundle") ?? false)
        guard bundle != bundleUnlocked else { return }
        bundleUnlocked = bundle
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
    /// Что у этого человека «обычный день» — в шагах и в потраченном.
    /// nil — данных ещё мало, идёт период привыкания, и поправка не работает.
    private(set) var activityBaseline: ActivityAdjustment.Baseline?
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
    /// Отпечаток своих продуктов, по которому видно, надо ли пересчитывать
    /// предложения витаминов. Ноль — «ещё не считали ни разу».
    @ObservationIgnored private var vitaminOffersSignature: Int?
    /// Какой макрос сегодня ведущий — тот, что ещё не закрыт.
    ///
    /// Порядок закрытия: белок, потом жир, потом углеводы. По нему красится
    /// акцент приложения, если человек выбрал «По макросу»: цвет ведёт к тому,
    /// что осталось добрать, а не украшает экран.
    ///
    /// nil — закрыто всё.
    private(set) var focusMacro: MacroKind?
    private(set) var adaptedTodayGoal: Int = 0
    private(set) var calorieBankBonus: Int = 0

    // O(1) словари для быстрого поиска
    @ObservationIgnored private(set) var entriesByDay: [Date: [FoodEntry]] = [:]
    /// Категория по имени продукта. Строится один раз на обновление, потому что
    /// раньше каждая строка дневника при каждой перерисовке линейно прочёсывала
    /// и свои продукты, и встроенную базу — на каждое слово в названии приёма пищи.
    @ObservationIgnored private(set) var categoryByFoodName: [String: FoodCategory] = [:]
    /// Кашрутный статус по названию продукта — тем же способом, что категория.
    /// Записи дневника его не хранят: продукт правят, а снимок остаётся, и
    /// статус приходится собирать обратно по имени.
    @ObservationIgnored private(set) var kosherByFoodName: [String: KosherStatus] = [:]
    /// Продукты, после которых ждут как после мясного: твёрдый выдержанный сыр.
    @ObservationIgnored private(set) var hardCheeseFoodNames: Set<String> = []
    /// Запрещённые видом. Множеством, а не словарём: ответ тут один — есть
    /// имя в наборе или нет.
    @ObservationIgnored private(set) var forbiddenFoodNames: Set<String> = []
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

    enum Keys {
        static let goal = "daily_goal"
        static let adaptiveTDEE = "adaptive_tdee"
        static let adaptiveTDEEDay = "adaptive_tdee_day"
        /// Расход по дням: каким он был в тот день, а не какой он сегодня.
        static let tdeeHistory = "adaptive_tdee_history"
        /// «Обычный день» в шагах и когда его в последний раз считали.
        static let activityBaseline = "activity_baseline"
        static let activityBaselineDay = "activity_baseline_day"
        static let usesAdaptiveTDEE = "use_adaptive_tdee"
        static let goalSyncedTDEE = "goal_synced_tdee"
        static let goalSource = "daily_goal_source"
        static let previousPlan = "plan_previous"
        static let previousPlanDate = "plan_previous_date"
        static let goalAgreedAt = "daily_goal_agreed_at"
        static let goalProposal = "daily_goal_proposal"
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
        self.dailyGoalSource = (defaults.string(forKey: Keys.goalSource)
                                .flatMap(GoalSource.init(rawValue:))) ?? .plan
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

        restoreCroppedNames()
        rebuildCaches()
    }

    /// Возвращает полные имена приёмам, обрезанным по длине.
    ///
    /// Склейка имён резалась на шестидесяти знаках ещё при сохранении, и
    /// многоточие уезжало в базу. На экране это выглядело сломанной вёрсткой,
    /// а чинить было нечего: так и записано. Состав приёма хранится целиком,
    /// поэтому имя восстанавливается из него.
    ///
    /// Один раз: дальше имена приходят целыми.
    private func restoreCroppedNames() {
        let key = "entry_names_uncropped"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        var repaired = false
        for entry in entries where entry.name.hasSuffix("…") {
            let parts = entry.components.map(\.name).filter { !$0.isEmpty }
            guard parts.count > 1 else { continue }
            entry.name = parts.joined(separator: ", ")
            repaired = true
        }
        guard repaired else { return }
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
    }

    /// Подтянуть норму плана к расходу, от которого её считают.
    ///
    /// План пересчитывает дневную норму от расхода, но записанное число живёт
    /// в фазе и само не меняется. Пока расход брали из формулы, это было верно:
    /// формула не двигается. Факт двигается — и норма должна идти за ним, иначе
    /// выходит ровно то, ради чего всё делалось: тратишь 4000, ешь 2700 и
    /// думаешь, что это поддержание.
    ///
    /// Пересчитывает всё производное от записей дневника.
    ///
    /// Порядок шагов не случаен и держался раньше только комментариями внутри
    /// одной стотридцатистрочной функции: словари нужны сводкам, сводки —
    /// сериям, расход — цели, а «Недавнее» берёт категорию из словарей.
    /// Теперь порядок виден сразу, а каждый шаг читается отдельно.
    private func rebuildCaches() {
        let calendar = Calendar.current

        rebuildLookups(calendar)
        rebuildToday(calendar)
        rebuildDays(calendar)

        hasWeighedToday = weightEntries.contains { calendar.isDateInToday($0.date) }
        adherence = computePlanAdherence()

        rebuildStreaks(calendar)
        rebuildExpenditure(calendar)

        // После словарей: «Недавнее» берёт из них категорию продукта.
        rebuildRecent()
        rebuildVitaminOffers()

        cachesBuiltForDay = calendar.startOfDay(for: Date())
        publishToWidget(calendar)
        BodyBridge.publish(profile: profile, measurement: latestMeasurement)
    }

#if DEBUG
    /// Сколько стоит каждый шаг перестройки — в миллисекундах.
    ///
    /// Перестройка идёт на каждую запись еды и на каждое потягивание списка
    /// вниз, то есть внутри жеста, и лишние сто миллисекунд здесь человек
    /// чувствует как подлагивание. Вопрос «что именно из этого дорого»
    /// возникает не первый раз, и отвечать на него догадками дороже, чем
    /// держать эти двадцать строк.
    func rebuildTimings() -> [(step: String, ms: Double)] {
        let calendar = Calendar.current
        func measure(_ name: String, _ block: () -> Void) -> (String, Double) {
            let start = Date()
            block()
            return (name, Date().timeIntervalSince(start) * 1000)
        }
        return [
            measure("словари") { rebuildLookups(calendar) },
            measure("сегодня") { rebuildToday(calendar) },
            measure("дни") { rebuildDays(calendar) },
            measure("серии") { rebuildStreaks(calendar) },
            measure("расход") { rebuildExpenditure(calendar) },
            measure("недавнее") { rebuildRecent() },
            measure("витамины своим") { rebuildVitaminOffers() },
            measure("виджет") { publishToWidget(calendar) },
        ]
    }
#endif

    /// Словари для O(1)-обращений: день → записи, имя → категория и состав,
    /// день → зафиксированная цель.
    private func rebuildLookups(_ calendar: Calendar) {
        // Строим O(1)-словари один раз
        entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        // Свой продукт идёт последним и перекрывает одноимённый встроенный:
        // так же, как в прежнем поиске, где сначала смотрели свои.
        // Пост может идти через полночь: в наборе все сутки, которых он касается.
        fastDates = Set(fastDays.flatMap(\.coveredDays))
        categoryByFoodName = Dictionary(
            (FoodDatabase.items + customFoods).map { ($0.name, $0.foodCategory) },
            uniquingKeysWith: { _, own in own }
        )
        let allFoods = FoodDatabase.items + customFoods
        kosherByFoodName = Dictionary(
            allFoods.map { ($0.name, $0.kosherStatus) },
            uniquingKeysWith: { _, own in own }
        )
        hardCheeseFoodNames = Set(allFoods.filter(\.isHardCheese).map(\.name))
        forbiddenFoodNames = Set(allFoods.filter(\.kosherForbidden).map(\.name))
        // Каталог отдаёт состав уже разобранным и не меняется, поэтому его
        // словарь строится один раз; поверх кладём свои продукты — они как раз
        // меняются, но их немного.
        var profiles = FoodCatalog.nutrientProfilesByName
        for food in customFoods where !food.micronutrients.isEmpty {
            // Оценка по классу идёт в день с половинным весом: вещества у
            // похожей еды расходятся примерно в полтора раза, и объявлять такой
            // день изученным наравне с измеренным нельзя.
            profiles[food.name] = NutrientProfile(
                per100g: food.micronutrients,
                coverage: food.micronutrientsAreEstimated ? NutrientProfile.estimateCoverage : 1)
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
    }

    /// Сегодняшний день: записи, съеденное, макросы и приёмы пищи по времени.
    private func rebuildToday(_ calendar: Calendar) {
        // Агрегаты за сегодня — один проход по entries
        todayEntries = entries.filter { calendar.isDateInToday($0.date) }
        consumedToday = todayEntries.reduce(0) { $0 + $1.calories }
        macrosToday = todayEntries.reduce(Macros.zero) { $0 + $1.macros }

        groupedTodayEntries = MealPeriod.group(todayEntries)
    }


    /// Дневные сводки: все дни, последняя неделя и история.
    private func rebuildDays(_ calendar: Calendar) {
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
    }

    /// Серии: дней подряд с записями, с выполненной нормой и с белком.
    private func rebuildStreaks(_ calendar: Calendar) {
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
    }

    /// Как часто пересматривается измеренный расход, в днях.
    static let expenditureUpdateDays = 7

    /// Сохранённая активность по дням. Дневник её не собирает — она приходит
    /// из «Здоровья» через `StepStore`, — но знать о ней ему надо: она едет в
    /// резервную копию вместе с записями, а по ней же видно, в какой день
    /// нагрузка была выше.
    ///
    /// Держится в памяти, а не читается из настроек по требованию. Разбор
    /// четырёхсот дней из JSON стоит недёшево, а спрашивают её на каждый день
    /// недельной полоски и на каждую строку истории — то есть десятки раз за
    /// один экран.
    private(set) var stepHistory: [ActivityDay] = []

    /// Та же история, но прочитанная заново.
    ///
    /// Для резервной копии: её снимают раз в месяц, зато она обязана содержать
    /// всё, что записано к этой минуте, а не то, что лежало в памяти с
    /// последней перестройки.
    var storedActivity: [ActivityDay] { ActivityHistory(defaults: defaults).days }

    /// Записать норму, которая стоит на экране сегодня.
    ///
    /// Прошедший день до сих пор получал свою норму задним числом: вечером
    /// `lockPastGoals` считал её заново — и считал **сегодняшним** числом.
    /// А `dailyGoal` меняется сам, вслед за измеренным расходом. В итоге день,
    /// прожитый с нормой 2822, назавтра показывал 2492, и съеденное ровно в
    /// норму превращалось в перебор на триста килокалорий.
    ///
    /// Поэтому норма дня записывается, пока день идёт: на экране и в истории
    /// должно стоять одно и то же число. Запись обновляется на каждой
    /// перестройке — к полуночи в ней останется то, что человек видел
    /// последним.
    private func rememberTodaysGoal(_ goal: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        if let existing = goalRecords.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            guard existing.goal != goal else { return }
            existing.goal = goal
        } else {
            let record = GoalRecord(date: today, goal: goal)
            context.insert(record)
            goalRecords = (goalRecords + [record]).sorted { $0.date < $1.date }
        }
        goalsByDay[today] = goal
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
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
        BodyBridge.publish(profile: profile, measurement: latestMeasurement)
        if syncDailyGoal { setGoalSource(.plan) }
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

    /// Принять пересчёт с экрана плана: «ставить N ккал/день».
    ///
    /// Запоминаем не только число, но и то, откуда оно: дальше норма пойдёт
    /// за расходом по этому же правилу, а не вернётся к плановой.
    func acceptRecalibratedGoal(_ calories: Int) {
        setGoalSource(.recalibrated)
        defaults.set(Date(), forKey: Keys.goalAgreedAt)
        defaults.removeObject(forKey: Keys.goalProposal)
        dailyGoal = calories
    }

    /// Своё число вместо расчётного — из профиля.
    func setManualGoal(_ calories: Int) {
        setGoalSource(.manual)
        defaults.set(Date(), forKey: Keys.goalAgreedAt)
        defaults.removeObject(forKey: Keys.goalProposal)
        dailyGoal = calories
    }

    /// Запускает план — считает точную дневную норму под срок/целевой вес и делает её текущей целью.
    ///
    /// Гейт премиума живёт здесь, а не только в UI: раньше единственной защитой была
    /// проверка `isPremium` в тулбаре профиля, и любой новый экран мог случайно выдать
    /// платную фичу бесплатно. Уже сохранённый план продолжает работать — отбирать
    /// у пользователя то, что он настроил, мы не будем.
    func startPlan(_ newPlan: Plan, remembering: Bool = true) {
        guard isPremium else {
            logger.warning("startPlan вызван без активного премиума — игнорируем")
            return
        }
        // Запоминаем, что было до правки.
        //
        // Предложения с экрана плана переписывают и срок, и цель, и норму
        // калорий разом — а понимает человек это через неделю, глядя на
        // съехавшие числа. Один шаг назад стоит дёшево и возвращает всё
        // сразу: план, цель и норму.
        if remembering, let previous = plan, previous != newPlan,
           let data = try? JSONEncoder().encode(previous) {
            defaults.set(data, forKey: Keys.previousPlan)
            defaults.set(Date(), forKey: Keys.previousPlanDate)
        }
        plan = newPlan
        if let data = try? JSONEncoder().encode(newPlan) {
            defaults.set(data, forKey: Keys.plan)
        }
        // Цель считается от расхода, а сам профиль тут не нужен — важно лишь,
        // что он есть: без него считать не от чего.
        if profile != nil {
            // Новый план — новый договор: прежний принятый пересчёт к нему
            // отношения не имеет.
            setGoalSource(.plan)
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
                grams: item.grams, date: item.date,
                components: item.components ?? []))
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
            food.micronutrientsAreEstimated = item.micronutrientsAreEstimated ?? false
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
        if let steps = backup.steps { ActivityHistory(defaults: defaults).replace(with: steps) }

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
                              today: now,
                              brief: ExplanationSettings.shared.level == .expert)
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
    /// Сколько ждать между недельными обзорами.
    static let reviewIntervalDays = 7
    /// Меньше этого норму не пересматриваем: пятьдесят килокалорий в день —
    /// это полста граммов веса в неделю, то есть меньше, чем шумит тренд.
    static let meaningfulGoalChange = 50

    /// Норму хоть раз подтверждали вручную — значит дальше её меняют только с
    /// согласия.
    var goalWasAgreed: Bool { defaults.object(forKey: Keys.goalAgreedAt) is Date }

    /// Когда норму согласовали в последний раз.
    var goalAgreedAt: Date? { defaults.object(forKey: Keys.goalAgreedAt) as? Date }

    /// Отложенный пересчёт: число, которое приложение предлагает поставить.
    var proposedGoal: Int? {
        guard let value = defaults.object(forKey: Keys.goalProposal) as? Int, value != dailyGoal else { return nil }
        return value
    }

    /// Пора ли подводить недельный итог: прошла неделя с прошлого раза и есть
    /// что обсудить.
    var reviewIsDue: Bool {
        guard let proposedGoal, abs(proposedGoal - dailyGoal) >= Self.meaningfulGoalChange else { return false }
        guard let agreed = goalAgreedAt else { return true }
        return Date().timeIntervalSince(agreed) >= Double(Self.reviewIntervalDays) * 86_400
    }

    func proposeGoalChange(plan: Plan) {
        let target = dailyGoalSource == .recalibrated
            ? (recalibratedGoal() ?? plan.dailyCalorieTarget(for: Date(), tdee: workingTDEE))
            : plan.dailyCalorieTarget(for: Date(), tdee: workingTDEE)
        if abs(target - dailyGoal) >= Self.meaningfulGoalChange {
            defaults.set(target, forKey: Keys.goalProposal)
        } else {
            defaults.removeObject(forKey: Keys.goalProposal)
        }
    }

    /// Принять предложенную норму — и считать её согласованной.
    func acceptProposedGoal() {
        guard let proposedGoal else { return }
        defaults.removeObject(forKey: Keys.goalProposal)
        defaults.set(Date(), forKey: Keys.goalAgreedAt)
        dailyGoal = proposedGoal
    }

    /// Оставить как есть: до следующего обзора число не трогаем.
    func keepCurrentGoal() {
        defaults.removeObject(forKey: Keys.goalProposal)
        defaults.set(Date(), forKey: Keys.goalAgreedAt)
        rebuildCaches()
    }

    /// Сколько дней предлагаем вернуться к прежнему плану.
    ///
    /// Неделя: дальше это уже не «отменить правку», а смена плана задним
    /// числом, и делать её надо осознанно, в редакторе.
    static let planRevertWindowDays = 7

    /// План до последней правки — пока предложение вернуться ещё в силе.
    var revertablePlan: Plan? {
        guard let data = defaults.data(forKey: Keys.previousPlan),
              let changed = defaults.object(forKey: Keys.previousPlanDate) as? Date,
              Date().timeIntervalSince(changed) < Double(Self.planRevertWindowDays) * 86_400,
              let previous = try? JSONDecoder().decode(Plan.self, from: data),
              previous != plan else { return nil }
        return previous
    }

    /// Вернуть план, каким он был до последней правки, вместе с нормой.
    func revertPlan() {
        guard let previous = revertablePlan else { return }
        defaults.removeObject(forKey: Keys.previousPlan)
        defaults.removeObject(forKey: Keys.previousPlanDate)
        // Без запоминания: иначе отмена сама станет правкой, которую
        // предложат отменить, и кнопка начнёт переключать план туда-сюда.
        startPlan(previous, remembering: false)
    }

    func reschedulePlan(to newEndDate: Date) {
        guard let plan else { return }
        startPlan(plan.rescheduled(toEnd: newEndDate))
    }

    func add(name: String, calories: Int, macros: Macros = Macros(protein: 0, fat: 0, carbs: 0), grams: Double? = nil,
             date: Date = Date(), components: [EntryComponent] = []) {
        let entry = FoodEntry(name: name, calories: calories, macros: macros, grams: grams, date: date,
                              components: components)
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

    func updateEntry(_ entry: FoodEntry, name: String, calories: Int, macros: Macros, grams: Double?, date: Date,
                     components: [EntryComponent]? = nil) {
        entry.name = name
        entry.calories = calories
        entry.macros = macros
        entry.grams = grams
        entry.date = date
        // nil — правка не знает про состав (меняли калории руками), и трогать
        // его нельзя: иначе правка веса стирала бы, из чего собран приём.
        if let components { entry.components = components }
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        entries.sort { $0.date > $1.date }
        rebuildCaches()
        lockPastGoals()
    }

    func addCustomFood(name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double, category: FoodCategory = .other, defaultGrams: Double = 100, micronutrients: Micronutrients = Micronutrients(), catalogID: Int? = nil, micronutrientsAreEstimated: Bool = false) {
        let food = FoodItem(name: name, caloriesPer100g: caloriesPer100g, protein: protein, fat: fat, carbs: carbs, defaultGrams: defaultGrams, category: category)
        if !micronutrients.isEmpty { food.micronutrients = micronutrients }
        food.catalogID = catalogID
        food.micronutrientsAreEstimated = micronutrientsAreEstimated
        food.updatedAt = Date()
        context.insert(food)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods = (customFoods + [food]).sorted { $0.name < $1.name }
        rebuildCaches()
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
                      catalogID: food.catalogID,
                      micronutrientsAreEstimated: food.micronutrientsAreEstimated)
    }

    func deleteCustomFood(_ food: FoodItem) {
        context.delete(food)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods.removeAll { $0.id == food.id }
        rebuildCaches()
    }

    func updateCustomFood(_ food: FoodItem, name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double, category: FoodCategory = .other, defaultGrams: Double = 100, micronutrients: Micronutrients = Micronutrients(), catalogID: Int? = nil, micronutrientsAreEstimated: Bool = false) {
        let previousName = food.name
        food.micronutrients = micronutrients
        food.catalogID = catalogID
        food.micronutrientsAreEstimated = micronutrientsAreEstimated
        food.updatedAt = Date()
        food.defaultGrams = defaultGrams
        food.foodCategory = category
        food.name = name
        food.caloriesPer100g = caloriesPer100g
        food.protein = protein
        food.fat = fat
        food.carbs = carbs
        propagate(foodNamed: previousName, renamedTo: name)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods.sort { $0.name < $1.name }
        rebuildCaches()
    }

    /// Сохранить правку своего продукта и пересобрать то, что из него
    /// считается. Нужно там, где меняется одно поле и городить ради него
    /// полный `updateCustomFood` с десятком аргументов незачем.
    func persistCustomFoods() {
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods.sort { $0.name < $1.name }
        rebuildCaches()
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

    /// Сохранить правку блюда и пересобрать то, что из него считается.
    /// Для случаев, где меняется одно поле — например, партия.
    func persistDishes() {
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        rebuildCaches()
    }

    func updateDish(_ dish: Dish, name: String, ingredients: [DishIngredient], servingGrams: Double = 0) {
        let previousName = dish.name
        dish.name = name
        dish.ingredients = ingredients
        dish.defaultServingGrams = servingGrams
        dish.updatedAt = Date()
        propagate(dishNamed: previousName, renamedTo: name)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        rebuildCaches()
    }

    func deleteDish(_ dish: Dish) {
        bakeCompositionIntoEntries(of: dish)
        context.delete(dish)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        dishes.removeAll { $0.id == dish.id }
        rebuildCaches()
    }

    /// Впечатать состав блюда в записи, где его ели, — перед тем как удалить.
    ///
    /// Съеденное связано с блюдом по имени: по нему запись берёт витамины,
    /// категории и свежие цифры, когда блюдо правят. После удаления имя
    /// перестаёт на что-либо указывать, и запись остаётся числом без состава:
    /// борщ, съеденный в мае, теряет и овощи, и мясо, хотя человек их съел.
    ///
    /// Поэтому состав переносится в саму запись, пересчитанный на съеденную
    /// массу. Записи «просто 300 ккал», где граммов нет, не трогаем —
    /// пересчитывать нечего.
    private func bakeCompositionIntoEntries(of dish: Dish) {
        let batch = dish.totalGrams
        guard batch > 0, !dish.ingredients.isEmpty else { return }

        func parts(forEaten grams: Double) -> [EntryComponent] {
            let share = grams / batch
            return dish.ingredients.map { ingredient in
                let eaten = ingredient.grams * share
                return EntryComponent(
                    name: ingredient.foodName,
                    calories: Int((Double(ingredient.caloriesPer100g) * eaten / 100).rounded()),
                    macros: ingredient.macrosPer100g.portion(grams: eaten),
                    grams: eaten)
            }
        }

        for entry in entries {
            if entry.components.isEmpty {
                guard entry.name == dish.name, let grams = entry.grams, grams > 0 else { continue }
                entry.components = parts(forEaten: grams)
            } else {
                var expanded: [EntryComponent] = []
                var changed = false
                for part in entry.components {
                    guard part.name == dish.name, let grams = part.grams, grams > 0 else {
                        expanded.append(part)
                        continue
                    }
                    expanded.append(contentsOf: parts(forEaten: grams))
                    changed = true
                }
                guard changed else { continue }
                entry.components = expanded
            }
            // Итог пересобираем из частей — как и всюду, где состав меняется:
            // иначе сумма частей и число записи разойдутся на округления.
            entry.calories = entry.components.reduce(0) { $0 + $1.calories }
            entry.macros = entry.components.reduce(Macros.zero) { $0 + $1.macros }
        }
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

    /// Правка продукта или блюда расходится по дереву.
    ///
    /// Блюдо и приём пищи хранят цифры копией, а не ссылкой: так история не
    /// переписывается сама, когда в справочнике что-то поправили. Но у своей
    /// еды всё наоборот — поправил калорийность тунца, значит в банке был
    /// другой тунец, и блюда с ним и приёмы с этими блюдами считались неверно.
    /// Поэтому правка своего продукта проходит по блюдам, где он стоит
    /// ингредиентом, а потом по записям, где стоит он сам или эти блюда.
    ///
    /// Переименование связь не рвёт: ингредиенты и составляющие получают новое
    /// имя вместе со свежими цифрами.
    private func propagate(foodNamed oldName: String, renamedTo newName: String) {
        var touched: Set<String> = [newName]
        for dish in dishes {
            var ingredients = dish.ingredients
            var changed = false
            for index in ingredients.indices where ingredients[index].foodName == oldName {
                guard let food = customFood(named: newName) else { continue }
                ingredients[index].foodName = newName
                ingredients[index].caloriesPer100g = food.caloriesPer100g
                ingredients[index].macrosPer100g = food.macrosPer100g
                changed = true
            }
            guard changed else { continue }
            dish.ingredients = ingredients
            dish.updatedAt = Date()
            touched.insert(dish.name)
        }
        refreshEntries(named: touched, renamedFrom: oldName, to: newName)
    }

    /// То же для блюда: пересчитываем записи, где оно стоит.
    private func propagate(dishNamed oldName: String, renamedTo newName: String) {
        refreshEntries(named: [newName], renamedFrom: oldName, to: newName)
    }

    /// Пересчёт записей дневника по свежим цифрам.
    ///
    /// Считаем от граммов: запись «просто 300 ккал» пересчитывать не из чего,
    /// и её не трогаем.
    private func refreshEntries(named names: Set<String>, renamedFrom oldName: String, to newName: String) {
        for entry in entries {
            var parts = entry.components
            var changed = false

            if !parts.isEmpty {
                for index in parts.indices {
                    let name = parts[index].name == oldName ? newName : parts[index].name
                    guard names.contains(name), let grams = parts[index].grams, grams > 0,
                          let source = perHundredGrams(named: name) else { continue }
                    parts[index] = EntryComponent(
                        name: name,
                        calories: Int((Double(source.calories) * grams / 100).rounded()),
                        macros: source.macros.portion(grams: grams),
                        grams: grams)
                    changed = true
                }
                guard changed else { continue }
                entry.components = parts
                entry.calories = parts.reduce(0) { $0 + $1.calories }
                entry.macros = parts.reduce(Macros.zero) { $0 + $1.macros }
                if entry.name == oldName { entry.name = newName }
                continue
            }

            let name = entry.name == oldName ? newName : entry.name
            guard names.contains(name), let grams = entry.grams, grams > 0,
                  let source = perHundredGrams(named: name) else { continue }
            entry.name = name
            entry.calories = Int((Double(source.calories) * grams / 100).rounded())
            entry.macros = source.macros.portion(grams: grams)
        }
    }

    /// Свежие цифры на сто грамм по имени: свой продукт, блюдо или строка базы.
    ///
    /// Свой продукт первым: он для человека и есть настоящий, а в базе может
    /// лежать тёзка с другими числами.
    func perHundredGrams(named name: String) -> (calories: Int, macros: Macros)? {
        if let food = customFood(named: name) {
            return (food.caloriesPer100g, food.macrosPer100g)
        }
        if let dish = dishes.first(where: { $0.name == name }), dish.totalGrams > 0 {
            return (dish.caloriesPer100g, dish.macrosPer100g)
        }
        if let item = FoodDatabase.items.first(where: { $0.name == name }) {
            return (item.caloriesPer100g, item.macrosPer100g)
        }
        return nil
    }

    private func customFood(named name: String) -> FoodItem? {
        customFoods.first { $0.name == name }
    }

    /// Продукт по имени: свой первым, потом встроенная база.
    ///
    /// Нужен подсказкам «обычно вместе»: в дневнике от продукта остаются
    /// только имя и вес, а строка еды хочет ещё категорию и свойства.
    /// Не нашёлся — значит продукт переименовали или он пришёл из поиска,
    /// и строка просто обойдётся без значков.
    func foodNamed(_ name: String) -> FoodItem? {
        customFood(named: name) ?? FoodDatabase.items.first { $0.name == name }
    }

    private func rebuildRecent() {
        let dishNames = Set(dishes.map(\.name))
        // Продукт по имени: свой перекрывает встроенный — его правили руками,
        // значит он ближе к тому, что человек действительно ест.
        var foodByName: [String: FoodItem] = [:]
        for food in FoodDatabase.items { foodByName[food.name] = food }
        for food in customFoods { foodByName[food.name] = food }

        var seen = Set<String>()
        // Сперва только даты и имена: объекты дорого создавать, а нужны они
        // лишь для верхушки списка.
        var candidates: [(date: Date, food: FoodItem)] = []

        // Записи уже отсортированы по убыванию даты, поэтому первое попавшееся
        // имя — это последний раз, когда продукт ели.
        for entry in entries where !dishNames.contains(entry.name) {
            for component in entry.composition where !seen.contains(component.name) {
                guard let food = recentFood(named: component.name, from: component, in: foodByName)
                else { continue }
                seen.insert(component.name)
                candidates.append((entry.date, food))
            }
            // Записи, сделанные до того, как состав начали хранить: имя у них
            // склеено из названий через запятую, и это всё, что от состава
            // осталось. Разбираем — иначе продукт, который человек ест каждый
            // день внутри приёма, в «Недавнем» не появится никогда.
            guard entry.components.isEmpty else { continue }
            for part in Self.joinedNameParts(entry.name) where !seen.contains(part) {
                guard let food = foodByName[part] else { continue }
                seen.insert(part)
                candidates.append((entry.date, food))
            }
        }

        // Недавнее — это и съеденное, и заведённое: продукт заводят ровно
        // тогда, когда собираются им пользоваться.
        for food in customFoods {
            guard let updatedAt = food.updatedAt, !seen.contains(food.name) else { continue }
            seen.insert(food.name)
            candidates.append((updatedAt, food))
        }

        recentFoods = candidates
            .sorted { $0.date > $1.date }
            .prefix(Self.recentLimit)
            .map(\.food)

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

    /// Чем показать продукт в «Недавнем».
    ///
    /// Сначала настоящий продукт: у него есть категория, состав и порция по
    /// умолчанию. Если такого нет (еду записали разово, руками), собираем
    /// продукт из самой записи — для этого нужен вес, иначе пересчитать на
    /// сто грамм не из чего.
    private func recentFood(named name: String, from component: EntryComponent,
                            in foodByName: [String: FoodItem]) -> FoodItem? {
        if let food = foodByName[name] { return food }
        guard let grams = component.grams, grams > 0 else { return nil }
        let factor = 100 / grams
        return FoodItem(
            name: name,
            caloriesPer100g: Int((Double(component.calories) * factor).rounded()),
            protein: component.protein * factor,
            fat: component.fat * factor,
            carbs: component.carbs * factor,
            defaultGrams: grams,
            // Записи дневника категорию не хранят: без этой строки весь
            // список показывал «Другое».
            category: categoryByFoodName[name] ?? .other
        )
    }

    /// Кому из своих продуктов каталог может одолжить витамины.
    ///
    /// Точное совпадение по названию не считаем: там состав и так подтягивается
    /// сам, и предлагать нечего. Смысл только в непохожих названиях — «Творог
    /// мой» против «Творог 5%», — где связь может найти только поиск.
    ///
    /// Считается заново только когда изменились сами продукты, а не при каждой
    /// перестройке кэшей. Перебор каталога стоит несколько миллисекунд на
    /// продукт, а перестройка идёт на каждую запись еды и на каждое обновление
    /// «Сегодня»: на семидесяти своих продуктах это давало полторы десятых
    /// секунды на жест — ровно то подлагивание, которое видно при потягивании
    /// списка вниз. Сами продукты меняются от силы раз в день.
    private func rebuildVitaminOffers() {
        // В отпечаток идёт всё, от чего зависит ответ: имя и категория решают,
        // кого искать, калории и макросы — подойдёт ли донор по цифрам, состав
        // и связь с каталогом — нужно ли вообще предлагать. Блюда тоже: их имена
        // попадают в словарь составов, по которому мы отсеиваем тех, у кого
        // состав и так есть.
        var hasher = Hasher()
        for food in customFoods {
            hasher.combine(food.id)
            hasher.combine(food.name)
            hasher.combine(food.caloriesPer100g)
            hasher.combine(food.protein)
            hasher.combine(food.fat)
            hasher.combine(food.carbs)
            hasher.combine(food.category)
            hasher.combine(food.catalogID)
            hasher.combine(food.micronutrientsData)
        }
        for dish in dishes { hasher.combine(dish.name) }
        let signature = hasher.finalize()
        guard signature != vitaminOffersSignature else { return }
        vitaminOffersSignature = signature

        var offered: Set<UUID> = []
        for food in customFoods {
            guard food.catalogID == nil, food.micronutrients.isEmpty else { continue }
            guard nutrientProfilesByName[food.name] == nil else { continue }
            if !FoodCatalog.donors(forName: food.name, caloriesPer100g: food.caloriesPer100g,
                                   macrosPer100g: food.macrosPer100g,
                                   category: food.foodCategory, limit: 1).isEmpty {
                offered.insert(food.id)
            }
        }
        foodsOfferedVitamins = offered
    }

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
