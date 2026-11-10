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
    /// Калорий к этому часу меньше, чем пора бы: процент от нормы и сколько
    /// килокалорий до неё осталось.
    case underGoal(percent: Int, remaining: Int)
    /// Белка ниже цели на 20%+.
    case lowProtein(deficitGrams: Int)
    /// Жиров ниже цели на 20%+.
    case lowFat(deficitGrams: Int)
    /// Углеводов выше цели на 30%+.
    case highCarbs(overGrams: Int)
    /// Вес не менялся две недели.
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
        case .lowProtein: return String(localized: "Добавь белка")
        case .lowFat: return String(localized: "Добавь жиров")
        case .highCarbs: return String(localized: "Углеводы сверх нормы")
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
        case .lowProtein(let grams):
            return String(format: String(localized: "Белка маловато: добери ещё %d г."), grams)
        case .lowFat(let grams):
            return String(format: String(localized: "Жиров маловато: добери ещё %d г."), grams)
        case .highCarbs(let grams):
            return String(format: String(localized: "Углеводов на %d г больше цели."), grams)
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

    /// Приоритет: чем выше, тем раньше показываем.
    var priority: Int {
        switch self {
        case .overGoal: return 100
        // «Пора ужинать» конкретнее, чем «мало съедено»: человеку нужно
        // действие, а не сводка. Поэтому вечером совет про ужин идёт первым.
        case .noDinnerYet: return 95
        case .underGoal: return 90
        case .lowProtein, .lowFat, .highCarbs: return 80
        case .weightPlateau: return 60
        // Три дня без записей — важнее, чем «пора ужинать»: советовать
        // поесть человеку, который вообще перестал вести дневник, бессмысленно.
        case .notLogging: return 96
        case .onTarget, .none: return 10
        }
    }
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
        weightTrend: [Double]?,
        lastLoggedDay: Date?,
        wakeHour: Double = 7,
        sleepHour: Double = 23,
        now: Date = Date()
    ) -> DailyAdvice {
        var candidates: [(DailyAdvice, Int)] = []
        let progress = dayProgress(wake: wakeHour, sleep: sleepHour, now: now)

        // 1. Калории vs цель.
        if adaptedTodayGoal > 0 {
            let pct = Double(consumedToday) / Double(adaptedTodayGoal) * 100
            if pct >= 95 && pct <= 105 {
                candidates.append((.onTarget, 10))
            } else if pct > 105 {
                candidates.append((.overGoal(percent: Int((pct - 100).rounded())), 100))
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
                    candidates.append((.underGoal(percent: Int((100 - pct).rounded()),
                                                  remaining: adaptedTodayGoal - consumedToday), 90))
                }
            }
        }

        // 2. Белок.
        if let pt = proteinTarget, pt > 0, macrosToday.protein < pt * 0.8 {
            let deficit = Int((pt - macrosToday.protein).rounded())
            candidates.append((.lowProtein(deficitGrams: deficit), 80))
        }

        // 3. Жиры.
        if let ft = fatTarget, ft > 0, macrosToday.fat < ft * 0.8 {
            let deficit = Int((ft - macrosToday.fat).rounded())
            candidates.append((.lowFat(deficitGrams: deficit), 80))
        }

        // 4. Углеводы.
        if let ct = carbsTarget, ct > 0, macrosToday.carbs > ct * 1.3 {
            let over = Int((macrosToday.carbs - ct).rounded())
            candidates.append((.highCarbs(overGrams: over), 80))
        }

        // 5. Вес не менялся 14+ дней.
        if let trend = weightTrend, trend.count >= 14 {
            let first = trend[trend.count - 14]
            let last = trend[trend.count - 1]
            if abs(last - first) < 0.5 {
                candidates.append((.weightPlateau(days: 14), 60))
            }
        }

        // 6. Не записывали еду 3+ дня.
        if let last = lastLoggedDay {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            if daysSince >= 3 {
                candidates.append((.notLogging(days: daysSince), 40))
            }
        }
        // Если записей вообще нет — не советуем, а молчим: первый запуск.

        // 7. Вечер, а ужина нет (18:00–21:00, калорий мало).
        //
        // Верхняя граница важна: без неё «пора ужинать» висело и в полночь,
        // то есть советовало приём пищи ровно перед сном.
        let hour = Calendar.current.component(.hour, from: now)
        if (18..<21).contains(hour), consumedToday < adaptedTodayGoal * 2 / 3, adaptedTodayGoal > 0 {
            candidates.append((.noDinnerYet, 95))
        }

        return candidates.max(by: { $0.1 < $1.1 })?.0 ?? .none
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
