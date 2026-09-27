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

    /// Обстоятельства дня: нагрузка, сон, пульс, вес и самый крупный перебор.
    ///
    /// Цифры дневника отвечают, что человек съел. На вопрос «почему день
    /// вышел таким» они не отвечают вовсе, и человек сам сопоставляет
    /// оранжевый день с тем, что в ту ночь не спал, — а чаще не сопоставляет
    /// и решает, что сорвался.
    ///
    /// Поэтому здесь не оценки, а связи: норма выше, потому что много ходил;
    /// вес утром выше, потому что ночь была короткой; неделя с высоким пульсом
    /// покоя — повод отдохнуть, а не резать калории.
    struct Context {
        /// На сколько норма этого дня сдвинута за активность.
        var activityAdjustment: Int = 0
        /// Шаги за день и обычные шаги, если известны.
        var steps: Int? = nil
        var usualSteps: Int? = nil
        /// Записанная тренировка.
        var workoutTitle: String? = nil
        var workoutMinutes: Int? = nil
        /// Сон перед этим днём и насколько он короче привычного.
        var sleepHours: Double? = nil
        var sleepShortfall: Double = 0
        /// Насколько пульс в покое выше привычного.
        var restingPulseRise: Int? = nil
        /// Вес утром и отклонение от тренда.
        var weightKg: Double? = nil
        var weightAboveTrend: Double? = nil
        /// Самый крупный перебор по приёму: название и на сколько.
        var overeatenMeal: String? = nil
        var overeatenBy: Int = 0
    }

    /// Сколько килокалорий поправки стоит называть вслух: меньше — шум.
    static let notableAdjustment = 80
    /// Насколько вес должен уйти выше тренда, чтобы об этом говорить.
    static let notableWeightRise = 0.5

    static func context(_ input: Context) -> [Advice] {
        var result: [Advice] = []

        if let title = input.workoutTitle, let minutes = input.workoutMinutes, minutes > 0 {
            result.append(Advice(id: "workout", tone: .good,
                                 text: String(format: String(localized: "Тренировка: %1$@, %2$lld мин. Её калории уже посчитаны браслетом и учтены в норме дня — второй раз их прибавлять не надо."), title, minutes)))
        }

        if abs(input.activityAdjustment) >= notableAdjustment {
            if let steps = input.steps, let usual = input.usualSteps {
                let diff = steps - usual
                result.append(Advice(id: "activity", tone: .info,
                                     text: diff >= 0
                                     ? String(format: String(localized: "Шагов %1$lld — на %2$lld больше обычного, и норма дня выше на %3$lld ккал. Это не бонус, а плата за работу."), steps, diff, input.activityAdjustment)
                                     : String(format: String(localized: "Шагов %1$lld — на %2$lld меньше обычного, и норма дня ниже на %3$lld ккал. День был тише, значит и потрачено меньше."), steps, -diff, -input.activityAdjustment)))
            } else {
                result.append(Advice(id: "activity-plain", tone: .info,
                                     text: String(format: String(localized: "Норма дня сдвинута на %lld ккал за активность."), input.activityAdjustment)))
            }
        }

        if let hours = input.sleepHours {
            if input.sleepShortfall >= 1 {
                result.append(Advice(id: "sleep-short", tone: .warning,
                                     text: String(format: String(localized: "Спал %1$@ ч — на %2$@ ч меньше обычного. После короткой ночи голод сильнее, а вес утром выше: это вода и кортизол, а не жир. Такой день честнее считать обычным, а не сорванным."),
                                                  String(format: "%.1f", hours), String(format: "%.1f", input.sleepShortfall))))
            } else if hours >= 7 {
                result.append(Advice(id: "sleep-ok", tone: .good,
                                     text: String(format: String(localized: "Спал %@ ч — норма. На дефиците сон держит и аппетит, и силовые."), String(format: "%.1f", hours))))
            }
        }

        if let rise = input.restingPulseRise, isNotablePulse(rise) {
            result.append(Advice(id: "pulse", tone: .warning,
                                 text: String(format: String(localized: "Пульс в покое на %lld удара выше привычного и держится так не первый день. Обычно это недосып или накопленная усталость; если вес при этом встал, отдых сдвинет его вернее, чем ещё меньше еды."), rise)))
        }

        if let weight = input.weightKg, let above = input.weightAboveTrend, above >= notableWeightRise {
            let sleepy = input.sleepShortfall >= 1
            result.append(Advice(id: "weight-spike", tone: .info,
                                 text: sleepy
                                 ? String(format: String(localized: "Вес утром %1$@ кг — на %2$@ выше тренда. Ночь была короткой, и это обычная реакция: вода задерживается. Тренд важнее одного утра."), String(format: "%.1f", weight), String(format: "%.1f", above))
                                 : String(format: String(localized: "Вес утром %1$@ кг — на %2$@ выше тренда. Одно утро ничего не значит: соль, углеводы накануне и вода дают больше килограмма разброса."), String(format: "%.1f", weight), String(format: "%.1f", above))))
        }

        if let meal = input.overeatenMeal, input.overeatenBy > 0 {
            result.append(Advice(id: "meal-overshoot", tone: .info,
                                 text: String(format: String(localized: "Больше всего ушло вверх на приёме «%1$@» — на %2$lld ккал. Смотреть стоит не на день целиком, а на этот приём: именно там решается, попадёшь ли в норму."), meal, input.overeatenBy)))
        }

        return result
    }

    private static func isNotablePulse(_ rise: Int) -> Bool { rise >= 3 }

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
