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
        /// Сколько недель подряд вес стоит. Ноль — идёт как задумано.
        ///
        /// Длительность, а не «встал ли на этой неделе»: одна неделя бывает
        /// у всех — соль, перелёт, плохой сон. Две подряд — это уже не
        /// совпадение, и считать их за один признак значит не заметить
        /// разницы между случайностью и адаптацией.
        var stallWeeks: Int = 0
        /// Насколько просел измеренный расход за три недели, в процентах.
        ///
        /// Самый прямой признак из всех: приложение считает расход по факту —
        /// по съеденному и по весу, — и его падение и есть то, что обычно
        /// называют «дефицит перестал работать». Остальные признаки косвенны
        /// рядом с ним.
        var tdeeDropPercent: Double? = nil
        /// Темп фазы, процентов веса в неделю. Чем он круче, тем быстрее
        /// копится усталость — и тем раньше нужен отдых.
        var weeklyRatePercent: Double? = nil
        /// Брали ли диет-брейк недавно — второй подряд предлагать незачем.
        var weeksSinceBreak: Int? = nil
        /// Идёт ли разгрузочная неделя в зале. nil — соседнего приложения нет
        /// или оно давно молчит, и тогда об этом просто ничего не известно.
        var gymDeload: Bool? = nil
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
    /// Сколько недель дефицита должно пройти, чтобы совпадение с разгрузкой
    /// в зале стало поводом. Половина обычного срока: четыре недели — уже
    /// усталость, просто ещё не та, ради которой стоит ломать план.
    static let weeksBeforeBreakWithDeload = 4
    /// Вес считается вставшим, если за неделю ушло меньше трети плана.
    static let stallShare = 1.0 / 3
    /// Насколько должен просесть измеренный расход, чтобы это считалось
    /// признаком. Пять процентов — больше, чем дают погрешность весов и
    /// неточность дневника за три недели.
    static let notableTDEEDrop = 5.0
    /// А насколько — чтобы признак перевесил любой другой. Восемь процентов
    /// за три недели означают, что расход уходит быстрее, чем вес.
    static let severeTDEEDrop = 8.0
    /// Темп, с которого дефицит считается крутым. Полпроцента в неделю тело
    /// терпит долго, процент — нет.
    static let steepRatePercent = 0.8
    /// Сколько недель дефицита терпит крутой темп.
    static let weeksBeforeBreakWhenSteep = 5

    /// Через сколько недель дефицита брейк нужен независимо от самочувствия.
    ///
    /// Восемь недель — срок для спокойного темпа. На крутом усталость копится
    /// вдвое быстрее, и ждать тех же восьми недель значит ждать заведомо
    /// дольше, чем нужно.
    static func weeksBeforeBreak(rate: Double?) -> Int {
        guard let rate, rate >= steepRatePercent else { return weeksBeforeBreak }
        return weeksBeforeBreakWhenSteep
    }

    /// Признаки, по которым судим. Один — совпадение, два — уже сигнал.
    static func strain(_ input: Input) -> Int {
        var count = 0
        // Застой считается по длительности: вторая неделя подряд весит
        // столько же, сколько первая, — вместе они дают два признака.
        count += min(2, max(input.stallWeeks, isStalled(input) ? 1 : 0))
        // Просевший расход — признак того же веса, а сильно просевший
        // перевешивает: это уже не намёк, а измерение.
        if let drop = input.tdeeDropPercent {
            if drop >= severeTDEEDrop { count += 2 }
            else if drop >= notableTDEEDrop { count += 1 }
        }
        if let rise = input.pulseRise, rise >= RestingPulse.notableRise { count += 1 }
        if input.sleepShortfall >= 1 { count += 1 }
        return count
    }

    /// Стоит ли вес прямо сейчас — по последней неделе.
    static func isStalled(_ input: Input) -> Bool {
        guard let change = input.weeklyChangeKg, let planned = input.plannedWeeklyKg,
              planned > 0 else { return false }
        return -change < planned * stallShare
    }

    static func verdict(_ input: Input) -> Verdict {
        guard input.isCutting else { return .fine }
        let recentBreak = (input.weeksSinceBreak ?? Int.max) < weeksBetweenBreaks
        // Долгий дефицит — повод для брейка сам по себе: организм устаёт и
        // тогда, когда человек этого ещё не чувствует.
        if input.weeksInDeficit >= weeksBeforeBreak(rate: input.weeklyRatePercent),
           !recentBreak { return .dietBreak }
        // Разгрузка в зале — не признак усталости, а уже принятое решение
        // отдохнуть. Тело отдыхает целиком, и держать в эту неделю прежний
        // дефицит — значит отдыхать наполовину. Повод, а не диагноз: сам по
        // себе делоад брейка не требует, но на четвёртой неделе дефицита
        // лучшей недели для него не будет.
        if input.gymDeload == true, input.weeksInDeficit >= weeksBeforeBreakWithDeload,
           !recentBreak {
            return .dietBreak
        }
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

        // Про совпадение с залом говорим первым: это не наша догадка о
        // самочувствии, а то, что человек уже сам решил.
        if verdict == .dietBreak, input.gymDeload == true,
           input.weeksInDeficit < weeksBeforeBreak(rate: input.weeklyRatePercent) {
            return pick(
                String(localized: "В зале идёт разгрузка — лучшей недели для диет-брейка не будет. Тело отдыхает целиком, а жир за сушку уходит так же."),
                String(localized: "В зале разгрузка — хорошая неделя и для брейка."))
        }

        if verdict == .dietBreak, input.weeksInDeficit >= weeksBeforeBreak(rate: input.weeklyRatePercent) {
            return String(format: pick(
                String(localized: "Дефицит идёт %lld недель подряд. Дальше он покупается всё дороже: расход падает, тренировки тяжелеют, а вес всё равно стоит. Неделя-две поддержания вернут и то, и другое — жир за сушку уходит так же."),
                String(localized: "Дефицит идёт %lld недель подряд — пора на неделю-две поддержания.")), input.weeksInDeficit)
        }

        var parts: [String] = []
        if input.stallWeeks >= 2 {
            parts.append(String(format: String(localized: "вес стоит %lld недели подряд"),
                                input.stallWeeks))
        } else if isStalled(input) {
            parts.append(String(localized: "вес за неделю почти не двинулся"))
        }
        if let drop = input.tdeeDropPercent, drop >= notableTDEEDrop {
            parts.append(String(format: String(localized: "расход упал на %@ %%"),
                                String(format: "%.0f", drop)))
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
