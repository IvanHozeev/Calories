import Testing
import Foundation
@testable import Calories

/// «Как обычно» вставляет в приём сразу четыре позиции с порциями. Ошибка тут
/// стоит дороже, чем в подсказке одного продукта: её придётся разбирать
/// руками. Поэтому проверяем не то, что предложение находится, а то, что оно
/// не находится, когда повторов на самом деле нет.
@Suite struct UsualMealTests {

    private let calendar = Calendar.current

    private func part(_ name: String, _ calories: Int, grams: Double? = nil) -> EntryComponent {
        EntryComponent(name: name, calories: calories,
                       macros: Macros(protein: 10, fat: 5, carbs: 20), grams: grams)
    }

    private func meal(daysAgo: Int, hour: Int = 8,
                      _ parts: [EntryComponent]) -> (date: Date, parts: [EntryComponent]) {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return (date: date, parts: parts)
    }

    /// Обычный завтрак: овсянка, молоко, банан — три утра подряд.
    private var threeBreakfasts: [(date: Date, parts: [EntryComponent])] {
        (1...3).map { day in
            meal(daysAgo: day, [part("Овсянка", 300, grams: 80),
                                part("Овсяное молоко", 120, grams: 200),
                                part("Банан", 90, grams: 100)])
        }
    }

    // MARK: - Находит

    @Test func threeSameBreakfastsBecomeTheUsualOne() throws {
        let found = try #require(UsualMeal.suggestions(history: threeBreakfasts).first)
        #expect(found.times == 3)
        #expect(Set(found.parts.map(\.name)) == ["Овсянка", "Овсяное молоко", "Банан"])
        #expect(found.calories == 510)
    }

    /// Главное блюдо приёма — первым, как человек его и собирает.
    @Test func theBiggestPartComesFirst() throws {
        let found = try #require(UsualMeal.suggestions(history: threeBreakfasts).first)
        #expect(found.parts.first?.name == "Овсянка")
    }

    /// Человек не ест по рецепту: к обычному завтраку иногда добавляется
    /// банан, иногда забывается кофе. Это всё ещё тот самый завтрак.
    @Test func anOccasionalExtraDoesNotSplitTheHabit() throws {
        var history = threeBreakfasts
        history.append(meal(daysAgo: 4, [part("Овсянка", 300, grams: 80),
                                         part("Овсяное молоко", 120, grams: 200),
                                         part("Банан", 90, grams: 100),
                                         part("Кофе", 5, grams: 200)]))
        let found = try #require(UsualMeal.suggestions(history: history).first)
        #expect(found.times == 4)
        // Кофе был один раз из четырёх — в обычный завтрак он не входит.
        #expect(!found.parts.map(\.name).contains("Кофе"))
    }

    /// Порции медианные: одно утро с двойной порцией не должно её удваивать.
    @Test func portionsAreMedianNotLatest() throws {
        var history = threeBreakfasts
        history.append(meal(daysAgo: 0, [part("Овсянка", 600, grams: 160),
                                         part("Овсяное молоко", 120, grams: 200),
                                         part("Банан", 90, grams: 100)]))
        let found = try #require(UsualMeal.suggestions(history: history).first)
        let oats = try #require(found.parts.first { $0.name == "Овсянка" })
        #expect(oats.grams == 80)
        #expect(oats.calories == 300, "Калории должны пересчитаться под медианную порцию")
    }

    // MARK: - Молчит

    @Test func twiceIsNotAHabitYet() {
        let history = Array(threeBreakfasts.prefix(2))
        #expect(UsualMeal.suggestions(history: history).isEmpty)
    }

    /// Приём из одного продукта повторять незачем: для него есть «Недавнее».
    @Test func aSingleProductIsNotAMeal() {
        let history = (1...5).map { meal(daysAgo: $0, [part("Банан", 90, grams: 100)]) }
        #expect(UsualMeal.suggestions(history: history).isEmpty)
    }

    /// Три разных завтрака — не три повтора одного.
    @Test func differentMealsDoNotAddUp() {
        let history = [
            meal(daysAgo: 1, [part("Овсянка", 300), part("Молоко", 120)]),
            meal(daysAgo: 2, [part("Творог", 200), part("Ягоды", 60)]),
            meal(daysAgo: 3, [part("Яйца", 160), part("Хлеб", 140)]),
        ]
        #expect(UsualMeal.suggestions(history: history).isEmpty)
    }

    /// Обед на завтрак не предлагаем, даже если человек ест одно и то же.
    @Test func lunchIsNotOfferedForBreakfast() {
        let history = (1...4).map {
            meal(daysAgo: $0, hour: 13, [part("Паста", 500), part("Котлета", 300)])
        }
        #expect(UsualMeal.suggestions(history: history, period: .breakfast).isEmpty)
        #expect(!UsualMeal.suggestions(history: history, period: .lunch).isEmpty)
    }

    @Test func nothingFromAnEmptyDiary() {
        #expect(UsualMeal.suggestions(history: []).isEmpty)
    }

    // MARK: - Порядок

    /// Чаще — выше; при равной частоте ближе тот, что ели недавно.
    @Test func theMoreOftenTheHigher() throws {
        var history = threeBreakfasts
        history += (4...8).map { day in
            meal(daysAgo: day, [part("Творог", 200, grams: 200),
                                part("Ягоды", 60, grams: 100)])
        }
        let found = UsualMeal.suggestions(history: history)
        #expect(found.count == 2)
        #expect(found.first?.parts.contains { $0.name == "Творог" } == true)
    }
}
