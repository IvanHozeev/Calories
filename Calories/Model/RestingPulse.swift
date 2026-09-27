import Foundation

/// Пульс в покое — по ночным замерам, своими силами.
///
/// Готовую величину «пульс в покое» пишут часы Apple; браслет отдаёт только
/// сырой пульс, а айфон не считает её вовсе. Поэтому считаем сами: ночью
/// человек лежит, и самый низкий час сна — это и есть его покой.
///
/// Зачем это в приложении про еду. Пульс в покое — самый дешёвый признак
/// того, что организм не справляется: на затяжном дефиците он ползёт вниз
/// вместе с расходом, при перегрузе и недосыпе — вверх. Он не ставит
/// диагнозов и не двигает норму; он отвечает на вопрос «почему вес встал, хотя
/// я всё делаю правильно» — иногда ответ в том, что пора отдохнуть, а не резать
/// калории ещё.
enum RestingPulse {
    /// Средний пульс за час.
    struct Hour: Equatable, Sendable {
        let start: Date
        let average: Double
    }

    /// Ночные часы, когда человек почти наверняка лежит.
    ///
    /// Берутся, когда сон неизвестен: браслет мог не записать ночь, а пульс
    /// записать. С полуночи до шести — пересечение почти любого режима сна.
    static let fallbackNight = 0..<6
    /// Меньше двух часов замеров — не ночь, а случайное касание датчика.
    static let minimumHours = 2
    /// На сколько ударов пульс должен уйти вверх, чтобы об этом стоило
    /// говорить. Один-два удара — это погрешность оптического датчика.
    static let notableRise = 3

    /// Пульс в покое по дням: минимальный час ночи.
    ///
    /// Минимум, а не среднее: среднее за ночь тянут вверх пробуждения и
    /// сновидения, а нас интересует дно — то состояние, до которого организм
    /// успевает опуститься.
    static func daily(from hours: [Hour],
                      sleep: [Date: (bed: Date, wake: Date)] = [:],
                      calendar: Calendar = .current) -> [Date: Int] {
        var byDay: [Date: [Double]] = [:]
        for hour in hours {
            // Ночь принадлежит дню пробуждения: час ночи с 23:00 26-го — это
            // ночь на 27-е.
            let day = calendar.startOfDay(for: hour.start.addingTimeInterval(6 * 3600))
            if let window = sleep[day] {
                guard hour.start >= window.bed.addingTimeInterval(-1800),
                      hour.start <= window.wake else { continue }
            } else {
                guard fallbackNight.contains(calendar.component(.hour, from: hour.start)) else { continue }
            }
            byDay[day, default: []].append(hour.average)
        }
        return byDay.compactMapValues { values in
            guard values.count >= minimumHours, let lowest = values.min() else { return nil }
            return Int(lowest.rounded())
        }
    }

    /// Насколько пульс в покое сейчас выше привычного, в ударах.
    ///
    /// Сравнивается неделя с месяцем: одна ночь ничего не значит — можно
    /// выпить вина или лечь в жару, — а неделя подряд выше обычного уже
    /// говорит о том, что человек не восстанавливается.
    static func rise(recent: [Int], usual: [Int]) -> Int? {
        guard recent.count >= 3, usual.count >= 7 else { return nil }
        let now = Double(recent.reduce(0, +)) / Double(recent.count)
        let before = Double(usual.reduce(0, +)) / Double(usual.count)
        return Int((now - before).rounded())
    }

    /// Стоит ли об этом говорить человеку.
    static func isNotable(rise: Int?) -> Bool {
        guard let rise else { return false }
        return rise >= notableRise
    }
}
