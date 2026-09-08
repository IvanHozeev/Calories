import Foundation
import SwiftData
import SwiftUI

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
        case .protein: return String(localized: "Белки")
        case .fat: return String(localized: "Жиры")
        case .carbs: return String(localized: "Углеводы")
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
    /// Когда блюдо последний раз правили. Необязательное: у блюд, заведённых
    /// до появления «Недавнего», его нет, и там сойдёт дата создания.
    var updatedAt: Date?

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

    /// Порция по умолчанию. Ноль означает «вся кастрюля»: столько блюдо весит
    /// целиком. Своя порция нужна потому, что готовят обычно на несколько раз,
    /// и каждый раз отматывать от общего веса — лишняя работа.
    var defaultServingGrams: Double = 0

    /// Сколько подставлять в поле массы при добавлении.
    var servingGrams: Double {
        if defaultServingGrams > 0 { return defaultServingGrams }
        return totalGrams > 0 ? totalGrams : 100
    }

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
/// Один день недели глазами макросов: что съедено против того, что было целью.
struct MacroDay: Identifiable {
    let date: Date
    let macros: Macros
    let proteinTarget: Double
    let fatTarget: Double
    let carbsTarget: Double
    let hasEntries: Bool

    var id: Date { date }

    /// Белок засчитан только когда набран целиком: недобор белка на дефиците —
    /// это съеденные мышцы, и «почти» здесь не считается.
    var hitProtein: Bool { hasEntries && macros.protein >= proteinTarget }
}

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
        case .male: return String(localized: "Мужской")
        case .female: return String(localized: "Женский")
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return String(localized: "Минимальная")
        case .light: return String(localized: "Лёгкая")
        case .moderate: return String(localized: "Средняя")
        case .active: return String(localized: "Высокая")
        case .veryActive: return String(localized: "Очень высокая")
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary: return String(localized: "Сидячая работа, почти нет тренировок")
        case .light: return String(localized: "1–3 тренировки в неделю")
        case .moderate: return String(localized: "3–5 тренировок в неделю")
        case .active: return String(localized: "6–7 тренировок в неделю")
        case .veryActive: return String(localized: "Физическая работа + тренировки")
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
        case .fatLoss: return String(localized: "Снижение веса")
        case .maintenance: return String(localized: "Поддержание")
        case .muscleGain: return String(localized: "Набор веса")
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
/// От чего считать норму белка.
///
/// От общего веса — годится всем и не требует ничего, кроме весов. От сухой
/// массы — точнее: при одном весе на 12% и на 25% жира мышц разное количество,
/// а кормить надо мышцы. Требует снятых замеров.
enum ProteinBasis: String, Codable, CaseIterable, Identifiable {
    case bodyweight, leanMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyweight: return String(localized: "От веса")
        case .leanMass:   return String(localized: "От сухой массы")
        }
    }
}

struct UserProfile: Codable, Equatable {
    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: Sex
    var activityLevel: ActivityLevel
    var goal: Goal
    var proteinPerKg: Double
    /// Своё число для сухой массы.
    ///
    /// Отдельное, а не общее с `proteinPerKg`, потому что смысл у них разный:
    /// 2.0 г на кг веса — обычная норма, 2.0 г на кг сухой массы — уже недобор.
    /// Одно число на две основы означало бы, что переключатель молча меняет
    /// норму на четверть.
    var storedProteinPerLeanKg: Double?
    /// Опциональные намеренно: в уже сохранённых профилях этих ключей нет, а
    /// обязательное поле уронило бы декодирование целиком — то есть стёрло бы
    /// человеку профиль.
    var storedProteinBasis: ProteinBasis?
    /// Норма жира на кг веса. Тоже опциональная: до этой настройки её не было,
    /// и в сохранённых профилях ключа нет.
    var storedFatPerKg: Double?

