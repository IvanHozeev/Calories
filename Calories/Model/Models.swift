import Foundation
import SwiftData

struct Macros: Codable, Hashable {
    var protein: Double
    var fat: Double
    var carbs: Double

    static let zero = Macros(protein: 0, fat: 0, carbs: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            carbs: lhs.carbs + rhs.carbs
        )
    }

    func scaled(by grams: Double) -> Macros {
        Macros(
            protein: protein * grams / 100,
            fat: fat * grams / 100,
            carbs: carbs * grams / 100
        )
    }
}

/// Единая точка для всех констант макронутриентов — расчётов и UI.
enum MacroTargets {
    static let fatPerKg: Double = 0.8
    static let carbsMinimum: Double = 130
    static let kcalPerProteinGram: Double = 4
    static let kcalPerFatGram: Double = 9
    static let kcalPerCarbGram: Double = 4
}

/// Категория макронутриента — для поповеров и навигации в MacrosCard.
enum MacroKind: String, Identifiable {
    case protein, fat, carbs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return "Белки"
        case .fat: return "Жиры"
        case .carbs: return "Углеводы"
        }
    }
}

/// Запись о приёме пищи. Модель SwiftData — хранится в настоящей базе данных на диске,
/// не сериализуется целиком при каждом изменении, в отличие от прежнего JSON+UserDefaults.
@Model
final class FoodEntry: Identifiable {
    var id: UUID
    var name: String
    var calories: Int
    var protein: Double
    var fat: Double
    var carbs: Double
    var grams: Double?
    var date: Date

    init(id: UUID = UUID(), name: String, calories: Int, macros: Macros = .zero, grams: Double? = nil, date: Date = Date()) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = macros.protein
        self.fat = macros.fat
        self.carbs = macros.carbs
        self.grams = grams
        self.date = date
    }

    var macros: Macros {
        get { Macros(protein: protein, fat: fat, carbs: carbs) }
        set {
            protein = newValue.protein
            fat = newValue.fat
            carbs = newValue.carbs
        }
    }
}

/// Ингредиент блюда — снапшот БЖУ на момент добавления, чтобы при правке продукта блюдо не ломалось.
struct DishIngredient: Codable, Identifiable {
    var id: UUID = UUID()
    var foodName: String
    var caloriesPer100g: Int
    var macrosPer100g: Macros
    var grams: Double

    var calories: Int { Int((Double(caloriesPer100g) * grams / 100).rounded()) }
    var macros: Macros { macrosPer100g.scaled(by: grams) }
}

/// Пользовательское блюдо — собирается из нескольких продуктов. Модель SwiftData.
@Model
final class Dish: Identifiable {
    var id: UUID
    var name: String
    var ingredientsData: Data
    var createdAt: Date

    init(id: UUID = UUID(), name: String, ingredients: [DishIngredient] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.createdAt = createdAt
    }

    var ingredients: [DishIngredient] {
        get { (try? JSONDecoder().decode([DishIngredient].self, from: ingredientsData)) ?? [] }
        set { ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    var totalMacros: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }
    var totalGrams: Double { ingredients.reduce(0) { $0 + $1.grams } }

    var caloriesPer100g: Int {
        guard totalGrams > 0 else { return 0 }
        return Int((Double(totalCalories) / totalGrams * 100).rounded())
    }

    var macrosPer100g: Macros {
        guard totalGrams > 0 else { return .zero }
        return Macros(
            protein: totalMacros.protein / totalGrams * 100,
            fat: totalMacros.fat / totalGrams * 100,
            carbs: totalMacros.carbs / totalGrams * 100
        )
    }
}

/// Одна позиция в черновике приёма пищи — до нажатия «Сохранить» нигде не хранится.
struct MealItem: Identifiable {
    let id = UUID()
    var name: String
    var calories: Int
    var macros: Macros
    var grams: Double? = nil
}

/// Запись взвешивания. Модель SwiftData.
@Model
final class WeightEntry: Identifiable {
    var id: UUID
    var weightKg: Double
    var date: Date

    init(id: UUID = UUID(), weightKg: Double, date: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.date = date
    }
}

/// Зафиксированная цель по калориям на конкретный (уже прошедший) день. Как только день
/// перестаёт быть сегодняшним, для него один раз записывается снапшот — дальше правки
/// профиля/плана/цикла на него уже не влияют. Модель SwiftData.
@Model
final class GoalRecord: Identifiable {
    var id: UUID
    var date: Date
    var goal: Int

