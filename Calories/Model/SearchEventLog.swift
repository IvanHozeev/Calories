import Foundation

/// Событие поиска: что показали, что выбрали.
///
/// Нужно для ранкера на признаках (пункт 2): без лога «показали → выбрали/поправили»
/// учить нечему. Храним в отдельном JSON-файле, а не в UserDefaults, чтобы не
/// раздувать настройки и чтобы легко было экспортировать/отлаживать.
struct SearchEvent: Codable, Identifiable, Equatable {
    let id: UUID
    /// Что ввели в строку поиска.
    let query: String
    /// Что показали в быстром добавлении / совпадениях.
    let shown: [ShownItem]
    /// Что выбрали пользователь (или nil, если просто смотрел и убрал клавиатуру).
    let selected: ShownItem?
    /// Вес, который в итоге поставили (если былоquickAdd с граммовкой).
    let selectedGrams: Double?
    let timestamp: Date
}

/// Показанная позиция: имя, жирность, источник, ранг совпадения.
struct ShownItem: Codable, Equatable, Hashable {
    let name: String
    let percent: Double?          // жирность, если была в запросе
    let source: String            // "catalog", "custom", "recent", "dish"
    let rank: Int?                // 0 = точное совпадение, 1 = начало, 2 = токены, 3 = одно пропущенное слово
}

/// Лог событий поиска. Singleton — пишет с любого экрана, читает для ранкера.
final class SearchEventLog {
    static let shared = SearchEventLog()

    let fileURL: URL
    /// Кэш статистики: имя продукта → (показы, выборы). Инвалидируется при каждом логе.
    private var statsCache: [String: (shown: Int, selected: Int)] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = documents.appendingPathComponent("search_events.json")
        }
    }

    /// Записать событие. Храним не более 2000 последних — файл не разрастается бесконечно.
    func log(_ event: SearchEvent) {
        var events = load()
        events.append(event)
        if events.count > 2000 {
            events = Array(events.suffix(2000))
        }
        save(events)
        statsCache = computeStats(from: events)
    }

    /// Загрузить все события.
    func load() -> [SearchEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SearchEvent].self, from: data)) ?? []
    }

    /// Статистика по имени продукта: сколько раз показывалось, сколько раз выбиралось.
    /// Для ранкера: популярность и процент — признаки для сортировки.
    func stats(for name: String) -> (shown: Int, selected: Int) {
        if let cached = statsCache[name.lowercased()] { return cached }
        let events = load()
        let result = computeStats(from: events)
        statsCache = result
        return result[name.lowercased()] ?? (0, 0)
    }

    /// Популярность продукта: доля выборов от показов (0..1).
    /// Если никогда не показывали — 0. Если показывали, но не выбирали — 0.
    /// Если выбирали каждый раз — 1.
    func popularityScore(for name: String) -> Double {
        let s = stats(for: name)
        guard s.shown > 0 else { return 0 }
        return Double(s.selected) / Double(s.shown)
    }

    private func computeStats(from events: [SearchEvent]) -> [String: (shown: Int, selected: Int)] {
        var result: [String: (shown: Int, selected: Int)] = [:]
        for event in events {
            for item in event.shown {
                let key = item.name.lowercased()
                var s = result[key] ?? (0, 0)
                s.shown += 1
                result[key] = s
            }
            if let selected = event.selected {
                let key = selected.name.lowercased()
                var s = result[key] ?? (0, 0)
                s.selected += 1
                result[key] = s
            }
        }
        return result
    }

    private func save(_ events: [SearchEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