    init(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: Sex,
        activityLevel: ActivityLevel,
        goal: Goal,
        proteinPerKg: Double,
        proteinPerLeanKg: Double? = nil,
        proteinBasis: ProteinBasis = .bodyweight,
        fatPerKg: Double? = nil
    ) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.activityLevel = activityLevel
        self.goal = goal
        self.proteinPerKg = proteinPerKg
        self.storedProteinPerLeanKg = proteinPerLeanKg
        self.storedProteinBasis = proteinBasis
        self.storedFatPerKg = fatPerKg
    }

    var proteinBasis: ProteinBasis {
        get { storedProteinBasis ?? .bodyweight }
        set { storedProteinBasis = newValue }
    }

    var proteinPerLeanKg: Double {
        get { storedProteinPerLeanKg ?? Self.defaultProteinPerLeanKg }
        set { storedProteinPerLeanKg = newValue }
    }

    var fatPerKg: Double {
        get { storedFatPerKg ?? MacroTargets.fatPerKg }
        set { storedFatPerKg = newValue }
    }

    /// Целевой жир в граммах. Считается только от общего веса: гормонам нужен
    /// абсолютный минимум жира, а не доля от сухой массы.
    var fatTargetGrams: Double { fatPerKg * weightKg }

    static let defaultProteinPerKg: Double = 1.7
    /// Выше, чем от общего веса, и это не опечатка: сухой массы меньше, чем веса,
    /// а кормить надо именно её. Диапазон по Хелмсу для сухих атлетов — 2.3–3.1.
    static let defaultProteinPerLeanKg: Double = 2.4

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

    /// Сухая масса. Только по снятым замерам: оценка по ИМТ для этого слишком
    /// груба — она не отличает 77 кг мышц от 77 кг с животом, а вся суть режима
    /// именно в этом различии.
    func leanMassKg(from measurement: BodyMeasurement?) -> Double? {
        guard navyBodyFat(from: measurement) != nil else { return nil }
        let fat = bodyFatPercentage(from: measurement)
        let lean = weightKg * (1 - fat / 100)
        return lean > 0 ? lean : nil
    }

    /// Целевой белок в граммах. Без замеров персональный режим молча падает
    /// обратно на общий вес: лучше считать грубее, чем не считать вовсе.
    func proteinTargetGrams(from measurement: BodyMeasurement?) -> Double {
        switch proteinBasis {
        case .bodyweight:
            return proteinPerKg * weightKg
        case .leanMass:
            guard let lean = leanMassKg(from: measurement) else { return proteinPerKg * weightKg }
            return proteinPerLeanKg * lean
        }
    }

    var bmi: Double {
        let hm = heightCm / 100
        return weightKg / (hm * hm)
    }

    /// Navy-метод (точнее, ±2–3%): требует талию + шею (+ бёдра для женщин).
    ///
    /// Обхваты приходят параметром, а не хранятся в профиле. Раньше хранились — и
    /// разъезжались: экран расчёта строил их из свежих замеров, а отчёт читал
    /// сохранённую копию, из-за чего один и тот же процент жира показывался
    /// двумя разными числами. У величины должен быть один источник.
    func navyBodyFat(from measurement: BodyMeasurement?) -> Double? {
        guard let measurement else { return nil }
        let inputs = measurement.navyInputs(for: sex)
        guard let waist = inputs.waist, let neck = inputs.neck, waist > neck else { return nil }
        let bf: Double
        switch sex {
        case .male:
            bf = 86.010 * log10(waist - neck) - 70.041 * log10(heightCm) + 36.76
        case .female:
            guard let hip = inputs.hip, waist + hip > neck else { return nil }
            bf = 163.205 * log10(waist + hip - neck) - 97.684 * log10(heightCm) - 78.387
        }
        return max(3, min(bf, 60))
    }

    /// % жира: Navy если замеры есть, иначе Дойренберг (BMI-based, ±5%).
    func bodyFatPercentage(from measurement: BodyMeasurement?) -> Double {
        if let navy = navyBodyFat(from: measurement) { return navy }
        let sexFactor: Double = sex == .male ? 1.0 : 0.0
        let bf = 1.20 * bmi + 0.23 * Double(age) - 10.8 * sexFactor - 5.4
        return max(3, min(bf, 60))
    }

    func isNavyMethod(from measurement: BodyMeasurement?) -> Bool {
        navyBodyFat(from: measurement) != nil
    }

    func bodyFatCategory(from measurement: BodyMeasurement?) -> String {
        let bf = bodyFatPercentage(from: measurement)
        switch sex {
        case .male:
            if bf < 6  { return "Незаменимый жир" }
            if bf < 14 { return "Атлетический" }
            if bf < 18 { return "Фитнес" }
            if bf < 25 { return "Норма" }
            return "Выше нормы"
        case .female:
            if bf < 14 { return "Незаменимый жир" }
            if bf < 21 { return "Атлетический" }
            if bf < 25 { return "Фитнес" }
            if bf < 32 { return "Норма" }
            return "Выше нормы"
        }
    }
}

/// Паттерн недельного цикла калорий.
/// Пн=0…Вс=6; смещения в каждом случае суммируются в 0, среднее остаётся неизменным.
enum WeekendStyle: String, Codable, CaseIterable, Identifiable {
    case monTue   // рефид в начале недели: Пн+Вт
    case satSun   // стандартный мир: Сб+Вс
    case friSat   // Израиль: Пт+Сб
    case sunMon   // Израиль: Вс+Пн

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monTue: return String(localized: "Пн — Вт")
        case .satSun: return String(localized: "Сб — Вс")
        case .friSat: return String(localized: "Пт — Сб")
        case .sunMon: return String(localized: "Вс — Пн")
        }
    }

    var subtitle: String {
        switch self {
        case .monTue: return String(localized: "Рефид в начале недели")
        case .satSun: return String(localized: "Рефид на выходных")
        case .friSat: return String(localized: "Рефид на выходных (Израиль)")
        case .sunMon: return String(localized: "Рефид в начале недели (Израиль)")
        }
    }

    /// Смещения от среднего по дням Пн=0…Вс=6.
    /// Сумма = 0; рефид-дни выше нормы, остальные — ниже.
    var cycleOffsets: [Double] {
        switch self {
        case .monTue: return [0.14, 0.30, -0.08, -0.12, -0.08, -0.08, -0.08]
        case .satSun: return [-0.08, -0.08, -0.12, -0.08, -0.08, 0.14, 0.30]
        case .friSat: return [-0.08, -0.08, -0.12, -0.08, 0.30, 0.14, -0.08]
        case .sunMon: return [0.14, -0.08, -0.12, -0.08, -0.08, -0.08, 0.30]
        }
    }
}

