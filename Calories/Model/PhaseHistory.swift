import Foundation

/// Закончившийся кусок режима: сушка, набор или поддержание между ними.
///
/// Нужен, чтобы приложение помнило, что было до сегодня. Без этого на вопрос
/// «можно мне уже сушиться?» ответить нечем: ответ зависит от того, сколько
/// длилась прошлая сушка и сколько прошло с её конца, а не от одного веса.
struct PhaseRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var intent: PlanIntent
    var startDate: Date
    var endDate: Date
    var startWeightKg: Double?
    var endWeightKg: Double?
    /// Что было задумано: сколько недель и до какого веса. Нужны сводке, чтобы
    /// сравнить задуманное с прожитым. nil у записей, сделанных раньше.
    var plannedWeeks: Int? = nil
    var plannedEndWeightKg: Double? = nil
    /// Фаза закончена раньше срока — человек завершил план сам.
    var endedEarly: Bool? = nil

    /// Сколько килограммов в неделю ушло или пришло на деле.
    var weeklyChangeKg: Double? {
        guard let changeKg else { return nil }
        let weeks = endDate.timeIntervalSince(startDate) / (7 * 86_400)
        guard weeks >= 0.5 else { return nil }
        return changeKg / weeks
    }

    var weeks: Int {
        max(1, Int((endDate.timeIntervalSince(startDate) / (7 * 86_400)).rounded()))
    }

    var changeKg: Double? {
        guard let startWeightKg, let endWeightKg else { return nil }
        return endWeightKg - startWeightKg
    }
}

/// Что делать дальше: сушиться, набирать или ещё постоять на поддержании.
///
/// Правила простые и намеренно консервативные — они для натурала, у которого
/// нет фармподдержки и права на «догоню потом».
///
/// Между сушками телу нужно время на поддержании: гормоны, щитовидка и
/// адаптация расхода возвращаются не в день окончания дефицита. Привычный
/// ориентир — не меньше половины длины прошлой сушки и не меньше месяца.
enum PhaseAdvice {
    enum Kind: String, Equatable {
        case cut, bulk, maintain
    }

    struct Recommendation: Equatable {
        let kind: Kind
        /// Короткая строка для строки плана на «Сегодня».
        let headline: String
        /// Почему так — на экран плана.
        let detail: String
        /// Сколько недель имеет смысл держать фазу.
        let weeks: Int?
        /// Темп в процентах массы за неделю: 0.5 на сушке, 0.25 на наборе.
        let weeklyRatePercent: Double?
    }

    /// Сколько поддержания нужно после сушки.
    ///
    /// Не «половина сушки всегда». Половина — для глубокой: долгой (от
    /// двенадцати недель) или закончившейся сухой (жир до двенадцати
    /// процентов), где расход, гормоны и аппетит просели сильнее всего. После
    /// короткой мягкой хватает трети. Не меньше двух недель — столько
    /// возвращаются гликоген и вода, и до этого вес ничего не скажет, — и не
    /// больше восьми.
    ///
    /// `creditWeeks` — недели, уже съеденные на поддержании в конце сушки: если
    /// последние дни человек сам ел около расхода, восстановление началось.
    static func restWeeks(afterCutOf weeks: Int, bodyFatPercent: Double? = nil,
                          creditWeeks: Int = 0) -> Int {
        let deep = weeks >= 12 || (bodyFatPercent.map { $0 <= leanBodyFat } ?? false)
        let base = Int((Double(weeks) * (deep ? 0.5 : 1.0 / 3)).rounded())
        return max(minimumRestWeeks, min(8, base) - max(0, creditWeeks))
    }

    /// Меньше этого на поддержании не судим: столько возвращаются гликоген и
    /// вода, и вес до этого прыгает сам по себе.
    static let minimumRestWeeks = 2
    /// Ниже этого процента сушка считается глубокой.
    static let leanBodyFat = 12.0
    /// Вес «стоит», если за неделю тренд сдвинулся меньше чем на столько.
    static let stableWeeklyChangeKg = 0.2

    /// Процент жира, выше которого набирать невыгодно: лишнее уйдёт в жир,
    /// и следующая сушка будет длиннее самого набора.
    static let bulkCeilingBodyFat = 16.0
    /// Ниже этого сушиться незачем — и нечего.
    static let cutFloorBodyFat = 10.0
    /// Выше этого сушиться пора независимо от того, чего хочется.
    static let cutCeilingBodyFat = 20.0

