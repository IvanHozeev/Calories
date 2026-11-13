import Foundation

/// Когда строке «Взвешивание» есть смысл висеть на «Сегодня».
///
/// Вес для тренда снимают утром, натощак: вечером он выше на съеденное и
/// выпитое за день, и такое число тренд только сбивает. Строка, висящая в
/// восемь вечера, звала делать то, что делать поздно. Из меню «+» взвеситься
/// можно в любое время — уходит только напоминание.
enum WeighInWindow {
    /// Сколько часов после подъёма утро ещё длится.
    static let hoursAfterWake = 4.0
    /// Раньше этого часа окно не закрывается, даже если подъём в пять:
    /// до десяти утра вес всё ещё утренний.
    static let earliestClose = 10.0

    /// Открыто ли окно в `now` при подъёме в `wakeHour` (дробные часы: 7.5 — это 7:30).
    static func isOpen(now: Date, wakeHour: Double, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        return hour < max(wakeHour + hoursAfterWake, earliestClose)
    }
}

/// Сколько человек обычно кладёт того или иного продукта.
///
/// По истории записей, а не по порции из базы: «100 г» у творога — это
/// единица измерения, а не то, сколько его едят. Своя порция рядом с
/// продуктом превращает выбор в одно касание вместо подбора граммов.
enum UsualPortion {
    /// Сколько раз продукт должен встретиться с граммами, чтобы порция
    /// считалась привычкой, а не случаем.
    static let minimumTimes = 2
    /// За сколько дней смотреть: порции меняются вместе с планом, и
    /// прошлогодний набор массы не должен диктовать сегодняшнюю тарелку.
    static let days = 90

    /// Привычная порция для каждого продукта, по имени в нижнем регистре.
    ///
    /// Медиана, а не среднее: один двойной ужин не должен сдвигать
    /// обычную тарелку. Округление до пяти граммов — точнее весы на кухне
    /// всё равно не отмеряют, а «183 г» читается как расчёт, а не привычка.
    static func compute(parts: [EntryComponent]) -> [String: Double] {
        var grams: [String: [Double]] = [:]
        for part in parts {
            guard let g = part.grams, g > 0 else { continue }
            grams[part.name.lowercased(), default: []].append(g)
        }
        return grams.compactMapValues { values in
            guard values.count >= minimumTimes else { return nil }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
            return max(5, (median / 5).rounded() * 5)
        }
    }
}

/// Что человек ел вчера примерно в это же время.
///
/// День повторяет день чаще, чем кажется: тот же завтрак перед работой,
/// тот же перекус после зала. Первая строка листа добавления с этим
/// приёмом экономит поиск ровно в тот момент, когда он чаще всего не нужен.
enum YesterdayAtThisTime {
    /// Насколько вчерашняя запись может отстоять от «сейчас минус сутки».
    static let window: TimeInterval = 90 * 60

    /// Индекс ближайшей по времени вчерашней записи — или nil, если в окне ничего нет.
    static func closest(to now: Date, among dates: [Date], calendar: Calendar = .current) -> Int? {
        guard let target = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        var best: (index: Int, distance: TimeInterval)?
        for (index, date) in dates.enumerated() {
            guard calendar.isDate(date, inSameDayAs: target) else { continue }
            let distance = abs(date.timeIntervalSince(target))
            guard distance <= window else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }
}

extension CalorieStore {
    /// Привычные порции продуктов за последние `UsualPortion.days` дней.
    func usualPortions(now: Date = Date()) -> [String: Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -UsualPortion.days, to: now) ?? .distantPast
        let parts = entries.filter { $0.date >= cutoff }.flatMap(\.composition)
        return UsualPortion.compute(parts: parts)
    }

    /// Вчерашняя запись около этого же часа — или nil.
    func entryYesterdayAtThisTime(now: Date = Date()) -> FoodEntry? {
        let candidates = entries
        return YesterdayAtThisTime.closest(to: now, among: candidates.map(\.date)).map { candidates[$0] }
    }

    /// Привычный приём для текущего часа — его предлагают в пустой день.
    func usualMealNow(now: Date = Date()) -> UsualMeal.Suggestion? {
        usualMeals(period: MealPeriod.period(for: now)).first
    }
}
