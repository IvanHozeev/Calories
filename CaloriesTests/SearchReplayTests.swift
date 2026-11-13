import Testing
import Foundation
@testable import Calories

/// Приёмка ТЗ-5: прогон журнала поиска через сортировку.
///
/// Числа — из таблицы ТЗ, а не подогнаны под реализацию. Журнал только
/// синтетический: настоящий — личные данные и в репозиторий не попадает.
@MainActor
struct SearchReplayTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, percent: Double? = nil) -> ShownItem {
        ShownItem(name: name, percent: percent, source: "catalog", rank: nil)
    }

    private func show(_ query: String, _ names: [String], at seconds: TimeInterval) -> SearchEvent {
        SearchEvent(id: UUID(), query: query, shown: names.map { item($0) },
                    selected: nil, selectedGrams: nil, timestamp: start.addingTimeInterval(seconds))
    }

    private func pick(_ query: String, _ name: String, at seconds: TimeInterval) -> SearchEvent {
        SearchEvent(id: UUID(), query: query, shown: [], selected: item(name),
                    selectedGrams: 100, timestamp: start.addingTimeInterval(seconds))
    }

    private let identity: (String, [ShownItem]) -> [ShownItem] = { _, shown in shown }

    // 1
    @Test func fourPairsScoreByPosition() {
        let events = [
            show("а", ["x", "b", "c", "d"], at: 0), pick("а", "x", at: 10),
            show("б", ["b", "x", "c", "d"], at: 100), pick("б", "x", at: 110),
            show("в", ["b", "c", "d", "x"], at: 200), pick("в", "x", at: 210),
            show("г", ["b", "c", "d"], at: 300), pick("г", "x", at: 310),
        ]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.evaluated == 3)
        #expect(score.skipped == 1)
        #expect(abs(score.meanReciprocalRank - 0.5833) < 0.0001)
        #expect(abs(score.top1Share - 0.3333) < 0.0001)
    }

    // 2
    @Test func aReversingRankerMovesTheChoiceToThird() {
        let events = [show("q", ["x", "b", "c"], at: 0), pick("q", "x", at: 5)]
        let score = SearchReplay.score(events) { _, shown in shown.reversed() }
        #expect(abs(score.meanReciprocalRank - 0.3333) < 0.0001)
        #expect(score.top1Share == 0)
    }

    // 3
    @Test func showsWithoutChoicesScoreNothing() {
        let events = [show("q", ["x"], at: 0), show("w", ["y"], at: 5)]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.evaluated == 0)
        #expect(score.skipped == 0)
        #expect(score.meanReciprocalRank == 0)
        #expect(score.top1Share == 0)
    }

    // 4
    @Test func anEmptyLogScoresNothing() {
        let score = SearchReplay.score([], ranker: identity)
        #expect(score == SearchReplay.Score(meanReciprocalRank: 0, top1Share: 0, evaluated: 0, skipped: 0))
    }

    // 5
    @Test func aRankerThatDropsTheChoiceScoresZero() {
        let events = [show("q", ["x", "b"], at: 0), pick("q", "x", at: 5)]
        let score = SearchReplay.score(events) { _, shown in shown.filter { $0.name != "x" } }
        #expect(score.evaluated == 1)
        #expect(score.meanReciprocalRank == 0)
    }

    // 6
    @Test func aChoiceWithoutAShowIsSkipped() {
        let score = SearchReplay.score([pick("q", "x", at: 5)], ranker: identity)
        #expect(score.evaluated == 0)
        #expect(score.skipped == 1)
    }

    // 7
    @Test func aShowOlderThanTheWindowIsNotPaired() {
        let events = [show("q", ["x"], at: 0), pick("q", "x", at: 121)]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.skipped == 1)
        #expect(score.evaluated == 0)
    }

    // 8
    @Test func theLatestShowWins() {
        let events = [
            show("q", ["b", "c", "x"], at: 0),
            show("q", ["x", "b", "c"], at: 25),
            pick("q", "x", at: 30),
        ]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.evaluated == 1)
        #expect(score.meanReciprocalRank == 1)
    }

    // 9
    @Test func differentQueriesDoNotPair() {
        let events = [show("творог", ["x"], at: 0), pick("творог 5", "x", at: 5)]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.skipped == 1)
    }

    private var emptyResults: [SearchEvent] {
        [show("Кефир  2%", [], at: 0), show("Кефир  2%", [], at: 10),
         show("кефир 2%", [], at: 20), show("манго", [], at: 30)]
    }

    // 10
    @Test func emptyQueriesAreGluedByNormalization() {
        let queries = SearchReplay.emptyQueries(emptyResults, minCount: 2)
        #expect(queries.count == 1)
        #expect(queries.first?.count == 3)
    }

    // 11
    @Test func emptyQueriesBelowTheMinimumAreListedToo() {
        let queries = SearchReplay.emptyQueries(emptyResults, minCount: 1)
        #expect(queries.count == 2)
        #expect(queries.first?.count == 3)
    }

    // 12
    @Test func aChoiceIsNotAnEmptyResult() {
        let queries = SearchReplay.emptyQueries([pick("манго", "Манго", at: 0)], minCount: 1)
        #expect(queries.isEmpty)
    }

    // MARK: Записи с номером захода

    private func show(_ query: String, _ names: [String], at seconds: TimeInterval, session: UUID) -> SearchEvent {
        SearchEvent(id: UUID(), query: query, shown: names.map { item($0) },
                    selected: nil, selectedGrams: nil, timestamp: start.addingTimeInterval(seconds), session: session)
    }

    private func pick(_ query: String, _ name: String, at seconds: TimeInterval, session: UUID) -> SearchEvent {
        SearchEvent(id: UUID(), query: query, shown: [], selected: item(name),
                    selectedGrams: 100, timestamp: start.addingTimeInterval(seconds), session: session)
    }

    /// Быстрое добавление и «Совпадения» пишутся двумя показами одного
    /// захода; выбор из первого не должен пропадать из-за того, что вторым
    /// записался другой список.
    @Test func aChoiceFindsTheShowItCameFromWithinTheSession() {
        let id = UUID()
        let events = [
            show("тво", ["x", "b"], at: 0, session: id),
            show("тво", ["c", "d"], at: 1, session: id),
            pick("тво", "x", at: 5, session: id),
        ]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.evaluated == 1)
        #expect(score.meanReciprocalRank == 1)
    }

    /// Номер захода связывает выбор с показом и тогда, когда запрос успел
    /// измениться и прошло больше двух минут.
    @Test func theSessionPairsAcrossQueryChangesAndTime() {
        let id = UUID()
        let events = [show("тв", ["b", "x"], at: 0, session: id), pick("творог", "x", at: 300, session: id)]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.evaluated == 1)
        #expect(score.meanReciprocalRank == 0.5)
    }

    /// Выбор продукта, которого не было ни в одном показе захода (из базы
    /// ниже), в оценку не идёт, но и не теряется: он в `skipped`.
    @Test func aChoiceOutsideEveryShowIsSkipped() {
        let id = UUID()
        let events = [show("q", ["b"], at: 0, session: id), pick("q", "x", at: 5, session: id)]
        let score = SearchReplay.score(events, ranker: identity)
        #expect(score.evaluated == 0)
        #expect(score.skipped == 1)
    }

    /// Чужой заход не подходит, даже с тем же запросом.
    @Test func anotherSessionDoesNotPair() {
        let events = [show("q", ["x"], at: 0, session: UUID()), pick("q", "x", at: 5, session: UUID())]
        #expect(SearchReplay.score(events, ranker: identity).skipped == 1)
    }

    /// Старый журнал без номера читается, как раньше.
    @Test func anOldLogLineWithoutASessionStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","query":"q","shown":[],"selected":null,"selectedGrams":null,"timestamp":0}"#
        let event = try JSONDecoder().decode(SearchEvent.self, from: Data(json.utf8))
        #expect(event.session == nil)
        #expect(event.query == "q")
    }
}
