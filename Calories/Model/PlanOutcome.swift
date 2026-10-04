import Foundation

// Чем кончился план и что с телом: состав изменения веса, соблюдение,
// исход фазы и достижения.

struct CompositionChange {
    let fromDate: Date
    let toDate: Date
    let startWeightKg: Double
    let endWeightKg: Double
    let startFatPercent: Double
    let endFatPercent: Double

    var startFatKg: Double { startWeightKg * startFatPercent / 100 }
    var endFatKg: Double { endWeightKg * endFatPercent / 100 }
    var startLeanKg: Double { startWeightKg - startFatKg }
    var endLeanKg: Double { endWeightKg - endFatKg }

    var weightDeltaKg: Double { endWeightKg - startWeightKg }
    var fatDeltaKg: Double { endFatKg - startFatKg }
    var leanDeltaKg: Double { endLeanKg - startLeanKg }

    /// Сколько дней прошло между замерами.
    var days: Int {
        max(0, Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day ?? 0)
    }

    /// Раньше этого срока сравнивать состав не о чем.
    ///
    /// За несколько дней вес меняется водой и гликогеном сильнее, чем жиром:
    /// соль, углеводы накануне и недосып дают больше килограмма разброса, а
    /// запланированный дефицит за три дня — граммов триста. Две недели — тот же
    /// порог, с которого приложение берётся считать расход по факту, и по той
    /// же причине: короче окно, и меряешь не жир, а воду.
    static let minimumDays = 14

    /// Насколько метод вообще способен различить.
    ///
    /// У Navy погрешность около ±3% жира, что на 77 кг даёт ±2.3 кг сухой массы.
    /// Объявлять «ты потерял 400 г мышц» внутри этого коридора — врать точностью,
    /// которой нет, поэтому всё, что меньше, честно называется погрешностью.
    var noiseKg: Double { endWeightKg * 0.03 }

    var verdict: CompositionVerdict {
        if abs(leanDeltaKg) <= noiseKg { return .withinNoise }
        return leanDeltaKg < 0 ? .leanLoss : .leanGain
    }
}

/// Что фаза сделала с составом тела — с оглядкой на то, зачем она шла.
///
/// Без намерения вердикт по составу не полон. «Сухая масса держится» на сушке —
/// это успех, а на наборе — провал: набирали как раз её. Прежний вердикт
/// намерения не знал и на неудавшемся наборе честно докладывал, что всё в
/// порядке.
enum PhaseCompositionVerdict {
    /// Фаза сделала то, зачем была.
    case worked
    /// Сделала, но дорого: сушка за счёт мышц, набор в жир.
    case costly
    /// Не сделала ничего — вес не сдвинулся дальше погрешности весов.
    case stalled
    /// Между замерами слишком мало дней, чтобы судить.
    case tooSoon
    /// Жир ушёл, сухая масса прибавила. Лучшее, что может случиться, и
    /// случается это независимо от того, какая фаза шла: вес при этом может
    /// стоять, расти или падать — судить по нему тут бессмысленно.
    case recomposition

    var title: String {
        switch self {
        case .worked:       return String(localized: "Фаза отработала")
        case .costly:       return String(localized: "Отработала дорого")
        case .stalled:      return String(localized: "Вес не сдвинулся")
        case .tooSoon:      return String(localized: "Рано судить")
        case .recomposition: return String(localized: "Жир вниз, мышцы вверх")
        }
    }

    var icon: String {
        switch self {
        case .worked:        return "checkmark.circle.fill"
        case .costly:        return "exclamationmark.triangle.fill"
        case .stalled:       return "pause.circle.fill"
        case .tooSoon:       return "hourglass"
        case .recomposition: return "arrow.up.arrow.down.circle.fill"
        }
    }
}

extension CompositionChange {
    /// Насколько весы вообще различают изменение трендового веса.
    /// Это не погрешность процента жира — она на порядок больше и живёт
    /// в `noiseKg`, — а просто цена дня на весах.
    static let scaleNoiseKg = 0.5

    /// Какая часть изменения веса пришлась на жир. Ничего, если вес стоит.
    ///
    /// Ничего и тогда, когда жир с весом разошлись в разные стороны: вес вырос,
    /// а жира стало меньше — это рекомпозиция, и «доля» тут выдаёт что-нибудь
    /// вроде «−302% изменения веса», то есть арифметически верную бессмыслицу.
    var fatShareOfChange: Double? {
        guard abs(weightDeltaKg) > Self.scaleNoiseKg else { return nil }
        guard (fatDeltaKg >= 0) == (weightDeltaKg >= 0) else { return nil }
        return fatDeltaKg / weightDeltaKg
    }

