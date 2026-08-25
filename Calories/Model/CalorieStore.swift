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
    var dailyGoal: Int {
        // Кэш обязателен: adaptedTodayGoal (его читает кольцо на «Сегодня») считается только
        // в rebuildCaches(). Без этого цель меняется в графиках, но не в кольце — они расходятся,
        // пока что-нибудь другое не дёрнет пересчёт.
        didSet {
            defaults.set(dailyGoal, forKey: Keys.goal)
            rebuildCaches()
        }
    }
    private(set) var profile: UserProfile?
    private(set) var plan: Plan?
    var isPremium: Bool {
        didSet { defaults.set(isPremium, forKey: Keys.premium) }
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
    private(set) var streak: Int = 0
    private(set) var bestStreak: Int = 0
    private(set) var loggingStreak: Int = 0
    private(set) var proteinStreak: Int = 0
    private(set) var streakHistory: [(date: Date, hasEntries: Bool, onGoal: Bool)] = []
    private(set) var groupedTodayEntries: [(period: MealPeriod, entries: [FoodEntry])] = []
    private(set) var adaptedTodayGoal: Int = 0
    private(set) var calorieBankBonus: Int = 0

    // O(1) словари для быстрого поиска
    @ObservationIgnored private(set) var entriesByDay: [Date: [FoodEntry]] = [:]
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
        static let profile = "user_profile"
        static let plan = "active_plan"
        static let premium = "is_premium"
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
        self.profile = Self.loadProfile(from: defaults)
        self.plan = Self.loadPlan(from: defaults)
        self.isPremium = defaults.bool(forKey: Keys.premium)
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

        let dishDescriptor = FetchDescriptor<Dish>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        dishes = (try? context.fetch(dishDescriptor)) ?? []

        let weightDescriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        weightEntries = (try? context.fetch(weightDescriptor)) ?? []

        let goalDescriptor = FetchDescriptor<GoalRecord>(sortBy: [SortDescriptor(\.date, order: .forward)])
        goalRecords = (try? context.fetch(goalDescriptor)) ?? []

        rebuildCaches()
    }

    private func rebuildCaches() {
        let calendar = Calendar.current

        // Строим O(1)-словари один раз
        entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
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
            let dayTotal = (entriesByDay[date] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[date] ?? effectiveGoal(for: date)
            return (date, dayTotal > 0, dayTotal > 0 && dayTotal <= dayGoal)
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

        let adapted = computeAdaptedTodayGoal()
        adaptedTodayGoal = adapted
        calorieBankBonus = adapted - effectiveGoal(for: Date())

        cachesBuiltForDay = calendar.startOfDay(for: Date())

        groupDefaults?.set(consumedToday, forKey: "widget_consumed_today")
        groupDefaults?.set(adaptedTodayGoal, forKey: "widget_goal_today")
    }

    /// Пересобирает кэши, если с момента последнего пересчёта сменились сутки.
    /// Дёшево, когда день тот же, поэтому вызывать можно на каждую активацию приложения.
    func refreshIfDayChanged() {
        guard Calendar.current.startOfDay(for: Date()) != cachesBuiltForDay else { return }
        refresh()
        lockPastGoals()
    }


    /// Как только день перестаёт быть сегодняшним, фиксирует его текущую эффективную цель
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
        for date in datesToLock {
            let record = GoalRecord(date: date, goal: effectiveGoal(for: date))
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
        if syncDailyGoal, plan == nil {
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
            dailyGoal = newPlan.dailyCalorieTarget(tdee: profile.tdee)
        }
        rebuildCaches()
    }

    /// Завершает план и возвращает дневную цель к обычному расчёту по профилю.
    func cancelPlan() {
        plan = nil
        defaults.removeObject(forKey: Keys.plan)
        if let profile {
            dailyGoal = profile.calorieTarget
        }
        rebuildCaches()
    }

    /// Пересчитывает срок плана под новую дату финиша (в любую сторону).
    func reschedulePlan(to newEndDate: Date) {
        guard var updated = plan else { return }
        let daysCount = Calendar.current.dateComponents([.day], from: updated.startDate, to: newEndDate).day ?? updated.durationWeeks * 7
        updated.durationWeeks = max(1, Int((Double(daysCount) / 7).rounded(.up)))
        startPlan(updated)
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

    func addCustomFood(name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double) {
        let food = FoodItem(name: name, caloriesPer100g: caloriesPer100g, protein: protein, fat: fat, carbs: carbs)
        context.insert(food)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods = (customFoods + [food]).sorted { $0.name < $1.name }
        rebuildCaches()
    }

    func deleteCustomFood(_ food: FoodItem) {
        context.delete(food)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        customFoods.removeAll { $0.id == food.id }
        rebuildCaches()
    }

    func updateCustomFood(_ food: FoodItem, name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double) {
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

    func addDish(name: String, ingredients: [DishIngredient]) {
        let dish = Dish(name: name, ingredients: ingredients)
        context.insert(dish)
        do { try context.save() } catch { logger.error("context.save failed: \(error)") }
        dishes = [dish] + dishes
        rebuildCaches()
    }

    func updateDish(_ dish: Dish, name: String, ingredients: [DishIngredient]) {
        dish.name = name
        dish.ingredients = ingredients
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
    var recentFoods: [FoodItem] {
        let dishNames = Set(dishes.map(\.name))
        var seen = Set<String>()
        var result: [FoodItem] = []
        for entry in entries {
            guard result.count < 8 else { break }
            guard let grams = entry.grams, grams > 0 else { continue }
            guard !dishNames.contains(entry.name), !seen.contains(entry.name) else { continue }
            seen.insert(entry.name)
            let factor = 100 / grams
            result.append(FoodItem(
                name: entry.name,
                caloriesPer100g: Int((Double(entry.calories) * factor).rounded()),
                protein: entry.protein * factor,
                fat: entry.fat * factor,
                carbs: entry.carbs * factor,
                defaultGrams: grams
            ))
        }
        return result
    }

    /// Недавно съеденные блюда — по тем же записям дневника.
    var recentDishes: [Dish] {
        var seen = Set<String>()
        var result: [Dish] = []
        for entry in entries {
            guard result.count < 8 else { break }
            guard !seen.contains(entry.name) else { continue }
            guard let dish = dishes.first(where: { $0.name == entry.name }) else { continue }
            seen.insert(entry.name)
            result.append(dish)
        }
        return result
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
