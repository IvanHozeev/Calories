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
    /// Вес, который в итоге поставили (если было быстрое добавление с граммовкой).
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
///
/// Всё происходит на главном потоке: так и есть сегодня (оба места записи и
/// сортировка по популярности стоят внутри `MainActor.run`), и модуль по умолчанию
/// изолирован главным актором, так что компилятор это держит. Поэтому здесь нет
/// ни очередей, ни блокировок — их пришлось бы проверять, а они не нужны.
///
/// **Журнал живёт в памяти, на диск дописывается строка.** Прежний вариант на
/// каждое событие читал файл целиком, дописывал массив и записывал его обратно:
/// на полном журнале (2000 событий, 850 КБ) это 68 мс на главном потоке при каждой
/// паузе в наборе. А `stats(for:)` для названия, которого в журнале не было,
/// перечитывал файл заново, потому что «нет в кэше» не отличалось от «нет в
/// журнале»: сортировка тридцати незнакомых продуктов занимала 2,3 секунды.
///
/// Формат файла — по событию на строку (JSON Lines), чтобы дозапись не требовала
/// чтения. Старый файл — один JSON-массив — читается и при первом чтении
/// переписывается в новый формат. Оборванная последняя строка (приложение убили
/// посреди записи) пропускается и не съедает следующее событие.
final class SearchEventLog {
    static let shared = SearchEventLog()

    /// Сколько последних событий помнит журнал.
    static let capacity = 2000
    /// Сколько лишних строк копится в файле, прежде чем он перезапишется целиком.
    /// Раз в пятьсот событий одна полная перезапись вместо перезаписи на каждое.
    static let slack = 500

    let fileURL: URL

    /// `nil` — файл ещё не читали. Читается один раз за запуск.
    private var events: [SearchEvent]?
    /// Имя продукта (строчными) → (показы, выборы). Отсутствие имени здесь — это
    /// «в журнале нет», и файл ради этого больше не читается.
    private var stats: [String: (shown: Int, selected: Int)] = [:]
    private var linesOnDisk = 0
    private var needsLeadingNewline = false

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = documents.appendingPathComponent("search_events.json")
        }
    }

    /// Записать событие. Помним не более `capacity` последних.
    func log(_ event: SearchEvent) {
        loadIfNeeded()
        events?.append(event)
        apply(event, sign: 1)
        if (events?.count ?? 0) > Self.capacity, let dropped = events?.removeFirst() {
            // Вместе с событием уходит и его вклад в статистику: иначе показы
            // давно забытых запросов оставались бы в доле выбора навсегда.
            apply(dropped, sign: -1)
        }
        append(event)
        if linesOnDisk > Self.capacity + Self.slack { rewrite() }
    }

    /// Все помнимые события, от старых к новым.
    func load() -> [SearchEvent] {
        loadIfNeeded()
        return events ?? []
    }

    /// Статистика по имени продукта: сколько раз показывалось, сколько раз выбиралось.
    /// Для ранкера: популярность и процент — признаки для сортировки.
    func stats(for name: String) -> (shown: Int, selected: Int) {
        loadIfNeeded()
        return stats[name.lowercased()] ?? (0, 0)
    }

    /// Популярность продукта: доля выборов от показов (0..1).
    /// Если никогда не показывали — 0. Если показывали, но не выбирали — 0.
    /// Если выбирали каждый раз — 1.
    func popularityScore(for name: String) -> Double {
        let s = stats(for: name)
        guard s.shown > 0 else { return 0 }
        return Double(s.selected) / Double(s.shown)
    }

    // MARK: - Статистика

    private func apply(_ event: SearchEvent, sign: Int) {
        for item in event.shown {
            let key = item.name.lowercased()
            var s = stats[key] ?? (0, 0)
            s.shown += sign
            stats[key] = s.shown == 0 && s.selected == 0 ? nil : s
        }
        if let selected = event.selected {
            let key = selected.name.lowercased()
            var s = stats[key] ?? (0, 0)
            s.selected += sign
            stats[key] = s.shown == 0 && s.selected == 0 ? nil : s
        }
    }

    // MARK: - Диск

    private func loadIfNeeded() {
        guard events == nil else { return }
        var loaded: [SearchEvent] = []
        var legacy = false
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            if data.first == UInt8(ascii: "[") {
                // Прежний формат — один массив.
                loaded = (try? JSONDecoder().decode([SearchEvent].self, from: data)) ?? []
                legacy = true
            } else {
                let decoder = JSONDecoder()
                for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                    if let event = try? decoder.decode(SearchEvent.self, from: Data(line)) {
                        loaded.append(event)
                    }
                }
                needsLeadingNewline = data.last != UInt8(ascii: "\n")
            }
        }
        linesOnDisk = loaded.count
        if loaded.count > Self.capacity { loaded = Array(loaded.suffix(Self.capacity)) }
        events = loaded
        stats = [:]
        for event in loaded { apply(event, sign: 1) }
        if legacy { rewrite() }
    }

    /// Дописать одну строку. Файл не читается и не переписывается.
    private func append(_ event: SearchEvent) {
        guard var data = try? JSONEncoder().encode(event) else { return }
        data.append(UInt8(ascii: "\n"))
        if needsLeadingNewline {
            data.insert(UInt8(ascii: "\n"), at: 0)
            needsLeadingNewline = false
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
        linesOnDisk += 1
    }

    /// Переписать файл целиком из памяти: сжимает накопившиеся лишние строки и
    /// переводит старый формат в новый.
    private func rewrite() {
        let encoder = JSONEncoder()
        var data = Data()
        for event in events ?? [] {
            guard let line = try? encoder.encode(event) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        try? data.write(to: fileURL, options: .atomic)
        linesOnDisk = events?.count ?? 0
        needsLeadingNewline = false
    }
}