    /// Жир ушёл, а сухая масса прибавила — заметнее, чем метод способен наврать.
    ///
    /// Требование строгое только к сухой массе: её прирост и есть новость.
    /// От жира достаточно, чтобы он не вырос, — иначе «рекомпозицией» назвался
    /// бы обычный набор, где выросло всё сразу.
    var isRecomposition: Bool {
        leanDeltaKg > noiseKg && fatDeltaKg <= 0
    }

    func verdict(for intent: PlanIntent) -> PhaseCompositionVerdict {
        // Срок — раньше всего остального. На трёх днях вердикт получался
        // особенно глупым: вес ушёл на триста граммов — ровно в темп плана, —
        // а порог «сдвинулся» написан под полкилограмма и выдавал «вес не
        // сдвинулся, дефицита нет». Приложение обвиняло человека в том, что
        // просто прошло мало времени.
        if days < Self.minimumDays { return .tooSoon }

        // Рекомпозиция судится раньше намерения: жир вниз, мышцы вверх — это
        // успех в любой фазе, и по весу его не увидеть вовсе. Раньше такой
        // исход на поддержании объявлялся «дорогим» просто потому, что вес
        // сдвинулся, — то есть лучший результат называли худшим.
        if isRecomposition { return .recomposition }

        let moved = abs(weightDeltaKg) > Self.scaleNoiseKg
        switch intent {
        case .cut:
            if !moved { return .stalled }
            // Мышцы уходят заметнее, чем метод способен наврать, — значит
            // уходят на самом деле.
            return leanDeltaKg < -noiseKg ? .costly : .worked
        case .bulk:
            if !moved { return .stalled }
            if leanDeltaKg > noiseKg { return .worked }
            // Вес вырос, а сухая масса — нет. Это набранный жир, даже если
            // формально изменение сухой укладывается в погрешность.
            return weightDeltaKg > 0 ? .costly : .stalled
        case .maintenance:
            // На поддержании смотрим не на то, сдвинулся ли вес, а на то, чем
            // он сдвинулся: набранный жир — это разошедшаяся норма, а вода
            // и гликоген на пару килограммов — обычная неделя.
            if !moved { return .worked }
            // Основную часть сдвига дал жир — норма разошлась с расходом.
            // Если же вес прибавился водой и гликогеном, это обычная неделя,
            // а не провал: в пределах погрешности весов такое бывает каждую.
            let fatShare = fatDeltaKg / weightDeltaKg
            return fatShare > 0.5 ? .costly : .worked
        }
    }

    /// Что с этим делать. Текст зависит и от вердикта, и от намерения: «ешь
    /// больше» на сушке и на наборе — противоположные советы.
    func advice(for intent: PlanIntent) -> String {
        if verdict(for: intent) == .tooSoon {
            return String(format: String(localized: "Между замерами %lld дн. За такой срок вес меняется водой и гликогеном сильнее, чем жиром: сравнивать состав можно с двух недель."), days)
        }
        if verdict(for: intent) == .recomposition {
            return String(localized: "Жир ушёл, а сухая масса прибавила — так бывает у новичков, после перерыва и на возврате к прежней форме. Вес при этом может стоять или даже расти: смотреть надо на состав.")
        }
        switch (intent, verdict(for: intent)) {
        case (.cut, .worked):
            return String(localized: "Вес уходит жиром, сухая масса на месте — так дефицит и должен выглядеть.")
        case (.cut, .costly):
            return String(localized: "Уходит не только жир. Смягчи дефицит или подними норму белка — на сушке чинят это в первую очередь.")
        case (.cut, .stalled):
            return String(localized: "Вес стоит. Либо дефицита нет на самом деле, либо считается не всё съеденное.")
        case (.bulk, .worked):
            return String(localized: "Прибавка идёт сухой массой — темп можно не трогать.")
        case (.bulk, .costly):
            return String(localized: "Прибавка идёт в основном жиром. Сбавь темп: набирать быстрее пола процента в неделю натуралу почти нечем.")
        case (.bulk, .stalled):
            return String(localized: "Вес стоит. Профицита нет — либо норма занижена, либо съедается не столько, сколько записано.")
        case (.maintenance, .worked):
            return String(localized: "Вес держится — поддержание делает ровно то, зачем нужно.")
        case (.maintenance, .costly):
            return String(localized: "Вес поехал. На поддержании это значит, что норма разошлась с фактическим расходом.")
        case (.maintenance, .stalled):
            return String(localized: "Вес держится — поддержание делает ровно то, зачем нужно.")
        case (_, .recomposition), (_, .tooSoon):
            // Разобрано выше, до switch: эти два совета одни на все фазы.
            return ""
        }
    }
}

enum CompositionVerdict {
    /// Сухая масса просела заметнее погрешности метода.
    case leanLoss
    /// Сухая масса выросла заметнее погрешности.
    case leanGain
    /// Разница меньше того, что метод различает.
    case withinNoise

