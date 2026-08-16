import Foundation
import SwiftData
import Combine

final class CalorieStore: ObservableObject {
    private let context: ModelContext

    @Published private(set) var entries: [FoodEntry] = []
    @Published private(set) var customFoods: [FoodItem] = []
    @Published private(set) var dishes: [Dish] = []
    @Published private(set) var weightEntries: [WeightEntry] = []
    @Published private(set) var goalRecords: [GoalRecord] = []
    @Published var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: Keys.goal) }
    }
    @Published private(set) var profile: UserProfile?
    @Published private(set) var plan: Plan?
    @Published var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: Keys.premium) }
    }

    // Кэшированные производные — перестраиваются в rebuildCaches() после каждого изменения данных
    @Published private(set) var todayEntries: [FoodEntry] = []
    @Published private(set) var consumedToday: Int = 0
    @Published private(set) var macrosToday: Macros = .zero
    @Published private(set) var days: [DaySummary] = []
    @Published private(set) var pastDays: [DaySummary] = []
    @Published private(set) var lastSevenDays: [DaySummary] = []
    @Published private(set) var historyDays: [DaySummary] = []
    @Published private(set) var hasWeighedToday: Bool = false
    @Published private(set) var adherence: PlanAdherence?
    @Published private(set) var streak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var loggingStreak: Int = 0

    // O(1) словари для быстрого поиска
    private var entriesByDay: [Date: [FoodEntry]] = [:]
    private var goalsByDay: [Date: Int] = [:]

    @Published private(set) var recentFoodNames: [String] = []

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
    }

    /// Завершает план и возвращает дневную цель к обычному расчёту по профилю.
    func cancelPlan() {
        plan = nil
        UserDefaults.standard.removeObject(forKey: Keys.plan)
        if let profile {
            dailyGoal = profile.calorieTarget
        }
    }

    /// Сдвигает срок плана (сохраняя дату старта, начальный и целевой вес).
    func extendPlan(to newEndDate: Date) {
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
        let entryDates = Set(entries.map { Calendar.current.startOfDay(for: $0.date) })
        let datesToLock = entryDates.subtracting(goalsByDay.keys).filter { $0 < today }
        guard !datesToLock.isEmpty else { return }

        var newRecords: [GoalRecord] = []
        for date in datesToLock {
            let record = GoalRecord(date: date, goal: effectiveGoal(for: date))
            context.insert(record)
            newRecords.append(record)
        }
        try? context.save()
        goalRecords = (goalRecords + newRecords).sorted { $0.date < $1.date }
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

    /// Цель на сегодня — то, что показывается в кольце/статистике.
    var todayGoal: Int {
        effectiveGoal(for: Date())
    }

    var remaining: Int {
        todayGoal - consumedToday
    }

    var progress: Double {
        guard todayGoal > 0 else { return 0 }
        return min(Double(consumedToday) / Double(todayGoal), 1.0)
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

    func add(name: String, calories: Int, macros: Macros = .zero, grams: Double? = nil, date: Date = Date()) {
        let entry = FoodEntry(name: name, calories: calories, macros: macros, grams: grams, date: date)
        context.insert(entry)
        save()
    }

    func delete(entry: FoodEntry) {
        context.delete(entry)
        save()
    }

    func updateEntry(_ entry: FoodEntry, name: String, calories: Int, macros: Macros, grams: Double?, date: Date) {
        entry.name = name
        entry.calories = calories
        entry.macros = macros
        entry.grams = grams
        entry.date = date
        save()
    }

    func addCustomFood(name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double) {
        let food = FoodItem(name: name, caloriesPer100g: caloriesPer100g, protein: protein, fat: fat, carbs: carbs)
        context.insert(food)
        save()
    }

    func deleteCustomFood(_ food: FoodItem) {
        context.delete(food)
        save()
    }

    func updateCustomFood(_ food: FoodItem, name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double) {
        food.name = name
        food.caloriesPer100g = caloriesPer100g
        food.protein = protein
        food.fat = fat
        food.carbs = carbs
        save()
    }

    func addDish(name: String, ingredients: [DishIngredient]) {
        let dish = Dish(name: name, ingredients: ingredients)
        context.insert(dish)
        save()
    }

    func updateDish(_ dish: Dish, name: String, ingredients: [DishIngredient]) {
        dish.name = name
        dish.ingredients = ingredients
        save()
    }

    func deleteDish(_ dish: Dish) {
        context.delete(dish)
        save()
    }

    func addWeight(_ kg: Double, date: Date = Date()) {
        let entry = WeightEntry(weightKg: kg, date: date)
        context.insert(entry)
        save()
        if var p = profile {
            p.weightKg = kg
            updateProfile(p, syncDailyGoal: false)
        }
    }

    func deleteWeight(_ entry: WeightEntry) {
        context.delete(entry)
        save()
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
            recalibratedDailyCalories: recalibratedDailyCalories,
            status: status
        )
    }

    private func save() {
        try? context.save()
        refresh()
        lockPastGoals()
    }
}
