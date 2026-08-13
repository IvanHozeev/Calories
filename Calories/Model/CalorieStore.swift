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

    private enum Keys {
        static let goal = "daily_goal"
        static let profile = "user_profile"
    }

    init(context: ModelContext) {
        self.context = context
        self.dailyGoal = UserDefaults.standard.object(forKey: Keys.goal) as? Int ?? 2000
        self.profile = Self.loadProfile()
        refresh()
    }

    /// Сохраняет профиль и по умолчанию сразу пересчитывает дневную цель по калориям.
    func updateProfile(_ newProfile: UserProfile, syncDailyGoal: Bool = true) {
        profile = newProfile
        if let data = try? JSONEncoder().encode(newProfile) {
            UserDefaults.standard.set(data, forKey: Keys.profile)
        }
        if syncDailyGoal {
            dailyGoal = newProfile.calorieTarget
        }
    }

    private static func loadProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: Keys.profile) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
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

    private func save() {
        try? context.save()
        refresh()
    }
}
