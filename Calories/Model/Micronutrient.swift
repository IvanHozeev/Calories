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
    /// Клетчатка идёт первой: она не витамин, но считается так же — по составу
    /// съеденного, — а видеть её хочется рядом с макросами, а не в конце списка.
    case fiber
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminB6, vitaminB12, folate
    case calcium, iron, magnesium, zinc, potassium, sodium, selenium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiber:      return String(localized: "Клетчатка")
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

    /// Можно ли одолжить это вещество похожему продукту.
    ///
    /// Проверено на выгрузке USDA (4016 продуктов с полным составом): у пар,
    /// признанных похожими по категории, калорийности и раскладке макросов,
    /// вещества расходятся очень по-разному.
    ///
    /// Минералы сидят в теле продукта и нагревом не разрушаются — калий, магний,
    /// селен, цинк и железо предсказываются с ошибкой в 1.2–1.3 раза.
    /// Витамины группы B, фолаты, кальций, D, E и клетчатка дают 1.4–1.6 раза:
    /// перенести можно, но это оценка.
    ///
    /// А витамины A и C и натрий переносить нельзя вовсе. Витамин A в животной
    /// еде — готовый ретинол, в растительной — каротин, и его количество зависит
    /// от сорта, а не от макросов; витамин C распадается от нагрева и хранения;
    /// соль добавляет технолог, и в четверти случаев перенос насыпал бы её туда,
    /// где её нет. Ошибка по этим трём — вдвое, и пустое место честнее.
    var transfer: Transfer {
        switch self {
        case .potassium, .magnesium, .selenium, .zinc, .iron: return .direct
        case .fiber, .calcium, .vitaminD, .vitaminE, .vitaminB6, .vitaminB12, .folate: return .estimate
        case .vitaminA, .vitaminC, .sodium: return .never
        }
    }

    enum Transfer {
        /// Переносим молча: у похожей еды столько же.
        case direct
        /// Переносим, но это оценка, а не измерение.
        case estimate
        /// Не переносим: угадать нельзя.
        case never
    }

    /// Во что превращать граммы: Open Food Facts отдаёт состав в граммах, а мы
    /// храним минералы в миллиграммах, а витамины A, D, B12, фолаты и селен —
    /// в микрограммах.
    var gramsMultiplier: Double {
        switch unitScale {
        case .micrograms: return 1_000_000
        case .milligrams: return 1_000
        case .grams: return 1
        }
    }

    /// Больше этого на сто грамм не бывает ни у одной еды.
    ///
    /// Нужен против перепутанных единиц: у части товаров в Open Food Facts
    /// состав вписан на порцию или в других единицах, и тогда «кальций
    /// 40 000 мг» приезжает как правда. Порог щедрый — это сито от чуши, а не
    /// проверка правдоподобия.
    var plausibleMaximumPer100g: Double {
        switch self {
        case .fiber:      return 100
        case .vitaminA:   return 30_000
        case .vitaminC:   return 5_000
        case .vitaminD:   return 2_000
        case .vitaminE:   return 1_000
        case .vitaminB6:  return 100
        case .vitaminB12: return 1_000
        case .folate:     return 10_000
        case .calcium:    return 5_000
        case .iron:       return 500
        case .magnesium:  return 3_000
        case .zinc:       return 500
        case .potassium:  return 10_000
        case .sodium:     return 40_000
        case .selenium:   return 5_000
        }
    }

    /// В каких единицах хранится количество.
    private var unitScale: UnitScale {
        switch self {
        case .vitaminA, .vitaminD, .vitaminB12, .folate, .selenium: return .micrograms
        case .vitaminC, .vitaminE, .vitaminB6, .calcium, .iron,
             .magnesium, .zinc, .potassium, .sodium: return .milligrams
        case .fiber: return .grams
        }
    }

    private enum UnitScale { case micrograms, milligrams, grams }

    /// Витамин, а не минерал. По этому признаку день решает, можно ли считать
    /// состав записи изученным: минералы с этикетки про витамины не говорят.
    var isVitamin: Bool {
        switch self {
        case .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminB6, .vitaminB12, .folate:
            return true
        case .fiber, .calcium, .iron, .magnesium, .zinc, .potassium, .sodium, .selenium:
            return false
        }
    }

    /// Единица, в которой хранится и показывается количество.
    var unit: String {
        switch self {
        case .vitaminA, .vitaminD, .vitaminB12, .folate, .selenium:
            return String(localized: "мкг")
        case .vitaminC, .vitaminE, .vitaminB6, .calcium, .iron, .magnesium, .zinc, .potassium, .sodium:
            return String(localized: "мг")
        case .fiber:
            return String(localized: "г")
        }
    }

    /// Обозначение для значка в строке продукта. У минералов химический символ,
    /// у витаминов буква: и то и другое читается на любом языке, поэтому
    /// переводить тут нечего.
    var symbol: String {
        switch self {
        case .fiber:      return "Fib"
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
        // 28 г — привычный Daily Value. Рабочий ориентир выше — около 14 г
        // на тысячу килокалорий, — но шкала здесь общая для всех нутриентов.
        case .fiber:      return 28
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
        case .fiber:      return 1079   // Fiber, total dietary
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

    /// Копия с одним изменённым нутриентом.
    func setting(_ nutrient: Micronutrient, to amount: Double) -> Micronutrients {
        var result = self
        result.per100g[nutrient.rawValue] = amount
        return result
    }

    /// Что из этого состава можно одолжить похожему продукту.
    ///
    /// Не весь состав целиком: витамины A и C и натрий у похожей еды свои, и
    /// переносить их значит придумывать. Остальное — оценка по классу, и
    /// продукт, получивший такой состав, помечен оценкой.
    func transferable() -> Micronutrients {
        var result = Micronutrients()
        for nutrient in Micronutrient.allCases where nutrient.transfer != .never {
            guard let amount = self[nutrient] else { continue }
            result = result.setting(nutrient, to: amount)
        }
        return result
    }

    /// Есть ли здесь настоящие витамины и минералы.
    ///
    /// Клетчатка не в счёт: её вписывают с упаковки, и продукт с одной
    /// клетчаткой про витамины по-прежнему ничего не знает — значит одолжить
    /// их ему всё ещё можно.
    var hasVitamins: Bool {
        Micronutrient.allCases.contains { $0 != .fiber && self[$0] != nil }
    }

    /// Нутриенты порции по составу на сто грамм.
    func portion(grams: Double) -> Micronutrients {
        times(grams / 100)
    }

    /// Просто умножить: когда значения уже абсолютные, а не на сто грамм.
    func times(_ factor: Double) -> Micronutrients {
        var result = Micronutrients()
        result.per100g = per100g.mapValues { $0 * factor }
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
        let portion = portion(grams: grams)
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
