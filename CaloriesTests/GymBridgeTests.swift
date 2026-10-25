import Testing
import Foundation
@testable import Calories

/// Чужой снимок — источник, которым мы не управляем: он может быть вчерашним,
/// неполным или новее нашего понимания формата. Проверяем не то, что разбор
/// работает, а то, что он молчит, когда знать неоткуда.
@Suite struct GymBridgeTests {

    private let calendar = Calendar.current

    /// Снимок соседа, как он приходит по проводу: JSON с датами ISO.
    private func snapshot(_ json: String) -> GymBridge.State? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GymBridge.State.self, from: Data(json.utf8))
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    // MARK: - Формат

    @Test func itReadsTheSnapshotTheNeighbourSends() throws {
        let state = try #require(snapshot("""
        {
          "date": "\(iso(Date()))",
          "deload": { "isActive": true, "volumeFraction": 0.5, "intensityFraction": 0.9 },
          "block": { "name": "Набор", "week": 6, "totalWeeks": 12, "daysPerWeek": 4,
                     "isComplete": false, "trainsToFailure": true },
          "today": { "name": "Ноги", "type": "Legs", "isRest": false,
                     "plannedSets": 16, "plannedExercises": 5, "isDone": false },
          "week": { "startsOn": "\(iso(daysAgo(2)))", "totalSets": 62.5,
                    "setsByMuscle": { "Quads": 12.5, "Chest": 9, "Biceps": 4.5 } },
          "lastWorkout": { "at": "\(iso(daysAgo(1)))", "minutes": 72, "name": "Пуш", "sets": 18 },
          "daysSinceLastWorkout": 1
        }
        """))

        #expect(state.deload?.isActive == true)
        #expect(state.block?.week == 6)
        #expect(GymBridge.todayType(state) == "Legs")
        #expect(GymBridge.weeklySets(state) == 62.5)
        #expect(state.lastWorkout?.sets == 18)
    }

    /// Сосед обещал добавлять поля, не трогая старые. Неизвестное поле не
    /// должно ронять разбор целиком — иначе их следующий релиз выключит нам
    /// половину экрана.
    @Test func anUnknownFieldDoesNotBreakTheRest() throws {
        let state = try #require(snapshot("""
        {
          "date": "\(iso(Date()))",
          "week": { "totalSets": 40, "tonnageKg": 12500 },
          "readinessScore": 0.82
        }
        """))
        #expect(GymBridge.weeklySets(state) == 40)
    }

    /// Пустая неделя — это ноль, а не отсутствие данных.
    @Test func anEmptyWeekIsZeroNotSilence() throws {
        let state = try #require(snapshot("""
        { "date": "\(iso(Date()))", "week": { "totalSets": 0, "setsByMuscle": {} } }
        """))
        #expect(GymBridge.weeklySets(state) == 0)
        #expect(GymBridge.topMuscles(state).isEmpty)
    }

    // MARK: - Свежесть

    /// Вчерашний снимок про сегодняшний день не знает ничего. Молчим, а не
    /// выдаём вчерашний день за сегодняшний.
    @Test func yesterdaysSnapshotSaysNothingAboutToday() throws {
        let state = try #require(snapshot("""
        {
          "date": "\(iso(daysAgo(1)))",
          "today": { "name": "Ноги", "type": "Legs", "isRest": false }
        }
        """))
        #expect(GymBridge.todayType(state) == nil)
    }

    /// Но делоад живёт неделю: он не исчезает оттого, что в зал не заходили сутки.
    @Test func deloadOutlivesADayOfSilence() throws {
        let state = try #require(snapshot("""
        { "date": "\(iso(daysAgo(2)))", "deload": { "isActive": true } }
        """))
        #expect(GymBridge.isDeload(state) == true)
    }

    /// А месячной давности снимок не говорит и о делоаде.
    @Test func aMonthOldSnapshotKnowsNothing() throws {
        let state = try #require(snapshot("""
        {
          "date": "\(iso(daysAgo(30)))",
          "deload": { "isActive": true },
          "week": { "totalSets": 55 }
        }
        """))
        #expect(GymBridge.isDeload(state) == nil, "Месяц назад — это не «сейчас делоад»")
        #expect(GymBridge.weeklySets(state) == nil)
    }

    /// День отдыха сосед называет явно — и это не то же самое, что молчание.
    @Test func restIsSaidOutLoudNotGuessed() throws {
        let state = try #require(snapshot("""
        { "date": "\(iso(Date()))", "today": { "isRest": true, "type": "Legs" } }
        """))
        #expect(GymBridge.todayType(state) == nil)
    }

    /// Соседа нет вовсе — не повод считать, что человек не тренируется.
    @Test func noNeighbourMeansUnknown() {
        #expect(GymBridge.isDeload(nil) == nil)
        #expect(GymBridge.weeklySets(nil) == nil)
        #expect(GymBridge.topMuscles(nil).isEmpty)
    }

    @Test func itReadsNothingFromAnEmptyGroup() {
        let defaults = TestDefaults.make()
        #expect(GymBridge.read(defaults: defaults) == nil)
    }

    @Test func garbageInTheGroupIsNotACrash() {
        let defaults = TestDefaults.make()
        defaults.set(Data("не json".utf8), forKey: GymBridge.key)
        #expect(GymBridge.read(defaults: defaults) == nil)
    }

    // MARK: - Самые нагруженные мышцы

    @Test func theBusiestMusclesComeFirst() throws {
        let state = try #require(snapshot("""
        {
          "date": "\(iso(Date()))",
          "week": { "totalSets": 48,
                    "setsByMuscle": { "Quads": 14, "Chest": 9.5, "Biceps": 4.5,
                                      "Calves": 6, "Rear Delt": 3 } }
        }
        """))
        #expect(GymBridge.topMuscles(state).map(\.muscle) == ["Quads", "Chest", "Calves"])
    }
}
