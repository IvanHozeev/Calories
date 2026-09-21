import Foundation
import SwiftData

/// Полное голодание, отмеченное заранее или постфактум.
///
/// Нужно потому, что день без единой записи приложение до сих пор читало как
/// «забил на дневник»: рвалась серия, а банк калорий такой день просто пропускал.
/// Но человек сделал ровно то, что собирался, и отличить это от забытого дня
/// можно только по явной отметке.
@Model
final class FastDay: Identifiable {
    var id: UUID
    /// Начало суток — голодание привязано ко дню, а не к минуте.
    var date: Date
    var kindRaw: String
    /// Начало и конец поста. Необязательны: день можно отметить и задним
    /// числом, ничего не засекая, — тогда постом считаются целые сутки.
    ///
    /// Нужны, потому что настоящий пост редко совпадает с календарным днём:
    /// Йом Кипур начинается вечером и кончается вечером следующего дня, и без
    /// границ приложение либо считало бы голодными не те сутки, либо теряло
    /// половину поста.
    var startedAt: Date?
    var endedAt: Date?

    init(id: UUID = UUID(), date: Date, kind: FastKind, startedAt: Date? = nil, endedAt: Date? = nil) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var kind: FastKind {
        get { FastKind(rawValue: kindRaw) ?? .dry }
        set { kindRaw = newValue.rawValue }
    }

    /// Заданы ли границы явно. У старых отметок, сделанных «днём», их нет,
    /// и показывать по ним обратный отсчёт нельзя: он считал бы до полуночи.
    var hasExplicitInterval: Bool { startedAt != nil && endedAt != nil }

    /// Промежуток поста. Без явных границ — целые сутки отмеченного дня.
    var interval: DateInterval {
        let calendar = Calendar.current
        let start = startedAt ?? calendar.startOfDay(for: date)
        let end = endedAt ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? start
        return DateInterval(start: start, end: max(end, start))
    }

    /// Сутки, которых пост касается: он может идти через полночь.
    var coveredDays: [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        let last = calendar.startOfDay(for: interval.end)
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // Конец ровно в полночь принадлежит предыдущим суткам.
        if days.count > 1, interval.end == last { days.removeLast() }
        return days
    }

    /// Идёт ли пост прямо сейчас.
    func isRunning(at moment: Date = Date()) -> Bool {
        interval.contains(moment)
    }
}

/// Сухое голодание и голодание на воде — разные вещи, и советы к ним разные.
/// В Йом Кипур не пьют вовсе, и «пей больше воды» там вредный совет.
enum FastKind: String, Codable, CaseIterable, Identifiable {
    case dry, water

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dry:   return String(localized: "Сухое")
        case .water: return String(localized: "На воде")
        }
    }
}

/// Подсказка на «Сегодня» перед голоданием и в его день.
struct FastingHint: Equatable {
    let date: Date
    let kind: FastKind
    /// 0 — голодание сегодня.
    let daysUntil: Int
    let items: [FastingAdvice.Item]
    /// Промежуток поста: с него берутся часы начала и конца.
    var interval: DateInterval? = nil

    /// Идёт ли пост прямо сейчас.
    func isRunning(at moment: Date = Date()) -> Bool {
        interval?.contains(moment) ?? false
    }

    /// Сколько осталось до конца поста, если он идёт.
    func remaining(at moment: Date = Date()) -> TimeInterval? {
        guard let interval, interval.contains(moment) else { return nil }
        return interval.end.timeIntervalSince(moment)
    }

    static func == (lhs: FastingHint, rhs: FastingHint) -> Bool {
        lhs.date == rhs.date && lhs.kind == rhs.kind && lhs.daysUntil == rhs.daysUntil
            && lhs.items.map(\.text) == rhs.items.map(\.text)
    }
}