    var title: String {
        switch self {
        case .leanLoss:    return String(localized: "Сухая масса просела")
        case .leanGain:    return String(localized: "Сухая масса выросла")
        case .withinNoise: return String(localized: "Сухая масса держится")
        }
    }

    var explanation: String {
        switch self {
        case .leanLoss:
            return String(localized: "Вес уходит не только за счёт жира. Стоит смягчить дефицит или поднять норму белка — на сушке это первое, что чинят.")
        case .leanGain:
            return String(localized: "Редкий и хороший случай: жир уходит, а сухая масса прибавляет. Так бывает у новичков и после долгого перерыва.")
        case .withinNoise:
            return String(localized: "Изменение сухой массы меньше погрешности метода — считай, что она на месте, а вес уходит жиром.")
        }
    }
}

/// С чем план пришёл к финишу.
struct PlanOutcome {
    let plan: Plan
    /// Тренд последних взвешиваний, а не последнее число: вес скачет на килограмм
    /// от воды, и подводить итог по одному утру нечестно.
    let finalWeightKg: Double?

    var changeKg: Double? {
        finalWeightKg.map { $0 - plan.startWeightKg }
    }

    /// Сколько не дошли до цели. Ноль и меньше — цель взята.
    var shortfallKg: Double? {
        guard let finalWeightKg else { return nil }
        let planned = plan.totalWeightChangeKg
        if planned < 0 { return finalWeightKg - plan.targetWeightKg }
        if planned > 0 { return plan.targetWeightKg - finalWeightKg }
        return abs(finalWeightKg - plan.targetWeightKg)
    }

    /// Для поддержания цель считается взятой, если удержались в полукилограмме.
    var reachedTarget: Bool {
        guard let shortfallKg else { return false }
        return plan.totalWeightChangeKg == 0 ? shortfallKg <= 0.5 : shortfallKg <= 0
    }
}

enum PlanStatus {
    case insufficientData
    case onTrack
    case ahead
    case behind

    /// Допуск, внутри которого план считается выполняемым.
    ///
    /// Пропорционален тому, сколько фаза вообще собиралась сдвинуть: у
    /// поддержания это ноль, и остаётся нижняя граница в 300 г — шум весов,
    /// утренний стул и вчерашняя соль.
    ///
    /// После подъёма калорий допуск шире на пару килограммов: возвращаются
    /// гликоген и вода, и без этого приложение объявило бы провалом ровно то,
    /// что само же назначило переходом.
    static func tolerance(plannedChangeKg: Double, settling: Bool) -> Double {
        let proportional = abs(plannedChangeKg) * 0.05
        return settling ? max(Plan.settlingToleranceKg, proportional) : max(0.3, proportional)
    }

    /// Вердикт по отклонению от прогноза.
    ///
    /// `direction` — куда фаза ведёт вес: меньше нуля вниз, больше нуля вверх,
    /// ноль — поддержание. У поддержания «впереди» не бывает: любой уход от
    /// нуля — уход в сторону, в какую бы сторону он ни был.
    static func verdict(deviationKg: Double, direction: Double, tolerance: Double) -> PlanStatus {
        if abs(deviationKg) <= tolerance { return .onTrack }
        if direction == 0 { return .behind }
        let movingAwayFromTarget = (direction < 0 && deviationKg > 0) || (direction > 0 && deviationKg < 0)
        return movingAwayFromTarget ? .behind : .ahead
    }
}

/// Чего именно не хватает для расчёта тренда. Нужно, чтобы вместо пассивных серых часов
/// показать пользователю, сколько ещё шагов до появления аналитики.
struct AdherenceDataGap {
    let weighInsLogged: Int
    let weighInsRequired: Int
    let daysUntilTrend: Int

    /// 0…1 — доля собранного, для прогресс-бара.
    var progress: Double {
        let byWeighIns = weighInsRequired > 0
            ? min(Double(weighInsLogged) / Double(weighInsRequired), 1)
            : 1
        let byDays = daysUntilTrend <= 0 ? 1.0 : max(0, Double(7 - daysUntilTrend) / 7)
        return min(byWeighIns, byDays)
    }
}

/// Сверка факта (по журналу взвешиваний) с линейным прогнозом плана.
/// Не хранится — считается на лету в CalorieStore.planAdherence().
struct PlanAdherence {
    let expectedWeightToday: Double
    let actualWeightToday: Double?
    let observedWeeklyRateKg: Double?
    let projectedEndDate: Date?
    let projectedWeightAtPlanEnd: Double?
    let recalibratedDailyCalories: Int?
    let status: PlanStatus
    let dataGap: AdherenceDataGap?
    /// Вес ещё устаканивается после подъёма калорий — судить по нему рано.
    var isSettlingAfterIncrease: Bool = false