/// Зачем идёт фаза плана. Знак темпа задаётся отсюда, а не хранится вместе
/// с числом: «сушка с плюс полпроцента» — противоречие, которое незачем уметь
/// записывать.
enum PlanIntent: String, Codable, CaseIterable, Identifiable {
    case cut
    case maintenance
    case bulk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cut:         return String(localized: "Дефицит")
        case .maintenance: return String(localized: "Поддержание")
        case .bulk:        return String(localized: "Набор")
        }
    }

    var symbol: String {
        switch self {
        case .cut:         return "arrow.down.right"
        case .maintenance: return "equal"
        case .bulk:        return "arrow.up.right"
        }
    }

    /// Куда фаза ведёт вес: −1, 0 или +1.
    var direction: Double {
        switch self {
        case .cut:         return -1
        case .maintenance: return 0
        case .bulk:        return 1
        }
    }

    /// Разумный темп по умолчанию, в процентах массы за неделю.
    ///
    /// У дефицита и набора он разный не для красоты: на сушке 0.7% в неделю —
    /// рабочая середина, а на наборе столько же означает, что большая часть
    /// прибавки будет жиром. Натурал со стажем набирает медленно.
    var defaultWeeklyRatePercent: Double {
        switch self {
        case .cut:         return 0.7
        case .maintenance: return 0
        case .bulk:        return 0.3
        }
    }

    /// Выше этого темпа предупреждаем. Границы разные по той же причине.
    var aggressiveRatePercent: Double {
        switch self {
        case .cut:         return 1.0
        case .maintenance: return 0
        case .bulk:        return 0.5
        }
    }
}

/// Одна фаза плана.
///
/// Темп задаётся в процентах массы за неделю, а не в килограммах. «0.7% в неделю» —
/// одно и то же утверждение и для 70 кг, и для 95, а «0.5 кг в неделю» — два разных.
/// Внутри фазы процент один раз превращается в килограммы по весу на её старте
/// и дальше держится: так фаза остаётся линейной, а пересчёт «от текущего веса»
/// происходит на границе фаз, где ему и место.
struct PlanPhase: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var intent: PlanIntent
    var durationWeeks: Int
    /// Модуль темпа. Знак берётся у намерения.
    var weeklyRatePercent: Double
    /// Сколько недель калории добираются до нормы этой фазы от нормы прошлой.
    ///
    /// Ноль — прыжком в первый же день. Так делать можно, но выход из дефицита
    /// прыжком на пятьсот калорий возвращает гликоген и воду, и весы за три дня
    /// показывают плюс два килограмма, которые к жиру отношения не имеют.
    var rampWeeks: Int = 0

    init(id: UUID = UUID(), intent: PlanIntent, durationWeeks: Int,
         weeklyRatePercent: Double? = nil, rampWeeks: Int = 0) {
        self.id = id
        self.intent = intent
        self.durationWeeks = max(1, durationWeeks)
        self.weeklyRatePercent = abs(weeklyRatePercent ?? intent.defaultWeeklyRatePercent)
        self.rampWeeks = max(0, min(rampWeeks, self.durationWeeks))
    }

    private enum CodingKeys: String, CodingKey {
        case id, intent, durationWeeks, weeklyRatePercent, rampWeeks
    }

    // Явный init(from:): фазы, сохранённые до появления рампы, её не несут.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        intent = try container.decode(PlanIntent.self, forKey: .intent)
        durationWeeks = max(1, try container.decode(Int.self, forKey: .durationWeeks))
        weeklyRatePercent = abs(try container.decode(Double.self, forKey: .weeklyRatePercent))
        rampWeeks = max(0, min(try container.decodeIfPresent(Int.self, forKey: .rampWeeks) ?? 0, durationWeeks))
    }

    /// Темп со знаком, в долях массы за неделю.
    var signedWeeklyRate: Double { intent.direction * weeklyRatePercent / 100 }

    /// Сколько килограммов в неделю при таком весе на старте фазы.
    func weeklyRateKg(fromWeightKg weightKg: Double) -> Double {
        weightKg * signedWeeklyRate
    }

    var isAggressive: Bool {
        intent != .maintenance && weeklyRatePercent > intent.aggressiveRatePercent
    }
}

/// Персональный план: срок в неделях и целевой вес, с точным расчётом дневной нормы калорий
/// (в отличие от фиксированного множителя calorieMultiplier у Goal). Одна активная запись —
/// хранится в UserDefaults (JSON), как и профиль.
struct Plan: Codable, Equatable {
    var startDate: Date
    var startWeightKg: Double
    /// Цепочка фаз. Ради неё всё и затевалось: сушка, выход в поддержание,
    /// набор — это не три отдельных плана, а один, и самое интересное в нём
    /// происходит на стыках.
    ///
    /// Пустой она не бывает: инициализаторы подставляют хотя бы одну фазу.
    var phases: [PlanPhase]
    /// Автоматический недельный цикл калорий вокруг среднего плана — типичная практика
    /// бодибилдеров (меньше калорий в будни, рефид на выходных). Среднее за неделю
    /// остаётся точно равно dailyCalorieTarget — меняется только распределение по дням.
    var cyclingEnabled: Bool = false
    var weekendStyle: WeekendStyle = .satSun