    init(id: UUID = UUID(), date: Date, goal: Int) {
        self.id = id
        self.date = date
        self.goal = goal
    }
}

/// Сводка по одному дню — вычисляется на лету из записей, не хранится отдельно.
struct DaySummary: Identifiable {
    let date: Date
    let entries: [FoodEntry]
    let goal: Int

    var id: Date { date }

    var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    var totalMacros: Macros {
        entries.reduce(Macros.zero) { $0 + $1.macros }
    }

    var difference: Int {
        totalCalories - goal
    }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Мужской"
        case .female: return "Женский"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return "Минимальная"
        case .light: return "Лёгкая"
        case .moderate: return "Средняя"
        case .active: return "Высокая"
        case .veryActive: return "Очень высокая"
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary: return "Сидячая работа, почти нет тренировок"
        case .light: return "1–3 тренировки в неделю"
        case .moderate: return "3–5 тренировок в неделю"
        case .active: return "6–7 тренировок в неделю"
        case .veryActive: return "Физическая работа + тренировки"
        }
    }

    /// Множитель для расчёта TDEE из BMR.
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case fatLoss, maintenance, muscleGain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fatLoss: return "Снижение веса"
        case .maintenance: return "Поддержание"
        case .muscleGain: return "Набор веса"
        }
    }

    /// Множитель к TDEE для расчёта целевых калорий.
    var calorieMultiplier: Double {
        switch self {
        case .fatLoss: return 0.8
        case .maintenance: return 1.0
        case .muscleGain: return 1.1
        }
    }
}

/// Профиль пользователя для расчёта целевых калорий и белка.
/// Хранится как единственный объект в UserDefaults (JSON) — это одна запись, не список, SwiftData здесь избыточен.
struct UserProfile: Codable, Equatable {
    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: Sex
    var activityLevel: ActivityLevel
    var goal: Goal
    var proteinPerKg: Double

    static let defaultProteinPerKg: Double = 1.7

    /// Базовый метаболизм — формула Миффлина-Сан Жеора.
    var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Суточный расход энергии с учётом активности.
    var tdee: Double {
        bmr * activityLevel.multiplier
    }

    /// Целевые калории с учётом цели (дефицит/поддержание/профицит).
    var calorieTarget: Int {
        Int((tdee * goal.calorieMultiplier).rounded())
    }

    /// Целевой белок в граммах.
    var proteinTargetGrams: Double {
        proteinPerKg * weightKg
    }
}

/// Выбор дней выходных для недельного цикла калорий.
/// Пн=0…Вс=6; смещения в каждом случае суммируются в 0, среднее остаётся неизменным.
enum WeekendStyle: String, Codable, CaseIterable, Identifiable {
    case satSun   // стандартный мир: Сб+Вс
    case friSat   // Израиль: Пт+Сб

    var id: String { rawValue }

    var title: String {
        switch self {
        case .satSun: return "Сб — Вс"
        case .friSat: return "Пт — Сб (Израиль)"
        }
    }

    /// Смещения от среднего по дням Пн=0…Вс=6.
    /// Сумма = 0; рабочие дни ниже нормы, выходные — рефид.
    var cycleOffsets: [Double] {
        switch self {
        case .satSun: return [-0.08, -0.08, -0.12, -0.08, -0.08, 0.14, 0.30]
        case .friSat: return [-0.08, -0.08, -0.12, -0.08, 0.30, 0.14, -0.08]
        }
    }
}

/// Персональный план: срок в неделях и целевой вес, с точным расчётом дневной нормы калорий
/// (в отличие от фиксированного множителя calorieMultiplier у Goal). Одна активная запись —
/// хранится в UserDefaults (JSON), как и профиль.
struct Plan: Codable, Equatable {
    var startDate: Date
    var durationWeeks: Int
    var startWeightKg: Double
    var targetWeightKg: Double
    /// Автоматический недельный цикл калорий вокруг среднего плана — типичная практика
    /// бодибилдеров (меньше калорий в будни, рефид на выходных). Среднее за неделю
    /// остаётся точно равно dailyCalorieTarget — меняется только распределение по дням.
    var cyclingEnabled: Bool = false
    var weekendStyle: WeekendStyle = .satSun

