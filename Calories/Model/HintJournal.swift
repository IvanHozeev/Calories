import Foundation

/// Журнал подсказок «Сегодня»: что показали, на что нажали, что смахнули.
///
/// Из него приложение потом узнает, какие советы человеку помогают: какие он
/// принимает, а какие смахивает не читая. Сейчас журнал только пишется — в
/// порядок подсказок он вмешается отдельным решением (этап 4 ТЗ-1).
///
/// Живёт в настройках приложения, как история шагов, и едет в резервную копию
/// необязательным полем: это данные человека, и после переустановки они не
/// должны пропасть. Старые копии без журнала читаются как раньше.
struct HintJournal {
    /// Одно событие.
    ///
    /// Вид и источник — строками, а не перечислениями. Копию, снятую будущей
    /// версией с новым видом события, эта версия иначе не прочла бы целиком —
    /// вместе с дневником.
    struct Event: Codable, Equatable, Sendable {
        /// `shown`, `accepted`, `dismissed`.
        let kind: String
        /// Номер подсказки: `<источник>:<ключ>:<yyyy-MM-dd>`.
        let hintID: String
        /// `DayHint.Source.rawValue`.
        let source: String
        let urgency: Int
        let at: Date
    }

    enum Kind: String { case shown, accepted, dismissed }

    static let key = "hint_journal"
    /// Сколько последних событий помнить.
    static let capacity = 2000
    /// Старше года события не нужны: привычки меняются вместе с планом.
    static let maxAgeDays = 365

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var events: [Event] {
        guard let data = defaults.data(forKey: Self.key),
              let events = try? JSONDecoder().decode([Event].self, from: data) else { return [] }
        return events
    }

    /// Записать событие.
    ///
    /// Показ пишется один раз на подсказку: экран перерисовывается десятки раз
    /// за день, и без этого «показали» значило бы «перерисовали».
    func record(_ kind: Kind, _ hint: DayHint, now: Date = Date()) {
        var all = events
        if kind == .shown, all.contains(where: { $0.kind == Kind.shown.rawValue && $0.hintID == hint.id }) {
            return
        }
        all.append(Event(kind: kind.rawValue, hintID: hint.id, source: hint.source.rawValue,
                         urgency: hint.urgency, at: now))
        save(all, now: now)
    }

    /// Заменить журнал целиком — при восстановлении из копии.
    func replace(with events: [Event], now: Date = Date()) {
        save(events, now: now)
    }

    private func save(_ events: [Event], now: Date) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.maxAgeDays, to: now) ?? .distantPast
        let kept = events.filter { $0.at >= cutoff }.suffix(Self.capacity)
        guard let data = try? JSONEncoder().encode(Array(kept)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

extension CalorieStore {
    var hintJournal: HintJournal { HintJournal(defaults: defaults) }
}