    /// Идущая неделя плана, считая с первой. Упирается в длительность: после
    /// финиша номер расти не должен, иначе «неделя 14 из 12».
    var currentWeek: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return min(max(days / 7 + 1, 1), durationWeeks)
    }

    /// Сколько полных недель осталось после идущей.
    var weeksRemaining: Int { max(durationWeeks - currentWeek, 0) }

    init(startDate: Date, startWeightKg: Double, phases: [PlanPhase],
         cyclingEnabled: Bool = false, weekendStyle: WeekendStyle = .satSun) {
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.phases = phases.isEmpty ? [PlanPhase(intent: .maintenance, durationWeeks: 8)] : phases
        self.cyclingEnabled = cyclingEnabled
        self.weekendStyle = weekendStyle
    }

    /// План из одной фазы, заданной целевым весом.
    ///
    /// Осталась ради экранов, которые пока думают в терминах «из А в Б за N недель»,
    /// и ради старых сохранённых планов. Темп выводится из веса и срока — то есть
    /// ровно обратно тому, как считает цепочка.
    init(startDate: Date, durationWeeks: Int, startWeightKg: Double, targetWeightKg: Double,
         cyclingEnabled: Bool = false, weekendStyle: WeekendStyle = .satSun) {
        let weeks = max(1, durationWeeks)
        let change = targetWeightKg - startWeightKg
        let intent: PlanIntent = change < 0 ? .cut : (change > 0 ? .bulk : .maintenance)
        // Процент от стартового веса: внутри фазы темп в килограммах постоянен,
        // поэтому обратный пересчёт точен и старый план не «поедет».
        let ratePercent = startWeightKg > 0
            ? abs(change) / Double(weeks) / startWeightKg * 100
            : 0
        self.init(startDate: startDate,
                  startWeightKg: startWeightKg,
                  phases: [PlanPhase(intent: intent, durationWeeks: weeks, weeklyRatePercent: ratePercent)],
                  cyclingEnabled: cyclingEnabled,
                  weekendStyle: weekendStyle)
    }

    private enum CodingKeys: String, CodingKey {
        case startDate, durationWeeks, startWeightKg, targetWeightKg, cyclingEnabled, weekendStyle, phases
    }

    // Явный init(from:), чтобы уже сохранённые планы не переставали декодироваться.
    // План до фаз хранил срок и целевой вес — из них собирается фаза из одной
    // штуки, и человек с активной сушкой не обнаружит, что она исчезла.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decode(Date.self, forKey: .startDate)
        startWeightKg = try container.decode(Double.self, forKey: .startWeightKg)
        cyclingEnabled = try container.decodeIfPresent(Bool.self, forKey: .cyclingEnabled) ?? false
        weekendStyle = try container.decodeIfPresent(WeekendStyle.self, forKey: .weekendStyle) ?? .satSun

        if let stored = try container.decodeIfPresent([PlanPhase].self, forKey: .phases), !stored.isEmpty {
            phases = stored
        } else {
            let weeks = max(1, try container.decodeIfPresent(Int.self, forKey: .durationWeeks) ?? 8)
            let target = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg) ?? startWeightKg
            let change = target - startWeightKg
            let intent: PlanIntent = change < 0 ? .cut : (change > 0 ? .bulk : .maintenance)
            let ratePercent = startWeightKg > 0
                ? abs(change) / Double(weeks) / startWeightKg * 100
                : 0
            phases = [PlanPhase(intent: intent, durationWeeks: weeks, weeklyRatePercent: ratePercent)]
        }
    }

    // Пишем и фазы, и старые поля. Старые — не про совместимость назад, её здесь
    // нет: они нужны, чтобы файл резервной копии и экспорт остались читаемыми
    // глазами, где «цель 75 кг» понятнее, чем «дефицит 0.6% двенадцать недель».
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(startWeightKg, forKey: .startWeightKg)
        try container.encode(phases, forKey: .phases)
        try container.encode(cyclingEnabled, forKey: .cyclingEnabled)
        try container.encode(weekendStyle, forKey: .weekendStyle)
        try container.encode(durationWeeks, forKey: .durationWeeks)
        try container.encode(targetWeightKg, forKey: .targetWeightKg)
    }

    /// Грубое общепринятое приближение: ~7700 ккал на 1 кг жировой массы.
    static let kcalPerKg: Double = 7700

    private static func mondayBasedWeekdayIndex(for date: Date) -> Int {
        // Calendar.weekday: 1=Вс … 7=Сб. Приводим к Пн=0 … Вс=6.
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    var title: String {
        // Название по тому, чем план занят большую часть времени: цепочка
        // «сушка — поддержание — набор» не «снижение» и не «набор», и врать
        // одним из них хуже, чем назвать её планом.
        let byIntent = Dictionary(grouping: phases, by: \.intent)
            .mapValues { $0.reduce(0) { $0 + $1.durationWeeks } }
        guard byIntent.count == 1, let only = byIntent.first?.key else {
            return String(localized: "План")
        }
        switch only {
        case .cut:         return String(localized: "Снижение веса")
        case .bulk:        return String(localized: "Набор веса")
        case .maintenance: return String(localized: "Поддержание веса")
        }
    }

    var durationWeeks: Int { phases.reduce(0) { $0 + $1.durationWeeks } }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: durationWeeks * 7, to: startDate) ?? startDate
    }

    /// Дата начала фазы по её индексу.
    func startDate(ofPhaseAt index: Int) -> Date {
        let weeksBefore = phases.prefix(max(0, index)).reduce(0) { $0 + $1.durationWeeks }
        return Calendar.current.date(byAdding: .day, value: weeksBefore * 7, to: startDate) ?? startDate
    }

    /// Вес, с которого фаза стартует. Он же база для её темпа: процент считается
    /// от того, сколько человек весит к началу фазы, а не к началу всего плана.
    func weight(atStartOfPhaseAt index: Int) -> Double {
        var weight = startWeightKg
        for phase in phases.prefix(max(0, index)) {
            weight += phase.weeklyRateKg(fromWeightKg: weight) * Double(phase.durationWeeks)
        }
        return weight
    }

    /// Какая фаза идёт на эту дату. Ничего — если дата вне плана.
    func phaseIndex(on date: Date) -> Int? {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: date).day ?? 0
        guard days >= 0 else { return nil }
        var weeksPassed = 0
        for (index, phase) in phases.enumerated() {
            weeksPassed += phase.durationWeeks
            if days < weeksPassed * 7 { return index }
        }
        return nil
    }

    func phase(on date: Date) -> PlanPhase? {
        phaseIndex(on: date).map { phases[$0] }
    }

    /// Фаза, которая идёт сейчас, — или последняя, если план уже закончился.
    var currentPhase: PlanPhase? {
        phase(on: Date()) ?? phases.last
    }

    /// Куда план приводит вес: считается по цепочке, а не задаётся числом.
    ///
    /// Спрашивать целевой вес у цепочки нельзя: за тридцать недель вперёд его
    /// никто не знает. Знают темп, который готовы держать, — из него и выходит
    /// прогноз, и он честно называется прогнозом.
    var targetWeightKg: Double { weight(atStartOfPhaseAt: phases.count) }

    /// Прогноз веса на дату — по фазам, которые до неё успели пройти.
    func projectedWeight(on date: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: date).day ?? 0
        guard days > 0 else { return startWeightKg }
        var weight = startWeightKg
        var daysLeft = Double(days)
        for phase in phases {
            let phaseDays = Double(phase.durationWeeks * 7)
            let used = min(daysLeft, phaseDays)
            weight += phase.weeklyRateKg(fromWeightKg: weight) * used / 7
            daysLeft -= used
            if daysLeft <= 0 { return weight }
        }
        return weight
    }

    var totalWeightChangeKg: Double {
        targetWeightKg - startWeightKg
    }

    /// Темп идущей фазы в килограммах за неделю. Не средний по плану: средний
    /// у цепочки «сушка — поддержание — набор» близок к нулю и не говорит ничего.
    var weeklyRateKg: Double {
        weeklyRateKg(on: Date())
    }

    func weeklyRateKg(on date: Date) -> Double {
        guard let index = phaseIndex(on: date) ?? (phases.isEmpty ? nil : phases.count - 1) else { return 0 }
        return phases[index].weeklyRateKg(fromWeightKg: weight(atStartOfPhaseAt: index))
    }

    /// Суточная поправка к TDEE (отрицательная — дефицит, положительная — профицит).
    var dailyCalorieDelta: Double { dailyCalorieDelta(on: Date()) }

    func dailyCalorieDelta(on date: Date) -> Double {
        let target = weeklyRateKg(on: date) * Self.kcalPerKg / 7
        guard let index = phaseIndex(on: date), index > 0 else { return target }
        let phase = phases[index]
        guard phase.rampWeeks > 0 else { return target }

        let phaseStart = startDate(ofPhaseAt: index)
        let daysIn = Calendar.current.dateComponents([.day], from: phaseStart, to: date).day ?? 0
        let rampDays = Double(phase.rampWeeks * 7)
        guard Double(daysIn) < rampDays else { return target }

        // Линейно от нормы прошлой фазы к норме этой. Дельта прошлой берётся
        // на её последнем дне: у неё самой могла быть рампа, и начинать
        // переход от её начальной нормы значило бы переходить не оттуда,
        // где человек на самом деле оказался.
        let previousEnd = Calendar.current.date(byAdding: .day, value: -1, to: phaseStart) ?? phaseStart
        let from = weeklyRateKg(on: previousEnd) * Self.kcalPerKg / 7
        let progress = rampDays > 0 ? Double(daysIn) / rampDays : 1
        return from + (target - from) * progress
    }

    /// Устаканивается ли вес после того, как калории подняли.
    ///
    /// После дефицита возвращаются гликоген и вода — это килограмм-другой за
    /// несколько дней, и к жиру он отношения не имеет. Пока это происходит,
    /// судить о плане по весам нельзя: любой вердикт будет про воду.
    func isSettling(on date: Date) -> Bool {
        guard let index = phaseIndex(on: date), index > 0 else { return false }
        let phaseStart = startDate(ofPhaseAt: index)
        let previousEnd = Calendar.current.date(byAdding: .day, value: -1, to: phaseStart) ?? phaseStart
        // Только вверх: переход в дефицит воду не возвращает.
        guard weeklyRateKg(on: date) > weeklyRateKg(on: previousEnd) else { return false }
        let weeks = max(phases[index].rampWeeks, Self.settlingWeeks)
        let daysIn = Calendar.current.dateComponents([.day], from: phaseStart, to: date).day ?? 0
        return daysIn < weeks * 7
    }

    /// Сколько недель весам не верят после подъёма калорий, если рампы нет.
    static let settlingWeeks = 2

    /// Насколько шире допуск по весу, пока он устаканивается.
    /// Полтора килограмма — обычный возврат гликогена и воды после дефицита.
    static let settlingToleranceKg = 1.5

    /// Дневная норма на сегодня — без учёта цикла.
    func dailyCalorieTarget(tdee: Double) -> Int {
        dailyCalorieTarget(for: Date(), tdee: tdee)
    }

    func dailyCalorieTarget(for date: Date, tdee: Double) -> Int {
        Int((tdee + dailyCalorieDelta(on: date)).rounded())
    }

    /// Норма на конкретную дату — с учётом фазы и недельного цикла, если он включён.
    func calorieTarget(for date: Date, tdee: Double) -> Int {
        let base = Double(dailyCalorieTarget(for: date, tdee: tdee))
        guard cyclingEnabled else { return Int(base.rounded()) }
        let offset = weekendStyle.cycleOffsets[Self.mondayBasedWeekdayIndex(for: date)]
        return Int((base * (1 + offset)).rounded())
    }

    /// Раскладка нормы по дням недели (Пн…Вс) — для превью в UI.
    func weeklyCalorieBreakdown(tdee: Double) -> [(label: String, calories: Int)] {
        let cal = Calendar.current
        let labels = Array((1...7).map { i in cal.shortWeekdaySymbols[i % 7] })
        let base = Double(dailyCalorieTarget(tdee: tdee))
        return weekendStyle.cycleOffsets.enumerated().map { index, offset in
            (labels[index], Int((base * (1 + offset)).rounded()))
        }
    }

    /// Есть ли в плане фаза со слишком резким темпом.
    ///
    /// Порог берётся у намерения: процент, рабочий на сушке, на наборе означает,
    /// что большая часть прибавки уйдёт в жир. Один порог на оба был бы не
    /// строгостью, а невнимательностью.
    var hasAggressivePhase: Bool { phases.contains { $0.isAggressive } }

    /// Оставлено ради экранов, считающих в килограммах от веса. Аргумент больше
    /// ни на что не влияет: темп фазы и так задан в процентах массы.
    func isAggressivePace(relativeToWeightKg weightKg: Double) -> Bool {
        hasAggressivePhase
    }

    var progress: Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(max(Date().timeIntervalSince(startDate) / total, 0), 1)
    }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    /// План дошёл до даты финиша.
    ///
    /// До появления этого признака план не заканчивался никогда: неделя упиралась
    /// в потолок, дней оставалось ноль, а дефицит продолжал держаться — восьминедельная
    /// сушка молча превращалась в полугодовую.
    var isFinished: Bool { Date() >= endDate }

    /// План с другой датой финиша.
    ///
    /// Двигается последняя фаза: конец плана — это её конец, и растягивать ради
    /// него сушку в середине цепочки было бы не тем, о чём просили.
    func rescheduled(toEnd newEndDate: Date) -> Plan {
        guard !phases.isEmpty else { return self }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: newEndDate).day ?? 0
        let totalWeeks = max(1, Int((Double(days) / 7).rounded(.up)))
        let weeksBefore = phases.dropLast().reduce(0) { $0 + $1.durationWeeks }
        var updated = self
        updated.phases[phases.count - 1].durationWeeks = max(1, totalWeeks - weeksBefore)
        return updated
    }

    /// План, приводящий к другому весу к той же дате.
    ///
    /// Меняется темп последней фазы, а не срок: просьба «дойти до 74» — это про
    /// то, как быстро идти, а не про то, когда закончить.
    func retargeted(to weightKg: Double) -> Plan {
        guard let last = phases.last else { return self }
        let base = weight(atStartOfPhaseAt: phases.count - 1)
        guard base > 0, last.durationWeeks > 0 else { return self }
        let change = weightKg - base
        let intent: PlanIntent = change < 0 ? .cut : (change > 0 ? .bulk : .maintenance)
        let ratePercent = abs(change) / Double(last.durationWeeks) / base * 100
        var updated = self
        updated.phases[phases.count - 1] = PlanPhase(id: last.id,
                                                     intent: intent,
                                                     durationWeeks: last.durationWeeks,
                                                     weeklyRatePercent: ratePercent)
        return updated
    }
}

