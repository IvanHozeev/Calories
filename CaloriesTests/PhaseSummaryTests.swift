import Testing
import Foundation
import SwiftData
@testable import Calories

/// Завершили план раньше срока: в истории остаётся прожитое, а не задуманное.
@MainActor
@Suite(.serialized)
struct PhaseSummaryTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = TestDefaults.make()
        defaults.set(true, forKey: "is_premium")
        store = CalorieStore(context: container.mainContext, defaults: defaults, groupDefaults: nil)
        store.isPremium = true
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    @Test func anEarlyFinishKeepsTheWeeksAndWeightThatActuallyHappened() throws {
        // План на 20 недель до 70.7, прожито 12 с небольшим, вес встал на 74.1.
        store.startPlan(Plan(startDate: daysAgo(85), durationWeeks: 20,
                             startWeightKg: 77.5, targetWeightKg: 70.7))
        store.addWeight(77.5, date: daysAgo(84))
        store.addWeight(74.2, date: daysAgo(2))
        store.addWeight(74.0, date: daysAgo(1))
        store.addWeight(74.1, date: Date())

        store.cancelPlan()

        let record = try #require(store.phaseHistory.last)
        #expect(record.weeks == 12, "Недель — сколько прошло, а не сколько было в плане")
        #expect(record.plannedWeeks == 20)
        #expect(record.endedEarly == true)
        let end = try #require(record.endWeightKg)
        #expect(abs(end - 74.1) < 0.3, "Вес — тот, на котором остановились, а не целевой 70.7")
        #expect(record.plannedEndWeightKg.map { abs($0 - 70.7) < 0.2 } == true)
    }

    @Test func theWeeklyChangeIsTheFactNotThePlan() {
        let record = PhaseRecord(intent: .cut, startDate: daysAgo(84), endDate: Date(),
                                 startWeightKg: 77.5, endWeightKg: 74.1)
        let weekly = record.weeklyChangeKg
        #expect(weekly != nil)
        #expect(abs((weekly ?? 0) - (-3.4 / 12)) < 0.01)
    }

    @Test func aRecordWithoutThePlanFieldsStillDecodes() throws {
        let json = #"{"id":"6F2A1D68-2A8B-4C57-9C53-5B6E3D6B6F10","intent":"cut","startDate":0,"endDate":604800,"startWeightKg":80,"endWeightKg":79}"#
        let record = try JSONDecoder().decode(PhaseRecord.self, from: Data(json.utf8))
        #expect(record.plannedWeeks == nil)
        #expect(record.endedEarly == nil)
    }

    @Test func intakeIsAveragedOverTheDaysWithRecords() throws {
        store.add(name: "Обед", calories: 2000, macros: Macros(protein: 100, fat: 50, carbs: 200),
                  grams: nil, date: daysAgo(2), components: [])
        store.add(name: "Обед", calories: 3000, macros: Macros(protein: 140, fat: 60, carbs: 300),
                  grams: nil, date: daysAgo(1), components: [])
        let summary = try #require(store.intakeSummary(from: daysAgo(5), to: Date()))
        #expect(summary.days == 2, "Пустые дни не считаются")
        #expect(summary.calories == 2500)
        #expect(summary.protein == 120)
    }
}
