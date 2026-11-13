import Testing
import Foundation
import SwiftData
@testable import Calories

/// Подсказки «Сегодня» и листа добавления: утреннее взвешивание, обычная
/// порция продукта и вчерашний приём в это же время.
@MainActor
@Suite(.serialized)
struct DayShortcutsTests {
    private let container: ModelContainer
    private let store: CalorieStore
    private let calendar = Calendar.current

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: Взвешивание только утром

    @Test func weighInRowIsShownInTheMorning() {
        #expect(WeighInWindow.isOpen(now: at(8), wakeHour: 7))
        #expect(WeighInWindow.isOpen(now: at(10, 59), wakeHour: 7))
    }

    @Test func weighInRowIsGoneInTheEvening() {
        #expect(!WeighInWindow.isOpen(now: at(11), wakeHour: 7))
        #expect(!WeighInWindow.isOpen(now: at(20, 17), wakeHour: 7))
    }

    /// Ранний подъём не закрывает окно в девять: до десяти вес ещё утренний.
    @Test func anEarlyRiserStillHasUntilTen() {
        #expect(WeighInWindow.isOpen(now: at(9, 30), wakeHour: 5))
        #expect(!WeighInWindow.isOpen(now: at(10), wakeHour: 5))
    }

    /// Поздний подъём сдвигает утро вместе с собой.
    @Test func aLateRiserGetsALaterMorning() {
        #expect(WeighInWindow.isOpen(now: at(14), wakeHour: 11))
        #expect(!WeighInWindow.isOpen(now: at(15), wakeHour: 11))
    }

    // MARK: Обычная порция

    private func part(_ name: String, _ grams: Double?) -> EntryComponent {
        EntryComponent(name: name, calories: 100, grams: grams)
    }

    @Test func aSingleServingIsNotAHabit() {
        #expect(UsualPortion.compute(parts: [part("Творог", 200)]).isEmpty)
    }

    /// Медиана: один двойной ужин не двигает обычную тарелку.
    @Test func theUsualPortionIsTheMedianRoundedToFive() {
        let portions = UsualPortion.compute(parts: [
            part("Творог", 180), part("Творог", 183), part("творог", 400),
        ])
        #expect(portions["творог"] == 185)
    }

    @Test func entriesWithoutGramsDoNotCount() {
        let portions = UsualPortion.compute(parts: [part("Яблоко", nil), part("Яблоко", nil), part("Яблоко", 150)])
        #expect(portions["яблоко"] == nil)
    }

    @Test func theStoreReadsPortionsFromTheDiary() {
        for daysAgo in 1...2 {
            store.add(name: "Творог", calories: 200, macros: .zero, grams: 200, date: at(8, daysAgo: daysAgo))
        }
        #expect(store.usualPortions()["творог"] == 200)
    }

    @Test func oldPortionsAreForgotten() {
        for daysAgo in [100, 120] {
            store.add(name: "Творог", calories: 200, macros: .zero, grams: 200, date: at(8, daysAgo: daysAgo))
        }
        #expect(store.usualPortions()["творог"] == nil)
    }

    // MARK: Вчера в это время

    @Test func yesterdaysMealAtTheSameHourIsFound() {
        let now = at(13)
        let dates = [at(8, daysAgo: 1), at(12, 40, daysAgo: 1), at(19, daysAgo: 1)]
        #expect(YesterdayAtThisTime.closest(to: now, among: dates) == 1)
    }

    @Test func aMealFarFromThisHourIsNotOffered() {
        let now = at(13)
        let dates = [at(8, daysAgo: 1), at(19, daysAgo: 1)]
        #expect(YesterdayAtThisTime.closest(to: now, among: dates) == nil)
    }

    /// Сегодняшнее и позавчерашнее — не «вчера».
    @Test func onlyYesterdayCounts() {
        let now = at(13)
        let dates = [at(13), at(13, daysAgo: 2)]
        #expect(YesterdayAtThisTime.closest(to: now, among: dates) == nil)
    }

    // MARK: Итог недели — семь полных дней

    /// Сегодняшний день ещё идёт: в среднее и в число записанных дней он
    /// не входит, иначе утренний завтрак занижал бы среднее за неделю.
    @Test func theWeekReviewLeavesTodayOut() {
        for daysAgo in 1...7 {
            store.add(name: "Ужин", calories: 2000, date: at(19, daysAgo: daysAgo))
        }
        store.add(name: "Завтрак", calories: 300, date: at(0, 5))
        let input = store.weekReviewInput()
        #expect(input.loggedDays == 7)
        #expect(input.eaten.allSatisfy { $0 == 2000 })
    }

    @Test func theWeekRangeEndsYesterday() {
        let now = at(13)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(WeekReviewView.weekRange(now: now).hasSuffix(yesterday.formatted(.dateTime.day().month(.wide))))
    }

    // MARK: Обычный приём в пустой день

    @Test func anEmptyDayOffersTheUsualMealOfThisHour() {
        for daysAgo in 1...3 {
            let parts = [EntryComponent(name: "Овсянка", calories: 150, grams: 200),
                         EntryComponent(name: "Банан", calories: 90, grams: 100)]
            store.add(name: "Овсянка, Банан", calories: 240, macros: .zero,
                      date: at(8, daysAgo: daysAgo), components: parts)
        }
        #expect(store.usualMealNow(now: at(8, 30))?.calories == 240)
        #expect(store.usualMealNow(now: at(19)) == nil)
    }
}