/// Из чего состояло изменение веса между двумя сеансами замеров.
///
/// Смысл всей затеи: «минус 6 кг» ничего не говорит натуралу на сушке. Говорит
/// «минус 6 кг, из них жира 5.4, сухой массы 0.6» — то есть работает диета или
/// ты ешь собственные мышцы.
struct CompositionChange {
    let fromDate: Date
    let toDate: Date
    let startWeightKg: Double
    let endWeightKg: Double
    let startFatPercent: Double
    let endFatPercent: Double

    var startFatKg: Double { startWeightKg * startFatPercent / 100 }
    var endFatKg: Double { endWeightKg * endFatPercent / 100 }
    var startLeanKg: Double { startWeightKg - startFatKg }
    var endLeanKg: Double { endWeightKg - endFatKg }

    var weightDeltaKg: Double { endWeightKg - startWeightKg }
    var fatDeltaKg: Double { endFatKg - startFatKg }
    var leanDeltaKg: Double { endLeanKg - startLeanKg }

    /// Насколько метод вообще способен различить.
    ///
    /// У Navy погрешность около ±3% жира, что на 77 кг даёт ±2.3 кг сухой массы.
    /// Объявлять «ты потерял 400 г мышц» внутри этого коридора — врать точностью,
    /// которой нет, поэтому всё, что меньше, честно называется погрешностью.
    var noiseKg: Double { endWeightKg * 0.03 }

