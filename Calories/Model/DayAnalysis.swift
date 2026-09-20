import Foundation

/// Разбор дня словами: что с макросами не так и что с этим делать.
///
/// Цифры и полоски показывают, сколько съедено, но не говорят, хорошо это или
/// плохо. Вывод «белка 90 г из 136» человек делает сам и каждый день заново;
/// здесь он сделан один раз и объяснён — почему это важно именно на дефиците,
/// именно для натурала.
///
/// Чистая функция без стора: её легко проверить тестами на любых числах.
enum DayAnalysis {
    struct Advice: Identifiable, Equatable {
        enum Tone: String {
            case good, warning, info
        }

        let id: String
        let tone: Tone
        let text: String
    }

    struct Input {
        let macros: Macros
        let calories: Int
        let goal: Int
        let proteinTarget: Double?
        let fatTarget: Double?
        let carbsTarget: Double?
        let weightKg: Double?
        /// День отмечен голоданием: разбирать там нечего, ноль там намеренный.
        let isFast: Bool
        /// Сегодняшний день ещё идёт — выводы по нему преждевременны.
        let isInProgress: Bool
        /// Клетчатка за день, если состав съеденного известен достаточно точно.
        /// nil — считать не по чему, и молчать об этом честнее, чем пугать нулём.
        var fiber: Double? = nil
    }

    /// Ниже этой доли жира от веса страдают гормоны — тот самый порог,
    /// который в профиле нельзя опустить.
    static let fatFloorPerKg = 0.5
    /// Минимум углеводов, ниже которого мозгу не хватает глюкозы (RDA).
    static let carbsFloor = 130.0
    /// Рабочий ориентир по клетчатке. Привычные 25–38 г в день; берём нижнюю
    /// границу — на дефиците она важнее всего для сытости.
    static let fiberFloor = 25.0

    static func advice(_ input: Input) -> [Advice] {
        guard !input.isFast else {
            return [Advice(id: "fast", tone: .info,
                           text: String(localized: "День голодания — разбирать нечего. Ноль здесь намеренный, и на серию он не влияет."))]
        }
        guard input.calories > 0 else { return [] }

        var result: [Advice] = []

        // Белок первым: на дефиците он решает, уходит жир или мышцы.
        if let target = input.proteinTarget, target > 0 {
            let share = input.macros.protein / target
            let missing = Int((target - input.macros.protein).rounded())
            if share >= 1 {
                result.append(Advice(id: "protein-ok", tone: .good,
                                     text: String(localized: "Белок закрыт. На дефиците это главное: он решает, уходит жир или мышцы.")))
            } else if share >= 0.85, !input.isInProgress {
                result.append(Advice(id: "protein-close", tone: .info,
                                     text: String(format: String(localized: "Белка не хватило %lld г. Разница небольшая, но если так каждый день — за месяц она заметна."), missing)))
            } else if !input.isInProgress {
                result.append(Advice(id: "protein-low", tone: .warning,
                                     text: String(format: String(localized: "Белка мало: не хватило %lld г. На дефиците недобор белка оплачивается мышцами — это те самые «похудел, но выгляжу хуже»."), missing)))
            }
        }

        // Жир — про гормоны, а не про калории.
        if let weight = input.weightKg, weight > 0, !input.isInProgress {
            let perKg = input.macros.fat / weight
            if perKg < fatFloorPerKg {
                result.append(Advice(id: "fat-low", tone: .warning,
                                     text: String(format: String(localized: "Жира %.2f г/кг — ниже рабочего минимума 0.5. День-другой ничего не решают, но неделями так сидеть значит платить тестостероном."), perKg)))
            }
        }
        let fatCalories = input.macros.fat * MacroTargets.kcalPerFatGram
        if input.calories > 0, fatCalories / Double(input.calories) > 0.45, !input.isInProgress {
            result.append(Advice(id: "fat-high", tone: .info,
                                 text: String(localized: "Почти половина калорий из жира. Он сытнее на грамм, но вытесняет углеводы, на которых идут тренировки.")))
        }

        // Углеводы — топливо зала и мозга.
        if input.macros.carbs < carbsFloor, !input.isInProgress {
            result.append(Advice(id: "carbs-low", tone: .warning,
                                 text: String(format: String(localized: "Углеводов %lld г — меньше 130, минимума для мозга. Если день был тренировочный, силовые просядут на следующей же тренировке."), Int(input.macros.carbs.rounded()))))
        }

        // Калории: и недобор, и перебор одинаково мешают.
        if input.goal > 0, !input.isInProgress {
            let share = Double(input.calories) / Double(input.goal)
            let delta = abs(input.calories - input.goal)
            if share < 0.8 {
                result.append(Advice(id: "calories-low", tone: .warning,
                                     text: String(format: String(localized: "Недобор %lld ккал до нормы. Ускорить сушку так не выйдет: недоеденное возвращается срывом, а тело отвечает замедлением."), delta)))
            } else if share > 1.1 {
                result.append(Advice(id: "calories-high", tone: .warning,
                                     text: String(format: String(localized: "Перебор %lld ккал. Один день погоды не делает — важно, что скажет неделя."), delta)))
            } else if share >= 0.95 {
                result.append(Advice(id: "calories-ok", tone: .good,
                                     text: String(localized: "В норму попал. Неделя таких дней — это и есть результат.")))
            }
        }

        // Клетчатка — про сытость на дефиците, а не про «полезно».
        if let fiber = input.fiber, !input.isInProgress {
            if fiber < fiberFloor {
                result.append(Advice(id: "fiber-low", tone: .info,
                                     text: String(format: String(localized: "Клетчатки %lld г из 25. На дефиците она дешевле всего покупает сытость: объём есть, калорий почти нет."), Int(fiber.rounded()))))
            } else {
                result.append(Advice(id: "fiber-ok", tone: .good,
                                     text: String(localized: "Клетчатки достаточно — с ней дефицит переносится легче.")))
            }
        }

        if input.isInProgress, result.isEmpty {
            result.append(Advice(id: "in-progress", tone: .info,
                                 text: String(localized: "День ещё идёт — разбор будет к вечеру, когда съедено всё.")))
        }
        return result
    }

    /// Доли макросов в калориях — для круговой диаграммы состава.
    ///
    /// Именно в калориях, а не в граммах: в граммах жир всегда выглядит
    /// крошечным, хотя даёт девять килокалорий против четырёх у остальных.
    static func composition(_ macros: Macros) -> [(kind: MacroKind, calories: Double, share: Double)] {
        let parts: [(MacroKind, Double)] = [
            (.protein, macros.protein * MacroTargets.kcalPerProteinGram),
            (.fat, macros.fat * MacroTargets.kcalPerFatGram),
            (.carbs, macros.carbs * MacroTargets.kcalPerCarbGram),
        ]
        let total = parts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        return parts.map { (kind: $0.0, calories: $0.1, share: $0.1 / total) }
    }
}
