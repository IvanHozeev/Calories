import Foundation
import SwiftData
import Combine

final class CalorieStore: ObservableObject {
    private let context: ModelContext

    @Published private(set) var entries: [FoodEntry] = []
    @Published private(set) var customFoods: [FoodItem] = []
    @Published private(set) var weightEntries: [WeightEntry] = []
    @Published var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: Keys.goal) }
    }
    @Published private(set) var profile: UserProfile?
    @Published private(set) var plan: Plan?
    @Published var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: Keys.premium) }
    }

    private enum Keys {
        static let goal = "daily_goal"
        static let profile = "user_profile"
        static let plan = "active_plan"
        static let premium = "is_premium"
    }

    init(context: ModelContext) {
        self.context = context
        self.dailyGoal = UserDefaults.standard.object(forKey: Keys.goal) as? Int ?? 2000
        self.profile = Self.loadProfile()
        self.plan = Self.loadPlan()
        self.isPremium = UserDefaults.standard.bool(forKey: Keys.premium)
        refresh()
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

    /// Сдвигает срок плана (сохраняя дату старта, начальный и целевой вес) — используется,
    /// когда фактический темп медленнее/быстрее прогноза и план продлевают/сокращают.
    func extendPlan(to newEndDate: Date) {
        guard var updated = plan else { return }
        let days = Calendar.current.dateComponents([.day], from: updated.startDate, to: newEndDate).day ?? updated.durationWeeks * 7
        updated.durationWeeks = max(1, Int((Double(days) / 7).rounded(.up)))
        startPlan(updated)
    }

    private static func loadPlan() -> Plan? {
        guard let data = UserDefaults.standard.data(forKey: Keys.plan) else { return nil }
        return try? JSONDecoder().decode(Plan.self, from: data)
    }

    /// Перечитывает записи и продукты из базы. Вызывается после каждого изменения.
    func refresh() {
        let entryDescriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        entries = (try? context.fetch(entryDescriptor)) ?? []

        let foodDescriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        customFoods = (try? context.fetch(foodDescriptor)) ?? []

        let weightDescriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        weightEntries = (try? context.fetch(weightDescriptor)) ?? []
    }

    var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }
    }

    var consumedToday: Int {
        todayEntries.reduce(0) { $0 + $1.calories }
    }

    var macrosToday: Macros {
        todayEntries.reduce(Macros.zero) { $0 + $1.macros }
    }

    /// Целевой белок в граммах — nil, если профиль ещё не заполнен.
    var proteinTarget: Double? {
        profile?.proteinTargetGrams
    }

    var remaining: Int {
        dailyGoal - consumedToday
    }

    var progress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(consumedToday) / Double(dailyGoal), 1.0)
    }

    /// Все дни, по которым есть записи (включая сегодня), отсортированы от новых к старым.
    var days: [DaySummary] {
        let grouped = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return grouped
            .map { day, entries in
                DaySummary(
                    date: day,
                    entries: entries.sorted { $0.date > $1.date },
                    goal: dailyGoal
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// Прошлые дни, без сегодняшнего.
    var pastDays: [DaySummary] {
        days.filter { !Calendar.current.isDateInToday($0.date) }
    }

    /// Сводка за конкретный день.
    func summary(for date: Date) -> DaySummary {
        let day = Calendar.current.startOfDay(for: date)
        let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
        return DaySummary(date: day, entries: dayEntries, goal: dailyGoal)
    }

    /// Последние N дней (включая сегодня), от старого к новому — для графиков.
    func lastDays(_ count: Int) -> [DaySummary] {
        let calendar = Calendar.current
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return summary(for: date)
        }
    }

    /// Последние 7 дней (включая сегодня), от старого к новому — для графика по неделям.
    var lastSevenDays: [DaySummary] {
        lastDays(7)
    }

    func add(name: String, calories: Int, macros: Macros = .zero, date: Date = Date()) {
        let entry = FoodEntry(name: name, calories: calories, macros: macros, date: date)
        context.insert(entry)
        save()
    }

    func delete(entry: FoodEntry) {
        context.delete(entry)
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

    func addWeight(_ kg: Double, date: Date = Date()) {
        let entry = WeightEntry(weightKg: kg, date: date)
        context.insert(entry)
        save()
    }

    func deleteWeight(_ entry: WeightEntry) {
        context.delete(entry)
        save()
    }

    /// Последняя по дате запись веса.
    var latestWeight: WeightEntry? {
        weightEntries.last
    }

    var hasWeighedToday: Bool {
        weightEntries.contains { Calendar.current.isDateInToday($0.date) }
    }

    /// Записи веса за последние N дней, от старого к новому.
    func weightHistory(lastDays count: Int) -> [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -count, to: Date()) ?? .distantPast
        let cutoffStart = Calendar.current.startOfDay(for: cutoff)
        return weightEntries.filter { $0.date >= cutoffStart }
    }

    /// Сверяет факт по журналу взвешиваний с линейным прогнозом плана. nil, если плана или профиля нет.
    func planAdherence() -> PlanAdherence? {
        guard let plan, let profile else { return nil }

        let totalDays = Double(plan.durationWeeks * 7)
        let elapsedDays = min(max(Date().timeIntervalSince(plan.startDate) / 86400, 0), totalDays)
        let expectedWeightToday = plan.startWeightKg + plan.totalWeightChangeKg * (totalDays > 0 ? elapsedDays / totalDays : 0)

        // Записи веса с начала плана, тренд — среднее по последним до 7 из них (сглаживает суточный шум).
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
        // Нужна минимум неделя данных с начала плана, иначе темп слишком шумный, чтобы на него опираться.
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
    }
}
