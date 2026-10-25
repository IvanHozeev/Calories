import Foundation

/// Итог недели: что случилось за семь дней и что это значит.
///
/// День отвечает «как я сегодня», но решает не он. Вес двигается неделями,
/// расход считается по неделе, дефицит держится или срывается тоже на неделе —
/// а человек до сих пор видел только семь отдельных кружков в полоске и
/// складывал их в голове.
///
/// Чистая логика без стора: пороги и формулировки проверяются тестами.
enum WeekReview {
    struct Input {
        /// Съеденное по дням недели, от понедельника.
        var eaten: [Int] = []
        /// Норма тех же дней — та, что действовала в каждый из них.
        var goals: [Int] = []
        /// Сколько дней из семи записаны.
        var loggedDays: Int = 0
        /// Вес по тренду в начале и в конце недели.
        var weightStart: Double? = nil
        var weightEnd: Double? = nil
        /// Сколько планировалось потерять или набрать за неделю, кг.
        var plannedWeeklyKg: Double? = nil
        /// Измеренный расход на начало и на конец недели.
        var expenditureStart: Double? = nil
        var expenditureEnd: Double? = nil
        /// Средний сон за неделю и средние шаги.
        var sleepHours: Double? = nil
        var steps: Int? = nil
        /// Пульс в покое: среднее за неделю и насколько это выше привычного.
        var restingPulse: Int? = nil
        var pulseRise: Int? = nil
        /// Взвешенные рабочие сеты за неделю — из соседнего приложения.
        /// nil, когда его нет или оно давно молчит.
        var gymSets: Double? = nil
        /// Самые нагруженные мышцы недели: чем назвать нагрузку словами.
        var gymTopMuscles: [String] = []
        /// Идёт ли разгрузка в зале.
        var gymDeload: Bool? = nil
    }

    struct Line: Identifiable, Equatable {
        enum Tone: String { case good, warning, info }
        let id: String
        let tone: Tone
        let text: String
    }

    /// Насколько среднее за неделю может разойтись с нормой, чтобы считаться
    /// попаданием. Два процента — тот же допуск, что у дня: попасть точнее
    /// невозможно, да и незачем.
    static let tolerance = 0.02

