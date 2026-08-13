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
    var date: Date

    init(id: UUID = UUID(), name: String, calories: Int, macros: Macros = .zero, date: Date = Date()) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = macros.protein
        self.fat = macros.fat
        self.carbs = macros.carbs
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

/// Одна позиция в черновике приёма пищи — до нажатия «Сохранить» нигде не хранится.
struct MealItem: Identifiable {
    let id = UUID()
    var name: String
    var calories: Int
    var macros: Macros
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
        case .fatLoss: return "Потеря жира"
        case .maintenance: return "Поддержание"
        case .muscleGain: return "Набор массы"
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