    var verdict: CompositionVerdict {
        if abs(leanDeltaKg) <= noiseKg { return .withinNoise }
        return leanDeltaKg < 0 ? .leanLoss : .leanGain
    }
}

/// Что фаза сделала с составом тела — с оглядкой на то, зачем она шла.
///
/// Без намерения вердикт по составу не полон. «Сухая масса держится» на сушке —
/// это успех, а на наборе — провал: набирали как раз её. Прежний вердикт
/// намерения не знал и на неудавшемся наборе честно докладывал, что всё в
/// порядке.
enum PhaseCompositionVerdict {
    /// Фаза сделала то, зачем была.
    case worked
    /// Сделала, но дорого: сушка за счёт мышц, набор в жир.
    case costly
    /// Не сделала ничего — вес не сдвинулся дальше погрешности весов.
    case stalled

    var title: String {
        switch self {
        case .worked:  return String(localized: "Фаза отработала")
        case .costly:  return String(localized: "Отработала дорого")
        case .stalled: return String(localized: "Вес не сдвинулся")
        }
    }

    var icon: String {
        switch self {
        case .worked:  return "checkmark.circle.fill"
        case .costly:  return "exclamationmark.triangle.fill"
        case .stalled: return "pause.circle.fill"
        }
    }
}

extension CompositionChange {
    /// Насколько весы вообще различают изменение трендового веса.
    /// Это не погрешность процента жира — она на порядок больше и живёт
    /// в `noiseKg`, — а просто цена дня на весах.
    static let scaleNoiseKg = 0.5

