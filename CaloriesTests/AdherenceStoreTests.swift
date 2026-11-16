import Testing
import Foundation
import SwiftData
@testable import Calories

/// Привычки собираются из настоящего дневника, а не только из готовых дней.
@MainActor
@Suite(.serialized)
struct AdherenceStoreTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = CalorieStore(context: container.mainContext, defaults: TestDefaults.make(), groupDefaults: nil)
    }

    @Test func eightDaysOfMealsMakeHabits() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let schedule = MealScheduleSettings(defaults: TestDefaults.make())
        schedule.isEnabled = true
        for back in 1...8 {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            for (hour, minute) in [(9, 5), (13, 25), (16, 30), (18, 40)] {
                let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
                store.add(name: "Еда", calories: 500, macros: .zero, grams: 300, date: time)
            }
        }
        let days = store.adherenceDays(schedule: schedule)
        #expect(days.count == 8)
        let first = days.first?.meals.map { "\($0.period.rawValue):\($0.actualTime != nil)" } ?? []
        #expect(!first.isEmpty, "Нет приёмов в дне: \(first)")
        #expect(!MealAdherence.habits(days).isEmpty, "Дни: \(first)")
    }
}
