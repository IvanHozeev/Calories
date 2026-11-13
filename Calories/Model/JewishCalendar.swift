import Foundation

/// Посты и праздники еврейского календаря — поверх системного, без сети.
///
/// В приложении уже были три части одной темы: кашрут, дни поста (с Йом
/// Кипуром в комментариях) и перенос рефида. Не хватало самого календаря:
/// даты приходилось помнить и отмечать руками. Системный еврейский календарь
/// встроен в iOS, и сеть для него не нужна.
///
/// Решения владельца от 13.11: все шесть постов; малые — отдельным видом «от
/// рассвета до темноты»; израильский обычай (у праздников первый день), но Рош
/// ха-Шана — оба дня, как и в Израиле.
nonisolated enum JewishCalendar {
    enum Kind: Equatable, Sendable { case majorFast, minorFast, feast }

    struct Event: Equatable, Sendable {
        /// "yomKippur", "tishaBeAv", "gedaliah", "tevet10", "esther", "tammuz17",
        /// "roshHashana", "roshHashana2", "sukkot", "purim", "pesach", "shavuot"
        var key: String
        var kind: Kind
        /// Гражданские сутки дневной части — начало дня в поясе пользователя.
        var day: Date
        /// Начинается вечером накануне: большие посты и праздники.
        var startsEveningBefore: Bool

        /// Название для подсказки.
        var title: String {
            switch key {
            case "yomKippur": return String(localized: "Йом Кипур")
            case "tishaBeAv": return String(localized: "9 ава")
            case "gedaliah": return String(localized: "Пост Гедальи")
            case "tevet10": return String(localized: "10 тевета")
            case "esther": return String(localized: "Пост Эстер")
            case "tammuz17": return String(localized: "17 таммуза")
            case "roshHashana", "roshHashana2": return String(localized: "Рош ха-Шана")
            case "sukkot": return String(localized: "Суккот")
            case "purim": return String(localized: "Пурим")
            case "pesach": return String(localized: "Песах")
            case "shavuot": return String(localized: "Шавуот")
            default: return key
            }
        }

        var isFast: Bool { kind != .feast }
    }

    /// Номера месяцев системного календаря: 1 — тишрей, 4 — тевет, 7 — адар
    /// (в високосный год адар II), 8 — нисан, 10 — сиван, 11 — таммуз, 12 — ав.
    private enum Month {
        static let tishrei = 1, tevet = 4, adar = 7, nisan = 8, sivan = 10, tammuz = 11, av = 12
    }

    /// Что переносится с субботы и куда.
    private enum Shift { case none, toSunday, toThursdayBefore }

    private struct Rule {
        let key: String
        let kind: Kind
        let month: Int
        let day: Int
        let shift: Shift
    }

    private static let rules: [Rule] = [
        Rule(key: "roshHashana", kind: .feast, month: Month.tishrei, day: 1, shift: .none),
        Rule(key: "roshHashana2", kind: .feast, month: Month.tishrei, day: 2, shift: .none),
        // Пост Гедальи с субботы — на воскресенье.
        Rule(key: "gedaliah", kind: .minorFast, month: Month.tishrei, day: 3, shift: .toSunday),
        // Йом Кипур не переносится никогда, даже с субботы.
        Rule(key: "yomKippur", kind: .majorFast, month: Month.tishrei, day: 10, shift: .none),
        Rule(key: "sukkot", kind: .feast, month: Month.tishrei, day: 15, shift: .none),
        Rule(key: "tevet10", kind: .minorFast, month: Month.tevet, day: 10, shift: .none),
        // Пост Эстер с субботы — на четверг перед ней: пятница занята
        // подготовкой к шаббату.
        Rule(key: "esther", kind: .minorFast, month: Month.adar, day: 13, shift: .toThursdayBefore),
        Rule(key: "purim", kind: .feast, month: Month.adar, day: 14, shift: .none),
        Rule(key: "pesach", kind: .feast, month: Month.nisan, day: 15, shift: .none),
        Rule(key: "shavuot", kind: .feast, month: Month.sivan, day: 6, shift: .none),
        Rule(key: "tammuz17", kind: .minorFast, month: Month.tammuz, day: 17, shift: .toSunday),
        Rule(key: "tishaBeAv", kind: .majorFast, month: Month.av, day: 9, shift: .toSunday),
    ]

    /// События с `from` по `to` включительно, по дням в поясе `timeZone`.
    static func events(from: Date, to: Date, timeZone: TimeZone) -> [Event] {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = timeZone
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let start = gregorian.startOfDay(for: from)
        let end = gregorian.startOfDay(for: to)
        guard start <= end,
              let firstYear = hebrew.dateComponents([.year], from: start).year,
              let lastYear = hebrew.dateComponents([.year], from: end).year else { return [] }

        var events: [Event] = []
        for year in (firstYear - 1)...(lastYear + 1) {
            for rule in rules {
                guard let raw = hebrew.date(from: DateComponents(year: year, month: rule.month, day: rule.day))
                else { continue }
                var day = gregorian.startOfDay(for: raw)
                if gregorian.component(.weekday, from: day) == 7 {     // суббота
                    switch rule.shift {
                    case .none: break
                    case .toSunday: day = gregorian.date(byAdding: .day, value: 1, to: day) ?? day
                    case .toThursdayBefore: day = gregorian.date(byAdding: .day, value: -2, to: day) ?? day
                    }
                }
                guard day >= start, day <= end else { continue }
                events.append(Event(key: rule.key, kind: rule.kind, day: day,
                                    startsEveningBefore: rule.kind != .minorFast))
            }
        }
        return events.sorted { $0.day < $1.day }
    }
}
