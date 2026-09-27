import Foundation

/// Не пора ли подъесть.
///
/// Дефицит работает, пока тело его терпит. Дальше начинается то, что видно не
/// на весах, а вокруг них: вес встал, пульс в покое пополз вверх, сон
/// испортился, и каждый следующий день голоднее предыдущего. В этот момент
/// человек обычно режет калории ещё — и получает ровно обратное.
///
/// Приложение знает всё, что нужно, чтобы сказать об этом вслух: сколько
/// недель идёт дефицит, движется ли вес, что с пульсом и сном. Признаки не
/// складываются в диагноз — они складываются в предложение: сдвинуть рефид на
/// сегодня или взять диет-брейк.
///
/// Чистая логика без стора: пороги здесь важнее всего, и проверять их надо
/// тестами.
enum RecoverySignal {
    struct Input {
        /// Идёт ли дефицит прямо сейчас. Вне его советовать нечего.
        var isCutting: Bool = false
        /// Сколько недель подряд длится дефицит.
        var weeksInDeficit: Int = 0
        /// Насколько вес ушёл за последнюю неделю, кг (отрицательное — вниз).
        var weeklyChangeKg: Double? = nil
        /// Сколько планировалось потерять за неделю, кг.
        var plannedWeeklyKg: Double? = nil
        /// На сколько ударов пульс в покое выше привычного.
        var pulseRise: Int? = nil
        /// Насколько сон короче обычного, часов (среднее за неделю).
        var sleepShortfall: Double = 0
        /// Брали ли диет-брейк недавно — второй подряд предлагать незачем.
        var weeksSinceBreak: Int? = nil
    }

    enum Verdict: String, Equatable, Sendable {
        /// Всё идёт как задумано.
        case fine
        /// Один день повыше — сдвинуть рефид на сегодня.
        case refeed
        /// Неделя-две поддержания.
        case dietBreak
    }

    /// После скольких недель непрерывного дефицита брейк нужен независимо от
    /// самочувствия. Восемь — та граница, за которой у большинства падают и
    /// расход, и тренировки; дальше дефицит покупается всё дороже.
    static let weeksBeforeBreak = 8
    /// Ближе этого срока второй брейк не предлагаем.
    static let weeksBetweenBreaks = 4
    /// Вес считается вставшим, если за неделю ушло меньше трети плана.
    static let stallShare = 1.0 / 3

    /// Признаки, по которым судим. Один — совпадение, два — уже сигнал.
    static func strain(_ input: Input) -> Int {
        var count = 0
        if let change = input.weeklyChangeKg, let planned = input.plannedWeeklyKg, planned > 0,
           -change < planned * stallShare {
            count += 1
        }
        if let rise = input.pulseRise, rise >= RestingPulse.notableRise { count += 1 }
        if input.sleepShortfall >= 1 { count += 1 }
        return count
    }

    static func verdict(_ input: Input) -> Verdict {
        guard input.isCutting else { return .fine }
        let recentBreak = (input.weeksSinceBreak ?? Int.max) < weeksBetweenBreaks
        // Долгий дефицит — повод для брейка сам по себе: организм устаёт и
        // тогда, когда человек этого ещё не чувствует.
        if input.weeksInDeficit >= weeksBeforeBreak, !recentBreak { return .dietBreak }
        let strain = strain(input)
        // Три признака разом — это уже не «тяжёлая неделя», а накопленная
        // усталость, и одним сытым днём она не лечится.
        if strain >= 3, !recentBreak { return .dietBreak }
        if strain >= 2 { return .refeed }
        return .fine
    }

    /// Чем объяснить предложение. Возвращает nil, когда предлагать нечего.
    static func reason(_ input: Input, brief: Bool = false) -> String? {
        let verdict = verdict(input)
        guard verdict != .fine else { return nil }
        func pick(_ detailed: String, _ short: String) -> String { brief ? short : detailed }

        if verdict == .dietBreak, input.weeksInDeficit >= weeksBeforeBreak {
            return String(format: pick(
                String(localized: "Дефицит идёт %lld недель подряд. Дальше он покупается всё дороже: расход падает, тренировки тяжелеют, а вес всё равно стоит. Неделя-две поддержания вернут и то, и другое — жир за сушку уходит так же."),
                String(localized: "Дефицит идёт %lld недель подряд — пора на неделю-две поддержания.")), input.weeksInDeficit)
        }

        var parts: [String] = []
        if let change = input.weeklyChangeKg, let planned = input.plannedWeeklyKg, planned > 0,
           -change < planned * stallShare {
            parts.append(String(localized: "вес за неделю почти не двинулся"))
        }
        if let rise = input.pulseRise, rise >= RestingPulse.notableRise {
            parts.append(String(format: String(localized: "пульс в покое выше обычного на %lld"), rise))
        }
        if input.sleepShortfall >= 1 {
            parts.append(String(format: String(localized: "сон короче привычного на %@ ч"),
                                String(format: "%.1f", input.sleepShortfall)))
        }
        let listed = parts.joined(separator: ", ")

        if verdict == .dietBreak {
            return String(format: pick(
                String(localized: "Сразу несколько признаков усталости: %@. Одним сытым днём это не лечится — возьми неделю-две поддержания, дефицит после них снова начнёт работать."),
                String(localized: "Признаки усталости: %@. Нужен брейк, а не рефид.")), listed)
        }
        return String(format: pick(
            String(localized: "Похоже, тело просит передышки: %@. Сдвинь рефид на сегодня — дневной дефицит от этого не изменится, он просто переедет с другого дня."),
            String(localized: "Тело просит передышки: %@. Сдвинь рефид на сегодня.")), listed)
    }
}
