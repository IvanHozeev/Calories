import Foundation

/// Объяснитель веса на данных дневника.
///
/// Решения владельца от 13.11: вес — первое взвешивание за день (утреннее,
/// натощак: ровно то число, что пугает); поздний ужин — последний приём ближе
/// чем за три часа до отбоя из расписания приёмов; порог отклонения 0,5 кг.
extension CalorieStore {
    /// Сколько дней истории смотрим.
    static let explainerWindowDays = 180
    /// За сколько часов до отбоя ужин уже поздний.
    static let lateMealHoursBeforeSleep = 3.0

    /// История пар «вчера → утро», сегодняшняя пара (если сегодня
    /// взвешивались) и сегодняшний день как причина завтрашнего утра — для
    /// прогноза: его отклонение ещё неизвестно и стоит нулём, а тренд, от
    /// которого оно будет отсчитано, — `trendTomorrow`.
    func weightExplainerInput(now: Date = Date(), sleep: Date = MealScheduleSettings.shared.sleep)
        -> (history: [WeightExplainer.Day], today: WeightExplainer.Day?,
            tonight: WeightExplainer.Day?, trendTomorrow: Double?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // Первое взвешивание каждого дня.
        var firstWeight: [Date: Double] = [:]
        for entry in weightEntries.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: entry.date)
            if firstWeight[day] == nil { firstWeight[day] = entry.weightKg }
        }

        func shift(_ day: Date, _ by: Int) -> Date { calendar.date(byAdding: .day, value: by, to: day) ?? day }

        // Тренд — по неделе до дня, без самого дня: иначе сегодняшний скачок
        // тянул бы тренд за собой и сам себя наполовину гасил.
        func trend(before day: Date) -> Double? {
            let values = (1...7).compactMap { firstWeight[shift(day, -$0)] }
            guard values.count >= 3 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        var carbsCache: [Date: Double?] = [:]
        func carbs(on day: Date) -> Double? {
            if let cached = carbsCache[day] { return cached }
            let entries = entriesByDay[day] ?? []
            let value: Double? = entries.isEmpty ? nil : entries.reduce(0) { $0 + $1.carbs }
            carbsCache[day] = value
            return value
        }

        var sodiumCache: [Date: Double?] = [:]
        func sodium(on day: Date) -> Double? {
            if let cached = sodiumCache[day] { return cached }
            let micros = micronutrients(on: day)
            // Натрий складывается, и неполный день его занижает: считаем
            // только почти целиком известные дни.
            let value: Double? = micros.coverage >= 0.9 ? micros.totals[.sodium] : nil
            sodiumCache[day] = value
            return value
        }

        /// Личное среднее за 28 дней до `day` — не норма из профиля.
        func personalMean(before day: Date, _ value: (Date) -> Double?) -> Double? {
            let values = (1...28).compactMap { value(shift(day, -$0)) }
            guard values.count >= 7 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        let sleepParts = calendar.dateComponents([.hour, .minute], from: sleep)
        var sleepHour = Double(sleepParts.hour ?? 23) + Double(sleepParts.minute ?? 0) / 60
        if sleepHour < 12 { sleepHour += 24 }       // отбой после полуночи
        let lateFrom = sleepHour - Self.lateMealHoursBeforeSleep

        func lateHours(on day: Date) -> Double {
            guard let last = (entriesByDay[day] ?? []).map(\.date).max() else { return 0 }
            let parts = calendar.dateComponents([.hour, .minute], from: last)
            let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            return max(0, hour - lateFrom)
        }

        /// Причины, которые день `yesterday` оставляет следующему утру.
        func causes(of yesterday: Date, residual: Double) -> WeightExplainer.Day? {
            let fasted = isFastDay(yesterday)
            guard fasted || carbs(on: yesterday) != nil,
                  let carbsMean = personalMean(before: yesterday, carbs) else { return nil }
            let sodiumDelta: Double? = {
                guard let value = sodium(on: yesterday),
                      let mean = personalMean(before: yesterday, sodium) else { return nil }
                return value - mean
            }()
            return .init(residualKg: residual,
                         carbsDeltaG: (carbs(on: yesterday) ?? 0) - carbsMean,
                         sodiumDeltaMg: sodiumDelta,
                         lateHours: lateHours(on: yesterday),
                         afterFast: fasted)
        }

        func pair(for day: Date) -> WeightExplainer.Day? {
            guard let weight = firstWeight[day], let base = trend(before: day) else { return nil }
            return causes(of: shift(day, -1), residual: weight - base)
        }

        let history = (1...Self.explainerWindowDays).reversed().compactMap { pair(for: shift(today, -$0)) }
        let tomorrow = shift(today, 1)
        return (history, pair(for: today), causes(of: today, residual: 0), trend(before: tomorrow))
    }

    /// Прогноз на завтрашнее утро — или nil, когда честно сказать нечего.
    ///
    /// Только вечером, за три часа до отбоя и позже: днём еда ещё не съедена,
    /// и прогноз гадал бы по половине дня.
    func weightForecast(now: Date = Date(), sleep: Date = MealScheduleSettings.shared.sleep)
        -> (forecast: WeightExplainer.Forecast, trendKg: Double)? {
        let calendar = Calendar.current
        let sleepParts = calendar.dateComponents([.hour, .minute], from: sleep)
        var sleepHour = Double(sleepParts.hour ?? 23) + Double(sleepParts.minute ?? 0) / 60
        if sleepHour < 12 { sleepHour += 24 }
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let hour = Double(nowParts.hour ?? 0) + Double(nowParts.minute ?? 0) / 60
        guard hour >= sleepHour - Self.lateMealHoursBeforeSleep else { return nil }

        let input = weightExplainerInput(now: now, sleep: sleep)
        guard let tonight = input.tonight, let trend = input.trendTomorrow,
              let forecast = WeightExplainer.forecast(history: input.history, tonight: tonight)
        else { return nil }
        return (forecast, trend)
    }

    /// Объяснение сегодняшнего отклонения — или nil, когда честно сказать нечего.
    func weightExplanation(now: Date = Date()) -> WeightExplainer.Explanation? {
        let input = weightExplainerInput(now: now)
        guard let today = input.today else { return nil }
        return WeightExplainer.explain(history: input.history, today: today)
    }
}