    /// Какая часть изменения веса пришлась на жир. Ничего, если вес стоит.
    var fatShareOfChange: Double? {
        guard abs(weightDeltaKg) > Self.scaleNoiseKg else { return nil }
        return fatDeltaKg / weightDeltaKg
    }

    func verdict(for intent: PlanIntent) -> PhaseCompositionVerdict {
        let moved = abs(weightDeltaKg) > Self.scaleNoiseKg
        switch intent {
        case .cut:
            if !moved { return .stalled }
            // Мышцы уходят заметнее, чем метод способен наврать, — значит
            // уходят на самом деле.
            return leanDeltaKg < -noiseKg ? .costly : .worked
        case .bulk:
            if !moved { return .stalled }
            if leanDeltaKg > noiseKg { return .worked }
            // Вес вырос, а сухая масса — нет. Это набранный жир, даже если
            // формально изменение сухой укладывается в погрешность.
            return weightDeltaKg > 0 ? .costly : .stalled
        case .maintenance:
            // На поддержании успех — это когда ничего не произошло.
            return moved ? .costly : .worked
        }
    }

    /// Что с этим делать. Текст зависит и от вердикта, и от намерения: «ешь
    /// больше» на сушке и на наборе — противоположные советы.
    func advice(for intent: PlanIntent) -> String {
        switch (intent, verdict(for: intent)) {
        case (.cut, .worked):
            return String(localized: "Вес уходит жиром, сухая масса на месте — так дефицит и должен выглядеть.")
        case (.cut, .costly):
            return String(localized: "Уходит не только жир. Смягчи дефицит или подними норму белка — на сушке чинят это в первую очередь.")
        case (.cut, .stalled):
            return String(localized: "Вес стоит. Либо дефицита нет на самом деле, либо считается не всё съеденное.")
        case (.bulk, .worked):
            return String(localized: "Прибавка идёт сухой массой — темп можно не трогать.")
        case (.bulk, .costly):
            return String(localized: "Прибавка идёт в основном жиром. Сбавь темп: набирать быстрее пола процента в неделю натуралу почти нечем.")
        case (.bulk, .stalled):
            return String(localized: "Вес стоит. Профицита нет — либо норма занижена, либо съедается не столько, сколько записано.")
        case (.maintenance, .worked):
            return String(localized: "Вес держится — поддержание делает ровно то, зачем нужно.")
        case (.maintenance, .costly):
            return String(localized: "Вес поехал. На поддержании это значит, что норма разошлась с фактическим расходом.")
        case (.maintenance, .stalled):
            return String(localized: "Вес держится — поддержание делает ровно то, зачем нужно.")
        }
    }
}

enum CompositionVerdict {
    /// Сухая масса просела заметнее погрешности метода.
    case leanLoss
    /// Сухая масса выросла заметнее погрешности.
    case leanGain
    /// Разница меньше того, что метод различает.
    case withinNoise