    static func lines(_ input: Input, brief: Bool = false) -> [Line] {
        func pick(_ detailed: String, _ short: String) -> String { brief ? short : detailed }
        var result: [Line] = []

        guard input.loggedDays > 0 else {
            return [Line(id: "empty", tone: .info,
                         text: String(localized: "За эту неделю нет записей — разбирать нечего."))]
        }

        // Первое — среднее против нормы: именно оно решает, работает ли план.
        if !input.eaten.isEmpty, input.goals.count == input.eaten.count {
            let meanEaten = Double(input.eaten.reduce(0, +)) / Double(input.eaten.count)
            let meanGoal = Double(input.goals.reduce(0, +)) / Double(input.goals.count)
            let delta = Int((meanEaten - meanGoal).rounded())
            if meanGoal > 0, abs(meanEaten - meanGoal) <= meanGoal * tolerance {
                result.append(Line(id: "intake-ok", tone: .good,
                                   text: String(format: pick(
                                    String(localized: "В среднем %lld ккал в день — это и есть норма недели. Один день выше, другой ниже: решает среднее, а не каждый отдельный."),
                                    String(localized: "В среднем %lld ккал в день — норма недели выдержана.")), Int(meanEaten.rounded()))))
            } else if delta > 0 {
                result.append(Line(id: "intake-over", tone: .warning,
                                   text: String(format: pick(
                                    String(localized: "В среднем на %lld ккал в день больше нормы. За неделю это %lld ккал сверх — примерно столько же и не ушло."),
                                    String(localized: "В среднем на %lld ккал в день больше нормы (%lld за неделю).")),
                                                delta, delta * input.eaten.count)))
            } else {
                result.append(Line(id: "intake-under", tone: .info,
                                   text: String(format: pick(
                                    String(localized: "В среднем на %lld ккал в день меньше нормы. Ускорить так не выйдет: недоеденное возвращается срывом, а тело отвечает замедлением."),
                                    String(localized: "В среднем на %lld ккал в день меньше нормы.")), -delta)))
            }
        }

        // Полнота дневника: без неё все остальные выводы шаткие.
        if input.loggedDays < 5 {
            result.append(Line(id: "logging", tone: .warning,
                               text: String(format: pick(
                                String(localized: "Записано %lld дней из семи. По такой неделе ни расход, ни тренд веса посчитать нельзя — они собираются из полных дней."),
                                String(localized: "Записано %lld дней из семи — маловато для выводов.")), input.loggedDays)))
        }

        // Вес — не число на весах, а тренд: одно утро ничего не значит.
        if let start = input.weightStart, let end = input.weightEnd {
            let change = end - start
            let text: String
            var tone = Line.Tone.info
            if let planned = input.plannedWeeklyKg, planned > 0 {
                let share = -change / planned
                if share >= 0.7 {
                    tone = .good
                    text = pick(String(localized: "Вес по тренду %1$@ кг за неделю — это и был план (%2$@). Так и держи."),
                                String(localized: "Вес по тренду %1$@ кг при плане %2$@."))
                } else if share >= 0 {
                    text = pick(String(localized: "Вес по тренду %1$@ кг при плане %2$@. Медленнее задуманного — но пока идёт вниз, менять ничего не нужно."),
                                String(localized: "Вес по тренду %1$@ кг при плане %2$@ — медленнее."))
                } else {
                    tone = .warning
                    text = pick(String(localized: "Вес по тренду %1$@ кг при плане %2$@ — он не идёт туда, куда должен. Если так вторую неделю, дело не в весах, а в расчёте."),
                                String(localized: "Вес по тренду %1$@ кг при плане %2$@ — не туда."))
                }
                result.append(Line(id: "weight", tone: tone,
                                   text: String(format: text, signed(change), signed(-planned))))
            } else {
                result.append(Line(id: "weight", tone: .info,
                                   text: String(format: pick(
                                    String(localized: "Вес по тренду %@ кг за неделю. Тренд, а не утро: соль и вода дают больше килограмма разброса."),
                                    String(localized: "Вес по тренду %@ кг за неделю.")), signed(change))))
            }
        }

        // Расход — самое незаметное изменение недели: он едет молча.
        if let start = input.expenditureStart, let end = input.expenditureEnd, start > 0 {
            let delta = Int((end - start).rounded())
            if abs(delta) >= 50 {
                result.append(Line(id: "expenditure", tone: delta < 0 ? .warning : .info,
                                   text: String(format: pick(
                                    delta < 0
                                    ? String(localized: "Измеренный расход снизился на %1$lld ккал, до %2$lld. Так тело отвечает на дефицит — и поэтому норма считается от факта, а не от формулы.")
                                    : String(localized: "Измеренный расход вырос на %1$lld ккал, до %2$lld. Больше работы или лучше восстановление — в любом случае есть можно больше."),
                                    delta < 0
                                    ? String(localized: "Расход снизился на %1$lld, до %2$lld.")
                                    : String(localized: "Расход вырос на %1$lld, до %2$lld.")),
                                                abs(delta), Int(end.rounded()))))
            }
        }

        // Сон и пульс — не оценка недели, а объяснение, почему она такая.
        if let sleep = input.sleepHours, sleep > 0 {
            let tone: Line.Tone = sleep < 6.5 ? .warning : .good
            result.append(Line(id: "sleep", tone: tone,
                               text: String(format: pick(
                                sleep < 6.5
                                ? String(localized: "Спал в среднем %@ ч. На дефиците это самая дорогая экономия: голод сильнее, силовые ниже, вес стоит дольше.")
                                : String(localized: "Спал в среднем %@ ч — этого хватает, чтобы дефицит переносился спокойно."),
                                String(localized: "Сон в среднем %@ ч.")), String(format: "%.1f", sleep))))
        }
        if let rise = input.pulseRise, rise >= RestingPulse.notableRise, let pulse = input.restingPulse {
            result.append(Line(id: "pulse", tone: .warning,
                               text: String(format: pick(
                                String(localized: "Пульс в покое %1$lld — на %2$lld выше привычного. Неделю подряд так держится недовосстановление; отдых сдвинет вес вернее, чем ещё меньше еды."),
                                String(localized: "Пульс в покое %1$lld, на %2$lld выше обычного.")), pulse, rise)))
        }
        // Зал — последним: это не оценка недели и не объяснение самочувствия,
        // а вторая половина расхода, которой мы до сих пор не видели. Вес
        // встал при честном дефиците — объём недели и есть первое, что стоит
        // проверить, прежде чем резать еду дальше.
        if let sets = input.gymSets, sets > 0 {
            let muscles = input.gymTopMuscles.prefix(2).joined(separator: ", ")
            let text: String
            if input.gymDeload == true {
                text = String(format: pick(
                    String(localized: "В зале разгрузка: %@ рабочих сетов. Меньше работы — меньше и расход, поэтому вес на такой неделе часто стоит, и это не провал."),
                    String(localized: "Разгрузка в зале, %@ сетов.")), Self.sets(sets))
            } else if muscles.isEmpty {
                text = String(format: pick(
                    String(localized: "В зале %@ рабочих сетов за неделю — это та работа, из которой сложилась вторая половина расхода."),
                    String(localized: "В зале %@ сетов за неделю.")), Self.sets(sets))
            } else {
                text = String(format: pick(
                    String(localized: "В зале %1$@ рабочих сетов за неделю, больше всего досталось: %2$@."),
                    String(localized: "В зале %1$@ сетов, больше всего: %2$@.")), Self.sets(sets), muscles)
            }
            result.append(Line(id: "gym", tone: .info, text: text))
        }

        if let steps = input.steps, steps > 0 {
            result.append(Line(id: "steps", tone: .info,
                               text: String(format: pick(
                                String(localized: "Шагов в среднем %lld в день. Это та нагрузка, из которой и сложился измеренный расход."),
                                String(localized: "Шагов в среднем %lld в день.")), steps)))
        }
        return result
    }

    /// Сеты — с половинками, как их считает сосед: сет на одну сторону
    /// у него стоит половину, и округлять это до целого значит врать.
    private static func sets(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private static func signed(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }
}
