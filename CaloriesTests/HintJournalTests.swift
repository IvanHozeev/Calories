import Testing
import Foundation
import SwiftData
@testable import Calories

/// Журнал подсказок: что пишется и что переживает копию.
@MainActor
@Suite(.serialized)
struct HintJournalTests {
    private let container: ModelContainer
    private let store: CalorieStore
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private var hint: DayHint { DayHint.backup(now: now)[0] }

    /// Показ пишется один раз на подсказку, сколько бы раз её ни рисовали.
    @Test func aHintIsShownOnceNoMatterHowOftenItIsDrawn() {
        let journal = store.hintJournal
        for _ in 0..<5 { journal.record(.shown, hint, now: now) }
        journal.record(.dismissed, hint, now: now)
        #expect(journal.events.map(\.kind) == ["shown", "dismissed"])
        #expect(journal.events.first?.source == "backup")
        #expect(journal.events.first?.urgency == 100)
    }

    /// Нажатие и смахивание пишутся каждый раз — это решения человека.
    @Test func acceptedAndDismissedAreAlwaysWritten() {
        let journal = store.hintJournal
        journal.record(.accepted, hint, now: now)
        journal.record(.accepted, hint, now: now)
        #expect(journal.events.filter { $0.kind == "accepted" }.count == 2)
    }

    /// Журнал не растёт бесконечно: последние 2000 событий и не старше года.
    @Test func theJournalKeepsTheLatestYear() {
        let journal = store.hintJournal
        let old = HintJournal.Event(kind: "shown", hintID: "x", source: "backup", urgency: 1,
                                    at: now.addingTimeInterval(-400 * 86_400))
        let fresh = (0..<2100).map {
            HintJournal.Event(kind: "accepted", hintID: "y\($0)", source: "backup", urgency: 1,
                              at: now.addingTimeInterval(Double($0)))
        }
        journal.replace(with: [old] + fresh, now: now)
        #expect(journal.events.count == HintJournal.capacity)
        #expect(!journal.events.contains { $0.hintID == "x" })
        #expect(journal.events.last?.hintID == "y2099")
    }

    /// Журнал едет в копию и возвращается из неё.
    @Test func theJournalSurvivesABackup() throws {
        store.hintJournal.record(.dismissed, hint, now: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: try encoder.encode(store.makeBackup()))
        #expect(backup.hints?.count == 1)

        store.hintJournal.replace(with: [], now: now)
        store.restore(from: backup)
        #expect(store.hintJournal.events.map(\.kind) == ["dismissed"])
    }

    /// Копия без журнала читается, а журнал на телефоне не стирает.
    @Test func anOldBackupWithoutHintsLeavesTheJournalAlone() throws {
        store.hintJournal.record(.dismissed, hint, now: now)
        let json = """
        {"appVersion": "3", "dailyGoal": 2100, "exportedAt": "2026-09-01T10:00:00Z",
         "entries": [], "weights": [], "products": [], "dishes": [], "goalHistory": []}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: Data(json.utf8))
        #expect(backup.hints == nil)
        store.restore(from: backup)
        #expect(store.hintJournal.events.count == 1)
    }

    /// Копия от будущей версии с новым видом события читается целиком.
    @Test func anUnknownEventKindDoesNotBreakTheBackup() throws {
        let json = """
        {"appVersion": "9", "dailyGoal": 2100, "exportedAt": "2026-09-01T10:00:00Z",
         "entries": [], "weights": [], "products": [], "dishes": [], "goalHistory": [],
         "hints": [{"kind": "snoozed", "hintID": "backup:missing:2026-09-01", "source": "somethingNew",
                    "urgency": 50, "at": "2026-09-01T09:00:00Z"}]}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: Data(json.utf8))
        #expect(backup.hints?.first?.kind == "snoozed")
    }
}
