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

    /// Сдвиг окон сходится: сколько ни нажимай «Сдвинуть окно», приёмы не
    /// перекидывают друг друга по кругу. Привычка считается без личных
    /// сдвигов, поэтому нужный сдвиг — число, а не остаток; поставив его,
    /// приём больше не отстаёт, и кнопки у него нет.
    @Test func movingWindowsConverges() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let schedule = MealScheduleSettings(defaults: TestDefaults.make())
        schedule.isEnabled = true
        // Завтрак бывает и ранним, и очень поздним — таким, что при сдвиге
        // окна залезает в обеденное.
        let times: [(Int, Int, Int)] = [(9, 5, 0), (9, 40, 1), (10, 20, 2), (10, 50, 3), (9, 30, 4)]
        for back in 1...10 {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let breakfast = times[back % times.count]
            for (hour, minute) in [(breakfast.0, breakfast.1), (13, 25), (16, 30), (18, 40)] {
                let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
                store.add(name: "Еда", calories: 500, macros: .zero, grams: 300, date: time)
            }
        }
        var presses = 0
        for _ in 0..<12 {
            let habits = MealAdherence.habits(store.adherenceDays(schedule: schedule))
            let pending = habits.filter {
                $0.period != .nightSnack
                && abs($0.shiftMinutes - schedule.mealOffset($0.period)) >= MealAdherence.noticeableShiftMinutes
                && Int((Double($0.shiftMinutes) / 30).rounded()) * 30 != schedule.mealOffset($0.period)
            }
            guard let next = pending.first else { break }
            schedule.setMealOffset(Int((Double(next.shiftMinutes) / 30).rounded()) * 30, for: next.period)
            presses += 1
        }
        #expect(presses <= 4, "Окна всё ещё ездят после \(presses) нажатий")
        let again = MealAdherence.habits(store.adherenceDays(schedule: schedule))
        #expect(again.allSatisfy { habit in
            habit.period == .nightSnack
            || abs(habit.shiftMinutes - schedule.mealOffset(habit.period)) < MealAdherence.noticeableShiftMinutes
        }, "Остались расхождения после сдвигов")
    }

    /// Сдвиг приёма не меняет привычки соседей: запись принадлежит тому же
    /// приёму, что и до сдвига.
    @Test func anOffsetDoesNotChangeWhatTheNeighboursSee() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let schedule = MealScheduleSettings(defaults: TestDefaults.make())
        schedule.isEnabled = true
        for back in 1...8 {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            for (hour, minute) in [(10, 40), (13, 25), (16, 30), (18, 40)] {
                let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
                store.add(name: "Еда", calories: 500, macros: .zero, grams: 300, date: time)
            }
        }
        let before = MealAdherence.habits(store.adherenceDays(schedule: schedule)).map { "\($0.period.rawValue)\($0.shiftMinutes)" }
        schedule.setMealOffset(120, for: .breakfast)
        let after = MealAdherence.habits(store.adherenceDays(schedule: schedule)).map { "\($0.period.rawValue)\($0.shiftMinutes)" }
        #expect(before == after, "До \(before), после \(after)")
    }
}
