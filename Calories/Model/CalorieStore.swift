import Foundation
import SwiftData
import Observation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "CalorieStore")

@Observable
@MainActor
final class CalorieStore {
    private let context: ModelContext

    private(set) var entries: [FoodEntry] = []
    private(set) var customFoods: [FoodItem] = []
    private(set) var dishes: [Dish] = []
    private(set) var weightEntries: [WeightEntry] = []
    private(set) var goalRecords: [GoalRecord] = []
    var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: Keys.goal) }
    }
    private(set) var profile: UserProfile?
    private(set) var plan: Plan?
    var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: Keys.premium) }
    }

    // Кэшированные производные — перестраиваются в rebuildCaches() после каждого изменения данных
    private(set) var todayEntries: [FoodEntry] = []
    private(set) var consumedToday: Int = 0
    private(set) var macrosToday: Macros = .zero
    private(set) var days: [DaySummary] = []
    private(set) var pastDays: [DaySummary] = []
    private(set) var lastSevenDays: [DaySummary] = []
    private(set) var historyDays: [DaySummary] = []
    private(set) var hasWeighedToday: Bool = false
    private(set) var adherence: PlanAdherence?
    private(set) var streak: Int = 0
    private(set) var bestStreak: Int = 0
    private(set) var loggingStreak: Int = 0
    private(set) var streakHistory: [(date: Date, hasEntries: Bool, onGoal: Bool)] = []
    private(set) var groupedTodayEntries: [(period: MealPeriod, entries: [FoodEntry])] = []
    private(set) var adaptedTodayGoal: Int = 0
    private(set) var calorieBankBonus: Int = 0

    // O(1) словари для быстрого поиска
    @ObservationIgnored private var entriesByDay: [Date: [FoodEntry]] = [:]
    @ObservationIgnored private var goalsByDay: [Date: Int] = [:]
    // Кэш: день, на который уже залочены все прошлые цели — повторный вызов внутри дня бесплатен
    @ObservationIgnored private var goalLockedOnDay: Date? = nil

    private(set) var recentFoodNames: [String] = []

    private enum Keys {
        static let goal = "daily_goal"
        static let profile = "user_profile"
        static let plan = "active_plan"
        static let premium = "is_premium"
        static let recentFoods = "recent_food_names"
    }

    init(context: ModelContext) {
        self.context = context
        self.dailyGoal = UserDefaults.standard.object(forKey: Keys.goal) as? Int ?? 2000
        self.profile = Self.loadProfile()
        self.plan = Self.loadPlan()
        self.isPremium = UserDefaults.standard.bool(forKey: Keys.premium)
        self.recentFoodNames = UserDefaults.standard.stringArray(forKey: Keys.recentFoods) ?? []
        refresh()
        lockPastGoals()
    }

    func recordRecentFoods(_ names: [String]) {
        var updated = recentFoodNames
        for name in names.reversed() {
            updated.removeAll { $0 == name }
            updated.insert(name, at: 0)
        }
        recentFoodNames = Array(updated.prefix(20))
        UserDefaults.standard.set(recentFoodNames, forKey: Keys.recentFoods)
    }

    /// Сохраняет профиль и по умолчанию сразу пересчитывает дневную цель по калориям.
    func updateProfile(_ newProfile: UserProfile, syncDailyGoal: Bool = true) {
        profile = newProfile
        if let data = try? JSONEncoder().encode(newProfile) {
            UserDefaults.standard.set(data, forKey: Keys.profile)
        }
        if syncDailyGoal, plan == nil {
            dailyGoal = newProfile.calorieTarget
        }
    }

    private static func loadProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: Keys.profile) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    /// Запускает план — считает точную дневную норму под срок/целевой вес и делает её текущей целью.
    func startPlan(_ newPlan: Plan) {
        plan = newPlan
        if let data = try? JSONEncoder().encode(newPlan) {
            UserDefaults.standard.set(data, forKey: Keys.plan)
        }
        if let profile {
            dailyGoal = newPlan.dailyCalorieTarget(tdee: profile.tdee)
        }
        rebuildCaches()
    }

    /// Завершает план и возвращает дневную цель к обычному расчёту по профилю.
    func cancelPlan() {
        plan = nil
        UserDefaults.standard.removeObject(forKey: Keys.plan)
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

    private static func loadPlan() -> Plan? {
        guard let data = UserDefaults.standard.data(forKey: Keys.plan) else { return nil }
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
        goalsByDay = Dictionary(uniqueKeysWithValues: goalRecords.map {
            (calendar.startOfDay(for: $0.date), $0.goal)
        })
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
        pastDays = allDays.filter { !calendar.isDateInToday($0.date) }

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
        streakHistory = (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today14) else { return nil }
            let dayTotal = (entriesByDay[date] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[date] ?? effectiveGoal(for: date)
            return (date, dayTotal > 0, dayTotal > 0 && dayTotal <= dayGoal)
        }

        let grouped = Dictionary(grouping: todayEntries) { MealPeriod.period(for: $0.date) }
        groupedTodayEntries = MealPeriod.allCases.compactMap { period in
            guard let entries = grouped[period], !entries.isEmpty else { return nil }
            return (period, entries.sorted { $0.date < $1.date })
        }

        let adapted = computeAdaptedTodayGoal()
        adaptedTodayGoal = adapted
        calorieBankBonus = adapted - effectiveGoal(for: Date())

        let groupDefaults = UserDefaults(suiteName: "group.calories.shared")
        groupDefaults?.set(consumedToday, forKey: "widget_consumed_today")
        groupDefaults?.set(adaptedTodayGoal, forKey: "widget_goal_today")
    }

    func goalHistory(days: Int) -> [(date: Date, hasEntries: Bool, onGoal: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayTotal = (entriesByDay[date] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[date] ?? effectiveGoal(for: date)
            return (date, dayTotal > 0, dayTotal > 0 && dayTotal <= dayGoal)
        }
    }

    private func computeStreak() -> (current: Int, best: Int, logging: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // On-goal streak (логирование + попадание в калории)
        var currentStreak = 0
        let todayTotal = (entriesByDay[today] ?? []).reduce(0) { $0 + $1.calories }
        if todayTotal > 0, todayTotal <= (goalsByDay[today] ?? effectiveGoal(for: today)) {
            currentStreak += 1
        }
        var pastDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while true {
            let dayTotal = (entriesByDay[pastDate] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[pastDate] ?? effectiveGoal(for: pastDate)
            guard dayTotal > 0, dayTotal <= dayGoal else { break }
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: pastDate) else { break }
            pastDate = prev
        }

        var best = 0
        var run = 0
        var prevDate: Date? = nil
        for date in entriesByDay.keys.filter({ !calendar.isDateInToday($0) }).sorted() {
            let dayTotal = (entriesByDay[date] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[date] ?? effectiveGoal(for: date)
            if dayTotal > 0, dayTotal <= dayGoal {
                let consecutive = prevDate.map { calendar.date(byAdding: .day, value: 1, to: $0) == date } ?? false
                run = consecutive ? run + 1 : 1
                prevDate = date
                best = max(best, run)
            } else {
                prevDate = nil
                run = 0
            }
        }

        // Logging streak (просто есть записи за день)
        var loggingStreak = 0
        if todayTotal > 0 { loggingStreak += 1 }
        var logDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while true {
            guard (entriesByDay[logDate] ?? []).reduce(0, { $0 + $1.calories }) > 0 else { break }
            loggingStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: logDate) else { break }
            logDate = prev
        }

        return (currentStreak, max(best, currentStreak), loggingStreak)
    }

    /// Эффективная цель на конкретную дату: если активен план с недельным циклом — берём
    /// цифру из цикла на этот день недели, иначе — обычный dailyGoal.
    func effectiveGoal(for date: Date) -> Int {
        if let plan, plan.cyclingEnabled, let profile {
            return plan.calorieTarget(for: date, tdee: profile.tdee)
        }
        return dailyGoal
    }

    /// Зафиксированная цель на дату (из снапшота) — иначе живой расчёт. O(1) через goalsByDay.
    private func goal(for date: Date) -> Int {
        let day = Calendar.current.startOfDay(for: date)
        return goalsByDay[day] ?? effectiveGoal(for: day)
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

    /// Целевой белок в граммах — nil, если профиль ещё не заполнен.
    var proteinTarget: Double? {
        profile?.proteinTargetGrams
    }

    /// Текущий вес — из последнего взвешивания, иначе из профиля.
    var weightKg: Double? {
        latestWeight?.weightKg ?? profile?.weightKg
    }

    /// Минимальная дневная норма жиров исходя из веса.
    var fatTarget: Double? {
        weightKg.map { $0 * MacroTargets.fatPerKg }
    }

    /// Подсказка что добрать на оставшиеся калории: белок → жиры → углеводы.
    var macroSuggestion: String? {
        guard remaining > 0, profile != nil else { return nil }
        let m = macrosToday
        if let pt = proteinTarget, pt > 0, m.protein < pt {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerProteinGram, pt - m.protein).rounded())
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г белка"
        }
        if let ft = fatTarget, ft > 0, m.fat < ft {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerFatGram, ft - m.fat).rounded())
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г жиров"
        }
        if m.carbs < MacroTargets.carbsMinimum {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerCarbGram, MacroTargets.carbsMinimum - m.carbs).rounded())
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г углеводов"
        }
        return nil
    }

    /// Базовая цель на сегодня без поправки банка.
    var todayGoal: Int {
        effectiveGoal(for: Date())
    }

    var remaining: Int {
        adaptedTodayGoal - consumedToday
    }

    var progress: Double {
        guard adaptedTodayGoal > 0 else { return 0 }
        return min(Double(consumedToday) / Double(adaptedTodayGoal), 1.0)
    }

    /// Адаптированная цель с учётом недельного банка калорий.
    /// Если сэкономил раньше на неделе — норма растёт. Если перерасход — снижается.
    private func computeAdaptedTodayGoal() -> Int {
        guard isPremium else { return effectiveGoal(for: Date()) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Respect locale's first weekday (Sun=1 for IL/US, Mon=2 for Europe)
        let daysFromFirst = (weekday - calendar.firstWeekday + 7) % 7

        guard daysFromFirst > 0,
              let weekStart = calendar.date(byAdding: .day, value: -daysFromFirst, to: today) else {
            return effectiveGoal(for: today)
        }

        let remainingDays = 7 - daysFromFirst
        var weeklyGoalPast = 0
        var weeklyConsumedPast = 0

        for offset in 0..<daysFromFirst {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayEntries = entriesByDay[date] ?? []
            guard !dayEntries.isEmpty else { continue }
            weeklyGoalPast += goal(for: date)
            weeklyConsumedPast += dayEntries.reduce(0) { $0 + $1.calories }
        }

        let bank = weeklyGoalPast - weeklyConsumedPast
        let baseGoal = effectiveGoal(for: today)
        let bankPerDay = bank / remainingDays
        let cappedBonus = min(bankPerDay, 500)
        return max(baseGoal + cappedBonus, 1000)
    }

    /// Сводка за конкретный день — O(1) через entriesByDay.
    func summary(for date: Date) -> DaySummary {
        let day = Calendar.current.startOfDay(for: date)
        return DaySummary(date: day, entries: entriesByDay[day] ?? [], goal: goal(for: day))
    }

    /// Последние N дней (включая сегодня), от старого к новому — для графиков.
    func lastDays(_ count: Int) -> [DaySummary] {
        let calendar = Calendar.current
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return summary(for: date)
        }
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

    /// Сверяет факт с линейным прогнозом плана. Возвращает кэшированный результат из adherence.
    func planAdherence() -> PlanAdherence? { adherence }

    private func computePlanAdherence() -> PlanAdherence? {
        guard let plan, let profile else { return nil }

        let totalDays = Double(plan.durationWeeks * 7)
        let elapsedDays = min(max(Date().timeIntervalSince(plan.startDate) / 86400, 0), totalDays)
        let expectedWeightToday = plan.startWeightKg + plan.totalWeightChangeKg * (totalDays > 0 ? elapsedDays / totalDays : 0)

        let relevantEntries = weightEntries.filter { $0.date >= plan.startDate }
        guard relevantEntries.last != nil else {
            return PlanAdherence(
                expectedWeightToday: expectedWeightToday,
                actualWeightToday: nil,
                observedWeeklyRateKg: nil,
                projectedEndDate: nil,
                projectedWeightAtPlanEnd: nil,
                recalibratedDailyCalories: nil,
                status: .insufficientData
            )
        }
        let recentWindow = relevantEntries.suffix(7)
        let actualWeightToday = recentWindow.reduce(0) { $0 + $1.weightKg } / Double(recentWindow.count)

        let elapsedWeeks = elapsedDays / 7
        guard elapsedWeeks >= 1, relevantEntries.count >= 2 else {
            return PlanAdherence(
                expectedWeightToday: expectedWeightToday,
                actualWeightToday: actualWeightToday,
                observedWeeklyRateKg: nil,
                projectedEndDate: nil,
                projectedWeightAtPlanEnd: nil,
                recalibratedDailyCalories: nil,
                status: .insufficientData
            )
        }

        let observedWeeklyRate = (actualWeightToday - plan.startWeightKg) / elapsedWeeks

        var projectedEndDate: Date?
        if observedWeeklyRate != 0 {
            let remainingChange = plan.targetWeightKg - actualWeightToday
            let weeksNeeded = remainingChange / observedWeeklyRate
            if weeksNeeded.isFinite, weeksNeeded > 0 {
                projectedEndDate = Calendar.current.date(byAdding: .day, value: Int((weeksNeeded * 7).rounded()), to: Date())
            }
        }

        let remainingDays = totalDays - elapsedDays
        var recalibratedDailyCalories: Int?
        if remainingDays > 0 {
            let remainingChangeNeeded = plan.targetWeightKg - actualWeightToday
            let dailyDelta = remainingChangeNeeded * Plan.kcalPerKg / remainingDays
            recalibratedDailyCalories = Int((profile.tdee + dailyDelta).rounded())
        }

        let remainingWeeks = remainingDays / 7
        let projectedWeightAtPlanEnd = remainingWeeks > 0
            ? actualWeightToday + observedWeeklyRate * remainingWeeks
            : nil as Double?

        let deviation = actualWeightToday - expectedWeightToday
        let threshold = max(0.3, abs(plan.totalWeightChangeKg) * 0.05)
        let status: PlanStatus
        if abs(deviation) <= threshold {
            status = .onTrack
        } else if (plan.totalWeightChangeKg < 0 && deviation > 0) || (plan.totalWeightChangeKg > 0 && deviation < 0) {
            status = .behind
        } else {
            status = .ahead
        }

        return PlanAdherence(
            expectedWeightToday: expectedWeightToday,
            actualWeightToday: actualWeightToday,
            observedWeeklyRateKg: observedWeeklyRate,
            projectedEndDate: projectedEndDate,
            projectedWeightAtPlanEnd: projectedWeightAtPlanEnd,
            recalibratedDailyCalories: recalibratedDailyCalories,
            status: status
        )
    }

}
