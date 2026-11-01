import Foundation

/// Приёмы пищи за день. Границы часов подобраны под привычный распорядок:
/// прежняя сетка считала ужином всё с 15:00, из-за чего полдник попадал в ужин,
/// а поздний ужин — в «Перекус».
///
/// Порядок объявления задаёт порядок на экранах, поэтому он хронологический.
enum MealPeriod: String, CaseIterable {
    case breakfast = "Завтрак"
    case secondBreakfast = "Второй завтрак"
    case lunch = "Обед"
    case afternoonSnack = "Полдник"
    case dinner = "Ужин"
    case secondDinner = "Второй ужин"
    case nightSnack = "Перекус"

    /// Подпись идущего сейчас окна: «Время завтрака», «Время обеда».
    ///
    /// Отдельной строкой на каждый приём, а не подстановкой в шаблон: по-русски
    /// нужен родительный падеж, и «Время завтрак» из склейки не спасти.
    var timeTitle: String {
        switch self {
        case .breakfast:       return String(localized: "Время завтрака")
        case .secondBreakfast: return String(localized: "Время второго завтрака")
        case .lunch:           return String(localized: "Время обеда")
        case .afternoonSnack:  return String(localized: "Время полдника")
        case .dinner:          return String(localized: "Время ужина")
        case .secondDinner:    return String(localized: "Время второго ужина")
        case .nightSnack:      return String(localized: "Перекус")
        }
    }

    /// Диапазон часов приёма. Ночной перекус переходит через полночь,
    /// поэтому его границы проверяются отдельно.
    var hours: Range<Int> {
        switch self {
        case .breakfast:       return 5..<10
        case .secondBreakfast: return 10..<12
        case .lunch:           return 12..<15
        case .afternoonSnack:  return 15..<17
        case .dinner:          return 17..<21
        case .secondDinner:    return 21..<23
        case .nightSnack:      return 23..<29   // 23:00–05:00, см. period(for:)
        }
    }

    /// Час, на который ставится запись при ручном выборе приёма — середина диапазона.
    var representativeHour: Int {
        switch self {
        case .breakfast:       return 8
        case .secondBreakfast: return 11
        case .lunch:           return 13
        case .afternoonSnack:  return 16
        case .dinner:          return 19
        case .secondDinner:    return 22
        case .nightSnack:      return 23
        }
    }

    static func period(for date: Date) -> MealPeriod {
        let hour = Calendar.current.component(.hour, from: date)
        for period in MealPeriod.allCases where period != .nightSnack {
            if period.hours.contains(hour) { return period }
        }
        return .nightSnack
    }

}

extension MealPeriod {
    /// День, разложенный по приёмам пищи.
    ///
    /// Живёт здесь, а не на экране, потому что экранов два: «Сегодня» и любой
    /// день из истории. Пока это была часть перестройки кэшей, история
    /// показывала еду одним плоским списком — тот же день выглядел
    /// по-разному в зависимости от того, с какой стороны на него смотрят.
    static func group(_ entries: [FoodEntry]) -> [(period: MealPeriod, entries: [FoodEntry])] {
        let byPeriod = Dictionary(grouping: entries) { MealPeriod.period(for: $0.date) }
        // День читается сверху вниз, как он и прожит: завтрак, обед, ужин.
        // Внутри приёма — тоже по времени: порядок, в котором ели.
        return allCases.compactMap { period in
            guard let entries = byPeriod[period], !entries.isEmpty else { return nil }
            return (period, entries.sorted { $0.date < $1.date })
        }
        .sorted { lhs, rhs in
            // Порядок — по часам, а не по типу приёма.
            //
            // «Перекус» живёт с 23:00 до 05:00, и раньше он безусловно уходил
            // в конец списка. Для перекуса в полночь это верно, а для
            // перекуса в 00:05 — нет: тот же календарный день, и съеден он
            // раньше завтрака, а показывался под обедом, будто его ещё не
            // было. Время первой записи секции отвечает на это само.
            //
            // Именно первой, а не последней: минимум секции не двигается,
            // когда в неё добавляют ещё еды, — иначе секции перескакивали бы
            // местами на каждую запись, а список делает это рывком.
            let left = lhs.entries.first?.date ?? .distantFuture
            let right = rhs.entries.first?.date ?? .distantFuture
            if left != right { return left < right }
            let order = { (period: MealPeriod) in allCases.firstIndex(of: period) ?? 0 }
            return order(lhs.period) < order(rhs.period)
        }
    }

    /// Во сколько ели: час, а когда приём растянулся — промежуток.
    static func time(of entries: [FoodEntry]) -> String {
        let dates = entries.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else { return "" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        let start = first.formatted(time)
        let end = last.formatted(time)
        return start == end ? start : "\(start) – \(end)"
    }
}
