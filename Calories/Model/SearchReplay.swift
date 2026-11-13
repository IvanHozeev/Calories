import Foundation

/// Прогон журнала поиска через сортировку: на каком месте оказался бы
/// продукт, который человек тогда выбрал.
///
/// Про любую правку поиска иначе можно только спорить, стало лучше или хуже.
/// С этим расчётом это число до и после на тех же записанных запросах, без
/// запуска приложения.
///
/// **Ограничение, которое нельзя замалчивать:** расчёт переупорядочивает
/// только то, что было показано. Продуктов, которые новый поиск нашёл бы, а
/// старый нет, он не видит.
///
/// Показ и выбор журнал пишет двумя записями: в записи показа выбора нет, в
/// записи выбора нет показанного. Поэтому сначала записи сводятся в пары.
enum SearchReplay {
    /// Пара «что показали → что выбрали», собранная из двух записей журнала.
    struct Session: Equatable {
        var query: String
        var shown: [ShownItem]
        var selected: ShownItem
    }

    struct Score: Equatable {
        /// Среднее 1/позиция по оценённым парам; 1 — выбранное всегда первым.
        var meanReciprocalRank: Double
        /// Доля пар, где выбранное стоит первым.
        var top1Share: Double
        /// Пар в оценке.
        var evaluated: Int
        /// Записей выбора, не попавших в оценку: без пары или без выбранного
        /// среди показанных.
        var skipped: Int
    }

    /// Сводит записи в пары.
    ///
    /// **Записи с номером захода** (`session`) сводятся внутри своего захода:
    /// берётся последний показ этого захода, где выбранное есть среди
    /// показанных, а если такого нет — просто последний. На одну паузу набора
    /// лист пишет два показа (быстрое добавление и «Совпадения»), и «просто
    /// последний» мог оказаться не тем списком, из которого выбирали.
    ///
    /// **Старые записи без номера** — как в ТЗ: последний предшествующий показ
    /// с тем же запросом, не старше `window` секунд.
    static func sessions(_ events: [SearchEvent], window: TimeInterval = 120)
        -> (paired: [Session], unpaired: Int) {
        let ordered = events.sorted { $0.timestamp < $1.timestamp }
        var lastShow: [String: SearchEvent] = [:]
        var showsInSession: [UUID: [SearchEvent]] = [:]
        var paired: [Session] = []
        var unpaired = 0
        for event in ordered {
            if let selected = event.selected {
                if let id = event.session {
                    let shows = showsInSession[id] ?? []
                    guard let show = shows.last(where: { $0.shown.contains { matches($0, selected) } })
                            ?? shows.last else {
                        unpaired += 1
                        continue
                    }
                    paired.append(Session(query: show.query, shown: show.shown, selected: selected))
                    continue
                }
                guard let show = lastShow[event.query],
                      event.timestamp.timeIntervalSince(show.timestamp) <= window else {
                    unpaired += 1
                    continue
                }
                paired.append(Session(query: event.query, shown: show.shown, selected: selected))
            } else if !event.shown.isEmpty {
                if let id = event.session {
                    showsInSession[id, default: []].append(event)
                } else {
                    lastShow[event.query] = event
                }
            }
        }
        return (paired, unpaired)
    }

    /// Оценка сортировки `ranker` на журнале.
    ///
    /// Выбранное ищется по имени и жирности. Если сортировка выбросила его
    /// из списка — пара оценивается нулём, а не пропускается: потерять
    /// выбранный продукт хуже, чем поставить его последним.
    static func score(_ events: [SearchEvent], window: TimeInterval = 120,
                      ranker: (_ query: String, _ shown: [ShownItem]) -> [ShownItem]) -> Score {
        let (sessions, unpaired) = sessions(events, window: window)
        var skipped = unpaired
        var reciprocalSum = 0.0
        var top1 = 0
        var evaluated = 0
        for session in sessions {
            guard session.shown.contains(where: { matches($0, session.selected) }) else {
                skipped += 1
                continue
            }
            evaluated += 1
            let ranked = ranker(session.query, session.shown)
            guard let index = ranked.firstIndex(where: { matches($0, session.selected) }) else { continue }
            reciprocalSum += 1.0 / Double(index + 1)
            if index == 0 { top1 += 1 }
        }
        guard evaluated > 0 else {
            return Score(meanReciprocalRank: 0, top1Share: 0, evaluated: 0, skipped: skipped)
        }
        return Score(meanReciprocalRank: reciprocalSum / Double(evaluated),
                     top1Share: Double(top1) / Double(evaluated),
                     evaluated: evaluated, skipped: skipped)
    }

    /// Запросы с пустой выдачей: нормализованный текст и сколько раз он
    /// встретился — готовый перечень пробелов в базе.
    ///
    /// Пустая выдача — запись показа, где показывать было нечего. Запись
    /// выбора тоже идёт с пустым `shown`, но это не пустая выдача.
    static func emptyQueries(_ events: [SearchEvent], minCount: Int) -> [(query: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events where event.shown.isEmpty && event.selected == nil {
            let query = FoodCatalog.normalize(event.query)
            guard !query.isEmpty else { continue }
            counts[query, default: 0] += 1
        }
        return counts
            .filter { $0.value >= minCount }
            .map { (query: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.query < $1.query }
    }

    private static func matches(_ a: ShownItem, _ b: ShownItem) -> Bool {
        a.name == b.name && a.percent == b.percent
    }
}
