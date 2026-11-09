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

    private let fileURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("search_events.json")
    }

    /// Записать событие. Храним не более 2000 последних — файл не разрастается бесконечно.
    func log(_ event: SearchEvent) {
        var events = load()
        events.append(event)
        if events.count > 2000 {
            events = Array(events.suffix(2000))
        }
        save(events)
    }

    /// Загрузить все события.
    func load() -> [SearchEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SearchEvent].self, from: data)) ?? []
    }

    /// Статистика по имени продукта: сколько раз показывалось, сколько раз выбиралось.
    /// Для ранкера: популярность и процент — признаки для сортировки.
    func stats(for name: String) -> (shown: Int, selected: Int) {
        let events = load()
        let shown = events.reduce(0) { $0 + ($1.shown.contains { $0.name.lowercased() == name.lowercased() } ? 1 : 0) }
        let selected = events.reduce(0) { $0 + ($1.selected.map { $0.name.lowercased() == name.lowercased() } == true ? 1 : 0) }
        return (shown, selected)
    }

    private func save(_ events: [SearchEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
