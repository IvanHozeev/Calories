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

    /// Сколько поддержания нужно после сушки: половина её длины, но не меньше
    /// четырёх недель.
    static func restWeeks(afterCutOf weeks: Int) -> Int {
        max(4, Int((Double(weeks) / 2).rounded()))
    }

    /// Процент жира, выше которого набирать невыгодно: лишнее уйдёт в жир,
    /// и следующая сушка будет длиннее самого набора.
    static let bulkCeilingBodyFat = 16.0
    /// Ниже этого сушиться незачем — и нечего.
    static let cutFloorBodyFat = 10.0
    /// Выше этого сушиться пора независимо от того, чего хочется.
    static let cutCeilingBodyFat = 20.0

    static func recommend(history: [PhaseRecord],
                          maintenanceSince: Date?,
                          bodyFatPercent: Double?,
                          today: Date = Date()) -> Recommendation {
        let maintenanceWeeks = maintenanceSince.map {
            max(0, Int(today.timeIntervalSince($0) / (7 * 86_400)))
        } ?? 0
        let lastCut = history.filter { $0.intent == .cut }.max { $0.endDate < $1.endDate }

        // Сначала отдых: после сушки телу нужно поддержание, и это не «можно
        // пропустить, если очень хочется».
        if let lastCut {
            let needed = restWeeks(afterCutOf: lastCut.weeks)
            if maintenanceWeeks < needed {
                let left = needed - maintenanceWeeks
                return Recommendation(
                    kind: .maintain,
                    headline: String(format: String(localized: "Поддержание ещё %lld нед."), left),
                    detail: String(format: String(localized: "Прошлая сушка длилась %1$lld нед., на поддержании ты %2$lld. Дай телу вернуть расход и гормоны — обычно это половина длины сушки, но не меньше месяца. Тогда следующий дефицит снова будет работать."), lastCut.weeks, maintenanceWeeks),
                    weeks: left,
                    weeklyRatePercent: nil)
            }
        }

        guard let fat = bodyFatPercent else {
            return Recommendation(
                kind: .maintain,
                headline: String(localized: "Сними замеры"),
                detail: String(localized: "Без процента жира советовать нечего: от него зависит, что выгоднее — сушиться или набирать. Сними шею и пояс в замерах, и приложение посчитает."),
                weeks: nil,
                weeklyRatePercent: nil)
        }

        if fat >= cutCeilingBodyFat {
            return Recommendation(
                kind: .cut,
                headline: String(localized: "Можно сушиться"),
                detail: String(format: String(localized: "Жир около %.0f%%. На таком проценте набор уходит в жир, а не в мышцы: сушка сейчас выгоднее. Темп 0.5%% массы в неделю — быстрее значит терять мышцы."), fat),
                weeks: 12,
                weeklyRatePercent: 0.5)
        }
        if fat <= bulkCeilingBodyFat {
            return Recommendation(
                kind: .bulk,
                headline: String(localized: "Можно набирать"),
                detail: String(format: String(localized: "Жир около %.0f%%. Есть куда набирать: на этом проценте прибавка идёт в мышцы охотнее всего. Темп 0.25%% массы в неделю — быстрее набирается жир, а не сила."), fat),
                weeks: 16,
                weeklyRatePercent: 0.25)
        }
        return Recommendation(
            kind: .maintain,
            headline: String(localized: "Можно и то, и другое"),
            detail: String(format: String(localized: "Жир около %.0f%% — это середина, откуда работает и сушка, и набор. Решает цель: хочешь рельеф к лету — сушка, хочешь массу — набор."), fat),
            weeks: nil,
            weeklyRatePercent: nil)
    }
}
