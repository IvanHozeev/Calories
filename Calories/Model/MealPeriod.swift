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

    /// Время сегодняшнего дня, попадающее в этот приём пищи. Нужно при ручном выборе
    /// приёма: запись группируется по часу, поэтому дата должна лежать внутри диапазона.
    /// Если выбранный приём уже идёт прямо сейчас, оставляем текущее время —
    /// так запись не «уезжает» относительно соседних.
    func dateForToday(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        if Self.period(for: now) == self { return now }
        return calendar.date(bySettingHour: representativeHour, minute: 0, second: 0, of: now) ?? now
    }
}
