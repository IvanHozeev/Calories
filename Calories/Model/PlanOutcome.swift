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

    var title: String {
        switch self {
        case .worked:  return String(localized: "Фаза отработала")
        case .costly:  return String(localized: "Отработала дорого")
        case .stalled: return String(localized: "Вес не сдвинулся")
        }
    }

    var icon: String {
        switch self {
        case .worked:  return "checkmark.circle.fill"
        case .costly:  return "exclamationmark.triangle.fill"
        case .stalled: return "pause.circle.fill"
        }
    }
}

extension CompositionChange {
    /// Насколько весы вообще различают изменение трендового веса.
    /// Это не погрешность процента жира — она на порядок больше и живёт
    /// в `noiseKg`, — а просто цена дня на весах.
    static let scaleNoiseKg = 0.5

    /// Какая часть изменения веса пришлась на жир. Ничего, если вес стоит.
    var fatShareOfChange: Double? {
        guard abs(weightDeltaKg) > Self.scaleNoiseKg else { return nil }
        return fatDeltaKg / weightDeltaKg
    }

    func verdict(for intent: PlanIntent) -> PhaseCompositionVerdict {
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
            // На поддержании успех — это когда ничего не произошло.
            return moved ? .costly : .worked
        }
    }

    /// Что с этим делать. Текст зависит и от вердикта, и от намерения: «ешь
    /// больше» на сушке и на наборе — противоположные советы.
    func advice(for intent: PlanIntent) -> String {
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

    var deviationKg: Double? {
        guard let actualWeightToday else { return nil }
        return actualWeightToday - expectedWeightToday
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
