import Foundation

/// Совет дня: одна контекстная подсказка на экране «Сегодня».
///
/// Считается из данных пользователя — калории, макросы, вес, история.
/// Без ML, без сети, без автозаполнения: только правила и статистика.
enum DailyAdvice: Equatable {
    /// Калорий сегодня набрано ровно в норму (±5%).
    case onTarget
    /// Калорий набрано больше нормы на процент.
    case overGoal(percent: Int)
    /// Калорий к этому часу меньше, чем пора бы: сколько процентов нормы уже
    /// **съедено** и сколько килокалорий до неё осталось.
    ///
    /// Процент — съеденное, а не недобор: текст говорит «съедено N%», и
    /// число обязано быть тем, что съедено. Раньше сюда клали недобор, и при
    /// 35% съеденного человеку писали «съедено 65%», а при пустом дне —
    /// «съедено 100%».
    case underGoal(percent: Int, remaining: Int)
    /// Вес не менялся две недели: хватает трёх взвешиваний, растянутых на срок.
    case weightPlateau(days: Int)
    /// Не записывали еду 3+ дня.
    case notLogging(days: Int)
    /// Вечер, а еды почти нет — напомнить про ужин.
    case noDinnerYet
    /// Нет данных для совета.
    case none

    var title: String {
        switch self {
        case .onTarget: return String(localized: "Норма на сегодня набрана")
        case .overGoal: return String(localized: "Сегодня перебор")
        case .underGoal: return String(localized: "Не доел до нормы")
        case .weightPlateau: return String(localized: "Вес стоит на месте")
        case .notLogging: return String(localized: "Ты не записывал еду")
        case .noDinnerYet: return String(localized: "Вечер, а ужина ещё нет")
        case .none: return ""
        }
    }

    var body: String {
        switch self {
        case .onTarget:
            return String(localized: "Ты в норме. Завтра можно повторить.")
        case .overGoal(let pct):
            return String(format: String(localized: "На %d%% выше цели. Завтра можно есть легче."), pct)
        case .underGoal(let pct, let remaining):
            return String(format: String(localized: "Съедено %1$d%% нормы — к этому часу маловато. До цели ещё %2$d ккал."), pct, remaining)
        case .weightPlateau(let days):
            return String(format: String(localized: "Вес не менялся %d дней. Пересмотри дефицит или приём пищи."), days)
        case .notLogging(let days):
            return String(format: String(localized: "%d дней нет записей. Начни с одного приёма."), days)
        case .noDinnerYet:
            return String(localized: "Пора ужинать — не пропускай приём.")
        case .none:
            return ""
        }
    }

    /// Приоритет: чем выше, тем раньше показываем. Числа — общая шкала
    /// подсказок «Сегодня» (`DayHint.Urgency`), утверждённая владельцем: совет
    /// дня соревнуется не только сам с собой, но и с постом, копией и
    /// сигналом «пора подъесть».
    ///
    /// Плато выше перебора. Перебор бывает сознательным — праздник, ужин в
    /// гостях, — а плато говорит о том, что перестала работать сама норма.
    /// Пока плато стояло ниже, из двух движок выбирал перебор, и до общей
    /// очереди плато не доходило вовсе.
    ///
    /// Остальное в прежнем порядке: «нет записей» важнее «пора ужинать» —
    /// советовать поесть человеку, бросившему дневник, бессмысленно; «пора
    /// ужинать» конкретнее, чем «мало съедено».
    var priority: Int {
        switch self {
        case .weightPlateau: return DayHint.Urgency.plateau
        case .overGoal: return DayHint.Urgency.overGoal
        case .notLogging: return DayHint.Urgency.notLogging
        case .noDinnerYet: return DayHint.Urgency.noDinnerYet
        case .underGoal: return DayHint.Urgency.underGoal
        case .onTarget, .none: return DayHint.Urgency.onTarget
        }
    }
}

/// Взвешивание для совета дня: дата и вес.
///
/// Совету нужна дата, а не просто вес: «не менялся две недели» утверждает срок, и
/// проверить его по голому списку чисел нельзя.
struct AdviceWeighIn: Equatable {
    let date: Date
    let kg: Double
}

