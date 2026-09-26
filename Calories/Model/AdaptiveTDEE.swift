import Foundation

/// Расход по факту: сколько человек тратит на самом деле, судя по съеденному
/// и по тому, куда идёт вес.
///
/// Формула по профилю (Миффлин × множитель активности) даёт одно число на всех
/// и ошибается на сотни калорий: множитель выбирается на глаз, а расход зависит
/// от работы, шагов, сна и адаптации к дефициту. Живой пример: неделя брейка на
/// 3300 ккал, а вес всё равно ушёл вниз — значит, тратится заметно больше 3300,
/// и держать норму по формуле означает сидеть в дефиците, думая, что ешь вдоволь.
///
/// Считаем из закона сохранения: съеденное минус изменение запасов. Килограмм
/// изменения веса по тренду — это `kcalPerKg` килокалорий.
///
/// Наклон берём линейной регрессией по взвешиваниям окна, а не разностью
/// сглаженного тренда: экспоненциальное сглаживание отстаёт от настоящего
/// наклона примерно на `1/α` дней, и на двух неделях расход занижался бы на
/// несколько сотен килокалорий — ровно там, где точность и нужна.
enum AdaptiveTDEE {
    /// Сколько килокалорий стоит килограмм изменения веса. 7700 — привычная
    /// оценка для жира; вода и гликоген в тренде усредняются.
    static let kcalPerKg: Double = 7700

    /// Сглаживание тренда веса. 0.1 — примерно «неделя памяти».
    static let trendAlpha: Double = 0.1

    /// Сглаживание самой оценки расхода между днями: цель не должна прыгать
    /// на сотни калорий из-за одного праздника или одного солёного ужина.
    static let estimateBeta: Double = 0.25

    /// Ниже какого недельного темпа вес считается стоящим на месте.
    ///
    /// Сто пятьдесят грамм в неделю — это меньше, чем весы врут от соли, воды
    /// и времени взвешивания. Без этой мёртвой зоны шум читался как профицит:
    /// «вес подрос на 200 г» превращалось в «минус 220 ккал расхода», человек
    /// ел меньше, окно помнило прежний рост — и норма ползла вниз день за
    /// днём, хотя он держал поддержание.
    static let steadyWeeklyRateKg: Double = 0.15

    /// Один день истории. `calories` nil — день не записан: такой день не
    /// говорит ни о чём, кроме того, что дневник забыли.
    struct Day: Equatable {
        let date: Date
        let weightKg: Double?
        let calories: Int?

        init(date: Date, weightKg: Double? = nil, calories: Int? = nil) {
            self.date = date
            self.weightKg = weightKg
            self.calories = calories
        }
    }

    /// Насколько оценке можно верить. Считается по полноте данных, а не по
    /// разбросу: неполный дневник врёт сильнее любого шума весов.
    enum Confidence: String {
        case high, medium, low

        var title: String {
            switch self {
            case .high:   return String(localized: "точно")
            case .medium: return String(localized: "примерно")
            case .low:    return String(localized: "грубо")
            }
        }
    }

    struct Result: Equatable {
        /// Расход за окно, ккал/день.
        let tdee: Double
        /// Наклон тренда веса, кг в неделю. Минус — вес уходит.
        let weeklyRateKg: Double
        /// Среднее съеденное за записанные дни окна.
        let meanIntake: Double
        /// Сколько дней в окне записано и сколько взвешиваний в него попало.
        let loggedDays: Int
        let weighIns: Int
        let confidence: Confidence
    }

    /// Тренд веса: экспоненциальное сглаживание с переносом последнего значения
    /// на дни без взвешивания. Нужен для графиков и для того, чтобы показывать
    /// вес без скачков воды; сам расход считается не по нему.
    static func trend(_ days: [Day], alpha: Double = trendAlpha) -> [Date: Double] {
        var result: [Date: Double] = [:]
        var current: Double?
        for day in days.sorted(by: { $0.date < $1.date }) {
            if let weight = day.weightKg {
                current = current.map { alpha * weight + (1 - alpha) * $0 } ?? weight
            }
            if let current { result[day.date] = current }
        }
        return result
    }

    /// Оценка расхода по последним `window` дням.
    ///
    /// nil, когда считать не из чего: мало записанных дней, мало взвешиваний
    /// или они слишком близко друг к другу по времени, чтобы наклон что-то
    /// значил.
    static func estimate(_ days: [Day], window: Int = 14) -> Result? {
        let sorted = days.sorted { $0.date < $1.date }
        guard let last = sorted.last?.date else { return nil }
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -(window - 1), to: calendar.startOfDay(for: last))
        else { return nil }
        let inWindow = sorted.filter { $0.date >= from }

        let logged = inWindow.compactMap { $0.calories }
        let weighIns = inWindow.compactMap { day -> (Double, Double)? in
            guard let weight = day.weightKg else { return nil }
            return (day.date.timeIntervalSince(from) / 86_400, weight)
        }

        // Меньше половины записанных дней — считать нечего: среднее по трём
        // дням из четырнадцати не говорит о том, сколько человек ест.
        guard logged.count >= max(4, window / 2), weighIns.count >= 3 else { return nil }
        // Взвешивания должны покрывать хотя бы неделю: наклон по двум дням —
        // это наклон по воде.
        guard let span = weighIns.last.map({ $0.0 - weighIns[0].0 }), span >= 6 else { return nil }

        let rawSlope = regressionSlope(weighIns)
        // Шум весов трендом не считаем: иначе расход уезжает вслед за водой.
        let slopePerDay = abs(rawSlope * 7) < steadyWeeklyRateKg ? 0 : rawSlope
        let meanIntake = Double(logged.reduce(0, +)) / Double(logged.count)
        let tdee = meanIntake - slopePerDay * kcalPerKg

        let share = Double(logged.count) / Double(inWindow.count)
        let confidence: Confidence
        if share >= 0.85, weighIns.count >= 5 {
            confidence = .high
        } else if share >= 0.6, weighIns.count >= 4 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return Result(tdee: tdee,
                      weeklyRateKg: rawSlope * 7,
                      meanIntake: meanIntake,
                      loggedDays: logged.count,
                      weighIns: weighIns.count,
                      confidence: confidence)
    }

    /// Новая оценка, сглаженная относительно вчерашней. Без сглаживания цель
    /// прыгала бы за каждым всплеском веса; с ним она движется, но плавно.
    static func smoothed(previous: Double?, estimate: Double, beta: Double = estimateBeta) -> Double {
        guard let previous else { return estimate }
        return beta * estimate + (1 - beta) * previous
    }

    /// Наклон методом наименьших квадратов, кг в день.
    private static func regressionSlope(_ points: [(Double, Double)]) -> Double {
        let n = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.0 } / n
        let meanY = points.reduce(0) { $0 + $1.1 } / n
        let numerator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
