import Foundation

/// Витамин или минерал, который приложение умеет считать.
///
/// Список намеренно короткий. Считать имеет смысл только то, по чему у продуктов
/// реально бывают данные и по чему есть общепринятая суточная норма: остальное
/// превратится в колонку прочерков, которая создаёт видимость учёта.
/// Явно nonisolated: проект по умолчанию изолирует типы на главном акторе, а это
/// перечисление без поведения — его читают и из `Micronutrients`, который живёт
/// вне актора, и из фоновых разборов. Данных без состояния изоляция не касается.
nonisolated enum Micronutrient: String, CaseIterable, Identifiable, Codable {
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

    /// Обозначение для значка в строке продукта. У минералов химический символ,
    /// у витаминов буква: и то и другое читается на любом языке, поэтому
    /// переводить тут нечего.
    var symbol: String {
        switch self {
        case .vitaminA:   return "A"
        case .vitaminC:   return "C"
        case .vitaminD:   return "D"
        case .vitaminE:   return "E"
        case .vitaminB6:  return "B6"
        case .vitaminB12: return "B12"
        case .folate:     return "B9"
        case .calcium:    return "Ca"
        case .iron:       return "Fe"
        case .magnesium:  return "Mg"
        case .zinc:       return "Zn"
        case .potassium:  return "K"
        case .sodium:     return "Na"
        case .selenium:   return "Se"
        }
    }

    /// Суточный ориентир для взрослого — привычные Daily Values.
    ///
    /// Единицы те же, что у `unit`. Точности до возраста и пола здесь
    /// намеренно нет: приложение не диетолог, а разброс между «мужчина 30» и
    /// «женщина 30» меньше, чем разброс между тем, что человек съел и что
    /// записал.
    var dailyValue: Double {
        switch self {
        case .vitaminA:   return 900
        case .vitaminC:   return 90
        case .vitaminD:   return 20
        case .vitaminE:   return 15
        case .vitaminB6:  return 1.7
        case .vitaminB12: return 2.4
        case .folate:     return 400
        case .calcium:    return 1300
        case .iron:       return 18
        case .magnesium:  return 420
        case .zinc:       return 11
        case .potassium:  return 4700
        case .sodium:     return 2300
        case .selenium:   return 55
        }
    }

    /// Для натрия это потолок, а не цель. «Недобрал натрия» — бессмыслица, и
    /// показывать его вместе с остальными как недовыполненную норму нельзя:
    /// человек начнёт досаливать еду, чтобы закрыть шкалу.
    var isCeiling: Bool { self == .sodium }

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
/// Явно nonisolated: проект по умолчанию изолирует типы на главном акторе, а этот
/// читается и пишется из аксессоров SwiftData-модели, которые изолированными не
/// являются. Данных без поведения это не касается — трогать их можно откуда угодно.
nonisolated struct Micronutrients: Codable, Equatable {
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

    /// Чем эта порция богата — по убыванию весомости.
    ///
    /// Порог не выдуман: пятая часть суточной нормы на порцию — привычная
    /// граница «хороший источник» на этикетках. Ниже неё отмечать нечего,
    /// потому что следовые количества почти всего есть почти во всём, и значки
    /// превратились бы в шум на каждой строке.
    func notable(inGrams grams: Double, threshold: Double = 0.2) -> [Micronutrient] {
        guard grams > 0, !isEmpty else { return [] }
        let portion = scaled(by: grams)
        return Micronutrient.allCases
            .compactMap { nutrient -> (nutrient: Micronutrient, share: Double)? in
                guard let amount = portion[nutrient] else { return nil }
                let share = amount / nutrient.dailyValue
                return share >= threshold ? (nutrient, share) : nil
            }
            .sorted { $0.share > $1.share }
            .map(\.nutrient)
    }

    static func + (lhs: Micronutrients, rhs: Micronutrients) -> Micronutrients {
        var result = lhs
        for (key, value) in rhs.per100g {
            result.per100g[key, default: 0] += value
        }
        return result
    }
}