    init(startDate: Date, durationWeeks: Int, startWeightKg: Double, targetWeightKg: Double, cyclingEnabled: Bool = false, weekendStyle: WeekendStyle = .satSun) {
        self.startDate = startDate
        self.durationWeeks = durationWeeks
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.cyclingEnabled = cyclingEnabled
        self.weekendStyle = weekendStyle
    }

    private enum CodingKeys: String, CodingKey {
        case startDate, durationWeeks, startWeightKg, targetWeightKg, cyclingEnabled, weekendStyle
    }

    // Явный init(from:), чтобы уже сохранённые планы не переставали декодироваться —
    // отсутствующие поля трактуются как дефолтные значения.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decode(Date.self, forKey: .startDate)
        durationWeeks = try container.decode(Int.self, forKey: .durationWeeks)
        startWeightKg = try container.decode(Double.self, forKey: .startWeightKg)
        targetWeightKg = try container.decode(Double.self, forKey: .targetWeightKg)
        cyclingEnabled = try container.decodeIfPresent(Bool.self, forKey: .cyclingEnabled) ?? false
        weekendStyle = try container.decodeIfPresent(WeekendStyle.self, forKey: .weekendStyle) ?? .satSun
    }

    /// Грубое общепринятое приближение: ~7700 ккал на 1 кг жировой массы.
    static let kcalPerKg: Double = 7700

    private static func mondayBasedWeekdayIndex(for date: Date) -> Int {
        // Calendar.weekday: 1=Вс … 7=Сб. Приводим к Пн=0 … Вс=6.
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    var title: String {
        if targetWeightKg < startWeightKg { return "Снижение веса" }
        if targetWeightKg > startWeightKg { return "Набор веса" }
        return "Поддержание веса"
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: durationWeeks * 7, to: startDate) ?? startDate
    }

    var totalWeightChangeKg: Double {
        targetWeightKg - startWeightKg
    }

    var weeklyRateKg: Double {
        guard durationWeeks > 0 else { return 0 }
        return totalWeightChangeKg / Double(durationWeeks)
    }

    /// Суточная поправка к TDEE (отрицательная — дефицит, положительная — профицит).
    var dailyCalorieDelta: Double {
        let totalDays = Double(durationWeeks * 7)
        guard totalDays > 0 else { return 0 }
        return (totalWeightChangeKg * Self.kcalPerKg) / totalDays
    }

    /// Средняя дневная норма — без учёта цикла.
    func dailyCalorieTarget(tdee: Double) -> Int {
        Int((tdee + dailyCalorieDelta).rounded())
    }

    /// Норма на конкретную дату — с учётом недельного цикла, если он включён.
    func calorieTarget(for date: Date, tdee: Double) -> Int {
        let base = Double(dailyCalorieTarget(tdee: tdee))
        guard cyclingEnabled else { return Int(base.rounded()) }
        let offset = weekendStyle.cycleOffsets[Self.mondayBasedWeekdayIndex(for: date)]
        return Int((base * (1 + offset)).rounded())
    }

    /// Раскладка нормы по дням недели (Пн…Вс) — для превью в UI.
    func weeklyCalorieBreakdown(tdee: Double) -> [(label: String, calories: Int)] {
        let labels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        let base = Double(dailyCalorieTarget(tdee: tdee))
        return weekendStyle.cycleOffsets.enumerated().map { index, offset in
            (labels[index], Int((base * (1 + offset)).rounded()))
        }
    }

    /// Свыше ~1% веса в неделю большинство источников считает агрессивным темпом.
    func isAggressivePace(relativeToWeightKg weightKg: Double) -> Bool {
        guard weightKg > 0 else { return false }
        return abs(weeklyRateKg) / weightKg * 100 > 1.0
    }

    var progress: Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(max(Date().timeIntervalSince(startDate) / total, 0), 1)
    }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }
}

enum PlanStatus {
    case insufficientData
    case onTrack
    case ahead
    case behind
}

/// Сверка факта (по журналу взвешиваний) с линейным прогнозом плана.
/// Не хранится — считается на лету в CalorieStore.planAdherence().
struct PlanAdherence {
    let expectedWeightToday: Double
    let actualWeightToday: Double?
    let observedWeeklyRateKg: Double?
    let projectedEndDate: Date?
    let recalibratedDailyCalories: Int?
    let status: PlanStatus

    var deviationKg: Double? {
        guard let actualWeightToday else { return nil }
        return actualWeightToday - expectedWeightToday
    }
}
