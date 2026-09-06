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
    /// Когда начали и закончили — для таймера. Необязательны: день можно отметить
    /// и задним числом, ничего не засекая.
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