/// Расчёт совета дня из текущих данных.
struct DailyAdviceEngine {
    /// Выбрать один совет — самый важный из подходящих.
    static func advice(
        consumedToday: Int,
        adaptedTodayGoal: Int,
        macrosToday: Macros,
        proteinTarget: Double?,
        fatTarget: Double?,
        carbsTarget: Double?,
        weighIns: [AdviceWeighIn] = [],
        lastLoggedDay: Date?,
        wakeHour: Double = 7,
        sleepHour: Double = 23,
        now: Date = Date()
    ) -> DailyAdvice {
        var candidates: [DailyAdvice] = []
        let progress = dayProgress(wake: wakeHour, sleep: sleepHour, now: now)

        // 1. Калории vs цель.
        if adaptedTodayGoal > 0 {
            let pct = Double(consumedToday) / Double(adaptedTodayGoal) * 100
            if pct >= 95 && pct <= 105 {
                candidates.append(.onTarget)
            } else if pct > 105 {
                candidates.append(.overGoal(percent: Int((pct - 100).rounded())))
            } else if pct < 80 {
                // Сравниваем не с итоговой нормой, а с темпом дня: сколько
                // уже пора бы съесть к этому часу, если есть от подъёма до
                // отбоя. Иначе «недобрано 15%» висело с утра, когда 15% и
                // должно быть, — то есть сообщало ровно то, что человек и
                // так знает, глядя на кольцо.
                //
                // Говорим только когда прожита половина дня и отставание от
                // темпа заметное (20% нормы): это уже повод поесть, а не
                // сводка.
                let expected = progress * 100
                if progress >= 0.5, pct < expected - 20 {
                    candidates.append(.underGoal(percent: Int(pct.rounded()),
                                                 remaining: adaptedTodayGoal - consumedToday))
                }
            }
        }

        // 2. Белок и жиры.
        //
        // Советом дня они больше не бывают: у каждого есть своя плитка под
        // кольцом, и второй строки про то же самое экран не заслуживает.
        // Отставание от темпа считает `isBehindPace`, а показывает плитка.

        // 3. Вес не менялся две недели.
        //
        // Нужно три взвешивания, растянутых хотя бы на десять дней из
        // четырнадцати. Раньше требовалось четырнадцать подряд — по одному в
        // день без пропусков, и совет не срабатывал почти ни у кого: люди
        // взвешиваются раз в несколько дней.
        let windowStart = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let recent = weighIns.filter { $0.date >= windowStart }.sorted { $0.date < $1.date }
        if recent.count >= 3, let first = recent.first, let last = recent.last,
           last.date.timeIntervalSince(first.date) >= 10 * 86_400,
           abs(last.kg - first.kg) < 0.5 {
            candidates.append(.weightPlateau(days: 14))
        }

        // 4. Не записывали еду 3+ дня.
        if let last = lastLoggedDay {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            if daysSince >= 3 {
                candidates.append(.notLogging(days: daysSince))
            }
        }
        // Если записей вообще нет — не советуем, а молчим: первый запуск.

        // 5. Вечер, а ужина нет (18:00–21:00, калорий мало).
        //
        // Верхняя граница важна: без неё «пора ужинать» висело и в полночь,
        // то есть советовало приём пищи ровно перед сном.
        let hour = Calendar.current.component(.hour, from: now)
        if (18..<21).contains(hour), consumedToday < adaptedTodayGoal * 2 / 3, adaptedTodayGoal > 0 {
            candidates.append(.noDinnerYet)
        }

        return candidates.max(by: { $0.priority < $1.priority }) ?? .none
    }

    /// Отстаёт ли макрос от темпа дня.
    ///
    /// Сравниваем не с итоговой целью, а с тем, сколько пора бы съесть к
    /// этому часу: в полдень «съедено 20 г из 136» — норма, а не повод для
    /// подсказки. Молчим, пока не прожита половина дня, и пока отставание
    /// меньше пятой части цели. К концу дня правило совпадает с прежним
    /// «меньше 80% цели».
    static func isBehindPace(eaten: Double, target: Double?, progress: Double) -> Bool {
        guard let target, target > 0, progress >= 0.5 else { return false }
        return eaten < (progress - 0.2) * target
    }

    /// Съедено заметно больше нормы — только после половины дня.
    ///
    /// Плотный завтрак утром не должен проходить за перебор: цель на день,
    /// а не на утро. После полдня превышение на 30%+ — повод сказать.
    static func isOverTarget(eaten: Double, target: Double?, progress: Double) -> Bool {
        guard let target, target > 0, progress >= 0.5 else { return false }
        return eaten > target * 1.3
    }

    /// Какая доля дня уже прошла — от подъёма до отбоя.
    ///
    /// До подъёма — ноль, после отбоя — единица: раньше вставать смысла нет,
    /// а позже ложиться день уже прожит. По этой доле и считается, сколько
    /// калорий к текущему часу пора бы съесть.
    static func dayProgress(wake: Double, sleep: Double, now: Date) -> Double {
        guard sleep > wake else { return 1 }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        if hour <= wake { return 0 }
        if hour >= sleep { return 1 }
        return (hour - wake) / (sleep - wake)
    }
}
