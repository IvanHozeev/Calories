import Foundation

/// Витамин или минерал, который приложение умеет считать.
///
/// Список намеренно короткий. Считать имеет смысл только то, по чему у продуктов
/// реально бывают данные и по чему есть общепринятая суточная норма: остальное
/// превратится в колонку прочерков, которая создаёт видимость учёта.
enum Micronutrient: String, CaseIterable, Identifiable, Codable {
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminB6, vitaminB12, folate
    case calcium, iron, magnesium, zinc, potassium, sodium, selenium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vitaminA:   return String(localized: "Витамин A")
        case .vitaminC:   return String(localized: "Витамин C")
        case .vitaminD:   return String(localized: "Витамин D")
        case .vitaminE:   return String(localized: "Витамин E")
        case .vitaminB6:  return String(localized: "Витамин B6")
        case .vitaminB12: return String(localized: "Витамин B12")
        case .folate:     return String(localized: "Фолат")
        case .calcium:    return String(localized: "Кальций")
        case .iron:       return String(localized: "Железо")
        case .magnesium:  return String(localized: "Магний")
        case .zinc:       return String(localized: "Цинк")
        case .potassium:  return String(localized: "Калий")
        case .sodium:     return String(localized: "Натрий")
        case .selenium:   return String(localized: "Селен")
        }
    }

    /// Единица, в которой хранится и показывается количество.
    var unit: String {
        switch self {
        case .vitaminA, .vitaminD, .vitaminB12, .folate, .selenium:
            return String(localized: "мкг")
        case .vitaminC, .vitaminE, .vitaminB6, .calcium, .iron, .magnesium, .zinc, .potassium, .sodium:
            return String(localized: "мг")
        }
    }

    /// Идентификатор нутриента в базе USDA FoodData Central.
    /// Единицы там совпадают с нашими, поэтому пересчёт не нужен.
    var usdaNutrientID: Int {
        switch self {
        case .vitaminA:   return 1106   // Vitamin A, RAE
        case .vitaminC:   return 1162
        case .vitaminD:   return 1114   // Vitamin D (D2 + D3)
        case .vitaminE:   return 1109   // Vitamin E (alpha-tocopherol)
        case .vitaminB6:  return 1175
        case .vitaminB12: return 1178
        case .folate:     return 1177   // Folate, total
        case .calcium:    return 1087
        case .iron:       return 1089
        case .magnesium:  return 1090
        case .zinc:       return 1095
        case .potassium:  return 1092
        case .sodium:     return 1093
        case .selenium:   return 1103
        }
    }
}

/// Микронутриенты на 100 г продукта. Отсутствие вещества в словаре означает
/// «неизвестно», а не «ноль» — разница принципиальная: на нулях приложение
/// насчитало бы дефицит там, где просто нет данных.
struct Micronutrients: Codable, Equatable {
    private(set) var per100g: [String: Double]

    init(_ values: [Micronutrient: Double] = [:]) {
        per100g = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }

    var isEmpty: Bool { per100g.isEmpty }

    subscript(nutrient: Micronutrient) -> Double? {
        per100g[nutrient.rawValue]
    }

    /// Пересчёт на съеденную массу.
    func scaled(by grams: Double) -> Micronutrients {
        var result = Micronutrients()
        result.per100g = per100g.mapValues { $0 * grams / 100 }
        return result
    }

    static func + (lhs: Micronutrients, rhs: Micronutrients) -> Micronutrients {
        var result = lhs
        for (key, value) in rhs.per100g {
            result.per100g[key, default: 0] += value
        }
        return result
    }
}