    /// Целевой вес фазы и куда она ведёт: нужны, чтобы понять, о чём говорит
    /// прогноз — обгоняет он план или отстаёт от него.
    var phaseTargetWeightKg: Double = 0
    /// −1 на снижении, +1 на наборе, 0 на поддержании.
    var direction: Double = 0
    /// Когда фаза должна кончиться по плану.
    var phaseEnd: Date = .distantPast
    /// Прямая по взвешиваниям фазы: темп и его погрешность. nil — взвешиваний
    /// мало, и прямую строить не из чего.
    var trendFit: WeightTrendFit? = nil

    /// Коридор даты финиша: та же цель при темпе на границах погрешности.
    ///
    /// Две даты, а не одна: «цель к 3 ноября» при трёх взвешиваниях — точность,
    /// которой нет. Nil, когда темп не отличим от нуля: тогда дата не
    /// существует вовсе, и называть её нельзя.
    func projectedEndRange(from today: Date = Date()) -> ClosedRange<Date>? {
        guard let trendFit, trendFit.isDistinguishableFromZero, let actual = actualWeightToday else { return nil }
        let remaining = phaseTargetWeightKg - actual
        let dates: [Date] = [trendFit.range.lowerBound, trendFit.range.upperBound].compactMap { rate in
            guard rate != 0 else { return nil }
            let weeks = remaining / rate
            guard weeks.isFinite, weeks > 0, weeks < 260 else { return nil }
            return Calendar.current.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: today)
        }
        guard let first = dates.min(), let last = dates.max(), first != last else { return nil }
        return first...last
    }

    /// Темп измерен, но от нуля не отличается: данных мало или вес стоит.
    var rateIsIndistinguishableFromZero: Bool {
        guard let trendFit else { return false }
        return !trendFit.isDistinguishableFromZero
    }

    var deviationKg: Double? {
        guard let actualWeightToday else { return nil }
        return actualWeightToday - expectedWeightToday
    }

    /// Говорит ли темп то же, что и положение.
    ///
    /// Вердикт «опережаешь» считается по весу: тренд ниже ожидаемого. Прогноз
    /// считается по темпу за фазу. Эти двое расходятся, когда вес ушёл вниз
    /// рывком в начале, а потом встал: по положению человек впереди, а по
    /// темпу не дойдёт до цели никогда. Пока они расходятся, предлагать «есть
    /// больше» нельзя — это совет ускорить то, что и так стоит.
    var projectionAgreesWithPlan: Bool {
        guard let projectedEndDate else { return false }
        return projectedEndDate <= phaseEnd.addingTimeInterval(3 * 86400)
    }

    /// Вес, до которого при нынешнем темпе дойдёшь к концу фазы, — но только
    /// если он действительно глубже цели.
    ///
    /// Иначе «углубить цель» предлагало цель слабее нынешней: при почти нулевом
    /// темпе прогноз выходит выше целевого веса, и кнопка звала поднять цель,
    /// называя это углублением.
    var deeperTarget: Double? {
        guard direction != 0, let projected = projectedWeightAtPlanEnd else { return nil }
        let rounded = (projected * 10).rounded() / 10
        // Глубже цели — это ниже на снижении и выше на наборе, то есть дальше
        // по направлению фазы.
        let gain = (rounded - phaseTargetWeightKg) * direction
        guard gain >= 0.2 else { return nil }
        return rounded
    }
}

/// Достижение. Считается на лету из стриков — нигде не хранится, поэтому не может
/// рассинхронизироваться с фактическими данными и не требует миграций.
struct Achievement: Identifiable {
    enum Kind: String, CaseIterable {
        case firstWeek, disciplineMaster, proteinMaster, ironWill
    }

    let kind: Kind
    let current: Int
    let target: Int

    var id: String { kind.rawValue }
    var isUnlocked: Bool { current >= target }
    var progress: Double { target > 0 ? min(Double(current) / Double(target), 1) : 0 }

    var title: String {
        switch kind {
        case .firstWeek:        return String(localized: "Первая неделя")
        case .disciplineMaster: return String(localized: "Мастер дисциплины")
        case .proteinMaster:    return String(localized: "Мастер белка")
        case .ironWill:         return String(localized: "Железная воля")
        }
    }

    var requirement: String {
        switch kind {
        case .firstWeek:        return String(localized: "7 дней подряд в пределах дневной нормы калорий.")
        case .disciplineMaster: return String(localized: "14 дней подряд в пределах дневной нормы калорий.")
        case .proteinMaster:    return String(localized: "5 дней подряд закрыта норма белка.")
        case .ironWill:         return String(localized: "30 дней подряд с записями в дневнике — попадание в цель не требуется.")
        }
    }

    var icon: String {
        switch kind {
        case .firstWeek:        return "flame.fill"
        case .disciplineMaster: return "trophy.fill"
        case .proteinMaster:    return "bolt.fill"
        case .ironWill:         return "star.fill"
        }
    }
}
