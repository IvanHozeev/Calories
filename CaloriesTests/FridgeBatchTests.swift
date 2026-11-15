import Testing
import Foundation
@testable import Calories

/// Какие по счёту сутки у сваренной партии.
struct FridgeBatchTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private func state(cooked: Date) -> DishBatch.State {
        DishBatch.state(cookedAt: cooked, totalGrams: 2000, eatenGrams: 600, servingGrams: 350,
                        now: cooked, calendar: calendar)
    }

    /// День готовки — первый, даже если уже вечер.
    @Test func theCookingDayIsTheFirst() {
        let batch = state(cooked: day(10, hour: 8))
        #expect(batch.dayNumber(now: day(10, hour: 22), calendar: calendar) == 1)
    }

    @Test func eachCalendarDayCountsOnce() {
        let batch = state(cooked: day(10))
        #expect(batch.dayNumber(now: day(11), calendar: calendar) == 2)
        #expect(batch.dayNumber(now: day(12), calendar: calendar) == 3)
        #expect(batch.dayNumber(now: day(13), calendar: calendar) == 4)
    }

    /// Дальше срока не считаем: полоска из четырёх отрезков, пятого нет.
    @Test func itNeverGoesPastTheShelfLife() {
        let batch = state(cooked: day(10))
        #expect(batch.dayNumber(now: day(20), calendar: calendar) == DishBatch.shelfLifeDays)
    }

    /// Утром другого дня, но раньше часа готовки, всё равно новый день.
    @Test func itCountsDaysNotHours() {
        let batch = state(cooked: day(10, hour: 20))
        #expect(batch.dayNumber(now: day(11, hour: 7), calendar: calendar) == 2)
    }
}
