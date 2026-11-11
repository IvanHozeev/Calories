import Testing
import Foundation
@testable import Calories

/// Журнал выборов поиска: что показали, что выбрали.
///
/// Прежний журнал читал файл целиком на каждую запись и на каждый вопрос про
/// название, которого в нём не было, — на полном журнале это 68 мс и 40 мс на
/// главном потоке. Тесты фиксируют то, что от этого осталось: журнал переживает
/// перезапуск, помнит не больше положенного, и вопрос про незнакомое название не
/// ходит на диск.
@MainActor
@Suite struct SearchEventLogTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("search-events-\(UUID().uuidString).json")
    }

    private func event(shown: [String], selected: String? = nil) -> SearchEvent {
        func item(_ name: String) -> ShownItem {
            ShownItem(name: name, percent: nil, source: "catalog", rank: nil)
        }
        return SearchEvent(id: UUID(), query: shown.first ?? "", shown: shown.map(item),
                           selected: selected.map(item), selectedGrams: nil, timestamp: Date())
    }

    private func lines(in url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        return data.filter { $0 == UInt8(ascii: "\n") }.count
    }

    /// Вопрос про название, которого нет в журнале, не трогает диск.
    ///
    /// Прежний код отличал «нет в кэше» от «нет в журнале» только перечитыванием
    /// файла — и если файла к этому моменту уже не было, перечитанное пустое
    /// стирало кэш вместе со всем, что в нём лежало.
    @Test func aQuestionAboutAnUnknownNameDoesNotTouchTheDisk() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = SearchEventLog(fileURL: url)
        writer.log(event(shown: ["Молоко"], selected: "Молоко"))
        writer.log(event(shown: ["Молоко"]))

        let reader = SearchEventLog(fileURL: url)
        #expect(reader.stats(for: "молоко") == (2, 1))
        try? FileManager.default.removeItem(at: url)

        #expect(reader.stats(for: "никогда не показывали") == (0, 0))
        #expect(reader.stats(for: "Молоко") == (2, 1),
                "промах не должен был перечитать файл и стереть то, что уже знали")
    }

    @Test func theJournalSurvivesARestart() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = SearchEventLog(fileURL: url)
        for name in ["А", "Б", "В"] { first.log(event(shown: [name])) }

        let second = SearchEventLog(fileURL: url)
        #expect(second.load().map(\.query) == ["А", "Б", "В"])
    }

    /// Забытое событие уносит и свой вклад в статистику.
    @Test func theCapDropsTheOldestEventAndItsStatistics() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = SearchEventLog(fileURL: url)
        log.log(event(shown: ["Старый"], selected: "Старый"))
        for _ in 0..<SearchEventLog.capacity { log.log(event(shown: ["Новый"])) }

        #expect(log.load().count == SearchEventLog.capacity)
        #expect(log.stats(for: "Старый") == (0, 0), "показы забытого события остались в статистике")
        #expect(log.stats(for: "Новый").shown == SearchEventLog.capacity)
    }

    /// Файл не растёт бесконечно: раз в `slack` событий он сжимается до помнимых.
    @Test func theFileIsCompactedOnceItOutgrowsTheSlack() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = SearchEventLog(fileURL: url)
        for i in 0..<(SearchEventLog.capacity + SearchEventLog.slack + 5) {
            log.log(event(shown: ["п\(i)"]))
        }
        #expect(lines(in: url) <= SearchEventLog.capacity + SearchEventLog.slack)
        #expect(SearchEventLog(fileURL: url).load().count == SearchEventLog.capacity)
    }

    /// Файл прежнего формата — один массив — читается и переводится в новый.
    @Test func anOldArrayFileIsStillReadAndConverted() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let old = [event(shown: ["Старое-1"]), event(shown: ["Старое-2"])]
        try JSONEncoder().encode(old).write(to: url)

        let log = SearchEventLog(fileURL: url)
        #expect(log.load().count == 2)
        log.log(event(shown: ["Новое"]))

        let again = SearchEventLog(fileURL: url)
        #expect(again.load().map(\.query) == ["Старое-1", "Старое-2", "Новое"])
        #expect(lines(in: url) == 3, "после перехода файл должен лежать по событию на строку")
    }

    /// Оборванная посреди записи строка пропускается и не съедает следующее событие.
    @Test func aTornLastLineDoesNotLoseTheNextEvent() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var data = try JSONEncoder().encode(event(shown: ["Целое"]))
        data.append(UInt8(ascii: "\n"))
        data.append(Data(#"{"id":"обор"#.utf8))
        try data.write(to: url)

        let log = SearchEventLog(fileURL: url)
        #expect(log.load().map(\.query) == ["Целое"])
        log.log(event(shown: ["Следующее"]))

        #expect(SearchEventLog(fileURL: url).load().map(\.query) == ["Целое", "Следующее"])
    }
}