    var title: String {
        switch self {
        case .leanLoss:    return String(localized: "Сухая масса просела")
        case .leanGain:    return String(localized: "Сухая масса выросла")
        case .withinNoise: return String(localized: "Сухая масса держится")
        }
    }

    var explanation: String {
        switch self {
        case .leanLoss:
            return String(localized: "Вес уходит не только за счёт жира. Стоит смягчить дефицит или поднять норму белка — на сушке это первое, что чинят.")
        case .leanGain:
            return String(localized: "Редкий и хороший случай: жир уходит, а сухая масса прибавляет. Так бывает у новичков и после долгого перерыва.")
        case .withinNoise:
            return String(localized: "Изменение сухой массы меньше погрешности метода — считай, что она на месте, а вес уходит жиром.")
        }
    }
}

/// С чем план пришёл к финишу.
struct PlanOutcome {
    let plan: Plan
    /// Тренд последних взвешиваний, а не последнее число: вес скачет на килограмм
    /// от воды, и подводить итог по одному утру нечестно.
    let finalWeightKg: Double?

    var changeKg: Double? {
        finalWeightKg.map { $0 - plan.startWeightKg }
    }

    /// Сколько не дошли до цели. Ноль и меньше — цель взята.
    var shortfallKg: Double? {
        guard let finalWeightKg else { return nil }
        let planned = plan.totalWeightChangeKg
        if planned < 0 { return finalWeightKg - plan.targetWeightKg }
        if planned > 0 { return plan.targetWeightKg - finalWeightKg }
        return abs(finalWeightKg - plan.targetWeightKg)
    }

    /// Для поддержания цель считается взятой, если удержались в полукилограмме.
    var reachedTarget: Bool {
        guard let shortfallKg else { return false }
        return plan.totalWeightChangeKg == 0 ? shortfallKg <= 0.5 : shortfallKg <= 0
    }
}

enum PlanStatus {
    case insufficientData
    case onTrack
    case ahead
    case behind
}

/// Чего именно не хватает для расчёта тренда. Нужно, чтобы вместо пассивных серых часов
/// показать пользователю, сколько ещё шагов до появления аналитики.
struct AdherenceDataGap {
    let weighInsLogged: Int
    let weighInsRequired: Int
    let daysUntilTrend: Int

    /// 0…1 — доля собранного, для прогресс-бара.
    var progress: Double {
        let byWeighIns = weighInsRequired > 0
            ? min(Double(weighInsLogged) / Double(weighInsRequired), 1)
            : 1
        let byDays = daysUntilTrend <= 0 ? 1.0 : max(0, Double(7 - daysUntilTrend) / 7)
        return min(byWeighIns, byDays)
    }
}

/// Сверка факта (по журналу взвешиваний) с линейным прогнозом плана.
/// Не хранится — считается на лету в CalorieStore.planAdherence().
struct PlanAdherence {
    let expectedWeightToday: Double
    let actualWeightToday: Double?
    let observedWeeklyRateKg: Double?
    let projectedEndDate: Date?
    let projectedWeightAtPlanEnd: Double?
    let recalibratedDailyCalories: Int?
    let status: PlanStatus
    let dataGap: AdherenceDataGap?
    /// Вес ещё устаканивается после подъёма калорий — судить по нему рано.
    var isSettlingAfterIncrease: Bool = false

    var deviationKg: Double? {
        guard let actualWeightToday else { return nil }
        return actualWeightToday - expectedWeightToday
    }
}

/// Достижение. Считается на лету из стриков — нигде не хранится, поэтому не может
/// рассинхронизироваться с фактическими данными и не требует миграций.
struct Achievement: Identifiable {
    enum Kind: String, CaseIterable {
        case firstWeek, disciplineMaster, proteinMaster, ironWill
    }

    let kind: Kind
    let current: Int
    let target: Int

    var id: String { kind.rawValue }
    var isUnlocked: Bool { current >= target }
    var progress: Double { target > 0 ? min(Double(current) / Double(target), 1) : 0 }

    var title: String {
        switch kind {
        case .firstWeek:        return String(localized: "Первая неделя")
        case .disciplineMaster: return String(localized: "Мастер дисциплины")
        case .proteinMaster:    return String(localized: "Мастер белка")
        case .ironWill:         return String(localized: "Железная воля")
        }
    }

    var requirement: String {
        switch kind {
        case .firstWeek:        return String(localized: "7 дней подряд в пределах дневной нормы калорий.")
        case .disciplineMaster: return String(localized: "14 дней подряд в пределах дневной нормы калорий.")
        case .proteinMaster:    return String(localized: "5 дней подряд закрыта норма белка.")
        case .ironWill:         return String(localized: "30 дней подряд с записями в дневнике — попадание в цель не требуется.")
        }
    }

    var icon: String {
        switch kind {
        case .firstWeek:        return "flame.fill"
        case .disciplineMaster: return "trophy.fill"
        case .proteinMaster:    return "bolt.fill"
        case .ironWill:         return "star.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .firstWeek:        return .orange
        case .disciplineMaster: return .yellow
        case .proteinMaster:    return .blue
        case .ironWill:         return .purple
        }
    }
}