    /// - Parameter brief: человек выбрал короткие объяснения — совет тот же,
    ///   но без разъяснения, зачем телу отдых.
    /// - Parameter weeklyWeightChangeKg: как сдвинулся тренд веса за последнюю
    ///   неделю. Стоит вес после двух недель поддержания — восстановление
    ///   идёт, и ждать формальный срок необязательно.
    /// - Parameter creditWeeks: недели, которые человек уже ел около расхода в
    ///   конце сушки.
    static func recommend(history: [PhaseRecord],
                          maintenanceSince: Date?,
                          bodyFatPercent: Double?,
                          today: Date = Date(),
                          brief: Bool = false,
                          weeklyWeightChangeKg: Double? = nil,
                          creditWeeks: Int = 0) -> Recommendation {
        func pick(_ detailed: String, _ short: String) -> String { brief ? short : detailed }
        let maintenanceWeeks = maintenanceSince.map {
            max(0, Int(today.timeIntervalSince($0) / (7 * 86_400)))
        } ?? 0
        let lastCut = history.filter { $0.intent == .cut }.max { $0.endDate < $1.endDate }

        // Сначала отдых: после сушки телу нужно поддержание, и это не «можно
        // пропустить, если очень хочется».
        var readyEarly = false
        if let lastCut {
            let needed = restWeeks(afterCutOf: lastCut.weeks, bodyFatPercent: bodyFatPercent,
                                   creditWeeks: creditWeeks)
            // Срок — ориентир, а не закон. Две недели прошло и вес стоит —
            // гликоген вернулся, тело держит новую массу, и дальше решают
            // самочувствие и цель, а не календарь.
            let stable = weeklyWeightChangeKg.map { abs($0) < stableWeeklyChangeKg } ?? false
            readyEarly = maintenanceWeeks >= minimumRestWeeks && stable && maintenanceWeeks < needed
            if maintenanceWeeks < needed, !readyEarly {
                let left = needed - maintenanceWeeks
                return Recommendation(
                    kind: .maintain,
                    headline: String(format: String(localized: "Поддержание ещё %lld нед."), left),
                    detail: String(format: pick(String(localized: "Сушка длилась %1$lld нед., на поддержании ты %2$lld. Срок — по длине и глубине сушки, а не половина всегда. Через две-три недели смотри на себя: вес стоит, голод ровный, силы на тренировках вернулись — можно двигаться дальше и раньше."),
                                                String(localized: "Сушка длилась %1$lld нед., поддержания %2$lld. Вес встанет и голод уйдёт — можно раньше.")), lastCut.weeks, maintenanceWeeks),
                    weeks: left,
                    weeklyRatePercent: nil)
            }
        }

        let early = readyEarly
            ? pick(String(localized: "Вес стоит уже неделю — восстановление идёт, формальный срок можно не ждать. Если голод ровный и силы вернулись: "),
                   String(localized: "Вес стоит — можно не ждать срока. "))
            : ""

        guard let fat = bodyFatPercent else {
            return Recommendation(
                kind: .maintain,
                headline: String(localized: "Сними замеры"),
                detail: pick(String(localized: "Без процента жира советовать нечего: от него зависит, что выгоднее — сушиться или набирать. Сними шею и пояс в замерах, и приложение посчитает."),
                             String(localized: "Нужен процент жира: сними шею и пояс в замерах.")),
                weeks: nil,
                weeklyRatePercent: nil)
        }

        if fat >= cutCeilingBodyFat {
            return Recommendation(
                kind: .cut,
                headline: String(localized: "Можно сушиться"),
                detail: early + String(format: pick(String(localized: "Жир около %.0f%%. На таком проценте набор уходит в жир, а не в мышцы: сушка сейчас выгоднее. Темп 0.5%% массы в неделю — быстрее значит терять мышцы."),
                                            String(localized: "Жир около %.0f%% — выгоднее сушка, темп 0.5%% массы в неделю.")), fat),
                weeks: 12,
                weeklyRatePercent: 0.5)
        }
        if fat <= bulkCeilingBodyFat {
            return Recommendation(
                kind: .bulk,
                headline: String(localized: "Можно набирать"),
                detail: early + String(format: pick(String(localized: "Жир около %.0f%%. Есть куда набирать: на этом проценте прибавка идёт в мышцы охотнее всего. Темп 0.25%% массы в неделю — быстрее набирается жир, а не сила."),
                                            String(localized: "Жир около %.0f%% — можно набирать, темп 0.25%% массы в неделю.")), fat),
                weeks: 16,
                weeklyRatePercent: 0.25)
        }
        return Recommendation(
            kind: .maintain,
            headline: String(localized: "Можно и то, и другое"),
            detail: early + String(format: pick(String(localized: "Жир около %.0f%% — это середина, откуда работает и сушка, и набор. Решает цель: хочешь рельеф к лету — сушка, хочешь массу — набор."),
                                        String(localized: "Жир около %.0f%% — работает и сушка, и набор. Решает цель.")), fat),
            weeks: nil,
            weeklyRatePercent: nil)
    }
}
