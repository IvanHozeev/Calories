import ActivityKit
import Foundation

/// Идущий пост — на экране блокировки и в островке.
///
/// Так же, как ожидание кашрута: запись делается один раз, с временем конца, а
/// отсчёт и полоску рисует система по своим часам — приложение закрыто, а число
/// остаётся верным. Лежит в `Shared`, потому что нужна обоим таргетам, и потому
/// здесь нет ничего из модели: вид поста — строкой.
struct FastingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Когда пост кончится.
        var until: Date
    }

    /// С какого момента идёт: от него считается полоска.
    var startedAt: Date
    /// Вид поста: `dry`, `water` или `daytime`. Строкой — своей модели у виджета
    /// нет, а менять формат ради слова значит ломать идущие записи.
    var kind: String

    static let dry = "dry"
    static let water = "water"
    static let daytime = "daytime"

    /// Диапазон для системного отсчёта: конец не раньше начала. Причина та же,
    /// что у ожидания кашрута: после срока диапазон обязан остаться допустимым.
    static func countdownRange(now: Date, until: Date) -> ClosedRange<Date> {
        now...max(until, now)
    }
}
