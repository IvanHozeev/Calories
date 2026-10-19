import Testing
import Foundation
@testable import Calories

/// План против факта: пороги тут решают всё, и проверяются они здесь.
///
/// Предложение «подвинь завтрак на полчаса» человек получит один раз и
/// запомнит — если оно окажется глупым, он перестанет верить и остальным.
/// Поэтому важнее не то, что расчёт работает, а то, что он молчит, когда
/// данных мало или разброс случайный.
@Suite struct MealAdherenceTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Окно завтрака 7–10 с приёмом в 8:00 на 500 ккал.
    private func slot(_ day: Date,
                      _ period: MealPeriod,
                      planHour: Int,
                      window: ClosedRange<Int>,
                      planned: Int) -> MealSchedule.Slot {
        MealSchedule.Slot(index: 0,
                          period: period,
                          start: at(day, window.lowerBound),
                          end: at(day, window.upperBound),
                          time: at(day, planHour),
                          calories: planned,
                          planned: planned,
                          consumed: 0,
                          state: .done)
    }

    // MARK: - Один день

    @Test func aMealTakesWhatFellIntoItsWindow() {
        let today = day(0)
        let result = MealAdherence.day(today,
            slots: [slot(today, .breakfast, planHour: 8, window: 7...10, planned: 500)],
            entries: [(at(today, 9, 30), 300), (at(today, 9, 50), 200), (at(today, 13), 700)])

        let meal = try! #require(result.meals.first)
        #expect(meal.eatenCalories == 500, "Обед в окно завтрака попадать не должен")
        #expect(meal.actualTime == at(today, 9, 30), "Время приёма — по первой записи")
        #expect(meal.shiftMinutes == 90)
        #expect(meal.caloriesRatio == 1)
        #expect(!meal.skipped)
    }

    @Test func anEmptyWindowIsSkippedNotEatenLittle() {
        let today = day(0)
        let result = MealAdherence.day(today,
            slots: [slot(today, .breakfast, planHour: 8, window: 7...10, planned: 500)],
            entries: [(at(today, 13), 700)])

        let meal = try! #require(result.meals.first)
        #expect(meal.skipped)
        #expect(meal.shiftMinutes == nil)
        #expect(meal.caloriesRatio == nil, "У пропуска нет доли от плана")
    }

    // MARK: - Привычки

    /// Семь дней подряд завтрак случается на час позже плана.
    private func lateBreakfastWeek(shiftMinutes: Int, eaten: Int = 500) -> [MealAdherence.Day] {
        (0..<7).map { offset in
            let d = day(offset)
            let planned = at(d, 8)
            let actual = planned.addingTimeInterval(Double(shiftMinutes) * 60)
            return MealAdherence.day(d,
                slots: [slot(d, .breakfast, planHour: 8, window: 6...12, planned: 500)],
                entries: [(actual, eaten)])
        }
    }

    @Test func aSteadyShiftBecomesAHabit() {
        let habits = MealAdherence.habits(lateBreakfastWeek(shiftMinutes: 60))
        let breakfast = try! #require(habits.first { $0.period == .breakfast })
        #expect(breakfast.shiftMinutes == 60)
        #expect(breakfast.days == 7)
        #expect(breakfast.skippedDays == 0)
    }

    @Test func oneStrangeDayDoesNotMoveTheMedian() {
        var days = lateBreakfastWeek(shiftMinutes: 10)
        // Один раз человек позавтракал в четыре часа дня.
        let d = day(9)
        days.append(MealAdherence.day(d,
            slots: [slot(d, .breakfast, planHour: 8, window: 6...18, planned: 500)],
            entries: [(at(d, 16), 500)]))

        let breakfast = try! #require(MealAdherence.habits(days).first { $0.period == .breakfast })
        #expect(breakfast.shiftMinutes == 10, "Медиана не должна уезжать за одним днём")
    }

    @Test func tooFewDaysSayNothing() {
        let days = Array(lateBreakfastWeek(shiftMinutes: 60).prefix(4))
        #expect(MealAdherence.habits(days).isEmpty, "По четырём дням привычки ещё нет")
        #expect(MealAdherence.suggestions(for: days).isEmpty)
    }

    // MARK: - Предложения

    @Test func aSteadyShiftSuggestsMovingTheMeal() {
        let suggestions = MealAdherence.suggestions(for: lateBreakfastWeek(shiftMinutes: 75))
        #expect(suggestions.contains(.moveMeal(period: .breakfast, byMinutes: 75, days: 7)))
    }

    @Test func aQuarterOfAnHourIsNotWorthMoving() {
        let suggestions = MealAdherence.suggestions(for: lateBreakfastWeek(shiftMinutes: 12))
        #expect(suggestions.isEmpty, "Мелкий сдвиг — не повод переставлять расписание")
    }

    @Test func eatingHalfAgainAsMuchSuggestsResizing() {
        let suggestions = MealAdherence.suggestions(for: lateBreakfastWeek(shiftMinutes: 0, eaten: 750))
        let resize = suggestions.compactMap { suggestion -> Double? in
            if case let .resizeMeal(period, ratio, _) = suggestion, period == .breakfast { return ratio }
            return nil
        }
        #expect(resize == [1.5])
    }

    @Test func aWindowAlwaysEmptySuggestsDroppingIt() {
        let days = (0..<7).map { offset -> MealAdherence.Day in
            let d = day(offset)
            return MealAdherence.day(d,
                slots: [slot(d, .afternoonSnack, planHour: 16, window: 15...17, planned: 300)],
                entries: [(at(d, 13), 700)])
        }
        #expect(MealAdherence.suggestions(for: days)
            == [.dropMeal(period: .afternoonSnack, skippedDays: 7, ofDays: 7)])
    }

    /// Пропущенный через раз приём — ещё не лишний: так ест большинство.
    @Test func anOccasionallySkippedMealStays() {
        let days = (0..<7).map { offset -> MealAdherence.Day in
            let d = day(offset)
            let entries: [(date: Date, calories: Int)] = offset.isMultiple(of: 2)
                ? [(at(d, 16), 300)]
                : []
            return MealAdherence.day(d,
                slots: [slot(d, .afternoonSnack, planHour: 16, window: 15...17, planned: 300)],
                entries: entries)
        }
        #expect(!MealAdherence.suggestions(for: days).contains(where: {
            if case .dropMeal = $0 { return true }
            return false
        }))
    }
}
