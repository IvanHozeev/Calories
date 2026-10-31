import Testing
import Foundation
import SwiftData
@testable import Calories

/// Съеденное уменьшает остаток партии.
///
/// Звучит как то, что не нуждается в проверке, — и ровно поэтому нуждается:
/// остаток искали по имени записи, а приёмы здесь почти всегда составные и
/// называются склейкой. Человек съел пять порций из восьми, а кастрюля всё
/// ещё показывала полную.
@MainActor
@Suite(.serialized)
struct BatchEatingTests {

    private let container: ModelContainer
    private let store: CalorieStore

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(),
                             groupDefaults: nil)
    }

    /// Кастрюля на 3200 г, порция 400 — восемь порций.
    private func pot() -> Dish {
        store.addDish(name: "Паста с тунцом",
                      ingredients: [DishIngredient(foodName: "Паста",
                                                   caloriesPer100g: 100,
                                                   macrosPer100g: Macros(protein: 5, fat: 2, carbs: 15),
                                                   grams: 3200)],
                      servingGrams: 400)
        let dish = store.dishes[0]
        store.startBatch(of: dish, grams: 3200)
        return dish
    }

    @Test func aPlainEntryTakesFromThePot() throws {
        let dish = pot()
        store.add(name: dish.name, calories: 400, macros: .zero, grams: 400)

        let state = try #require(store.batchState(of: dish))
        #expect(state.remainingGrams == 2800)
        #expect(state.remainingServings == 7)
    }

    /// Главный случай: блюдо съели в составном приёме, и запись называется
    /// склейкой — имени блюда среди имён записей нет вовсе.
    @Test func aCompositeMealTakesFromThePotToo() throws {
        let dish = pot()
        store.add(name: "Паста с тунцом, Хлеб",
                  calories: 600, macros: .zero, grams: 480,
                  components: [
                    EntryComponent(name: "Паста с тунцом", calories: 400, grams: 400),
                    EntryComponent(name: "Хлеб", calories: 200, grams: 80),
                  ])

        let state = try #require(store.batchState(of: dish))
        #expect(state.remainingGrams == 2800, "Из кастрюли ушла одна порция, а не ноль")
    }

    /// Пять порций съедено — осталось три, и это ровно то, что человек видит
    /// в холодильнике.
    @Test func fiveServingsEatenLeaveThree() throws {
        let dish = pot()
        for _ in 0..<5 {
            store.add(name: "Паста с тунцом, Салат",
                      calories: 450, macros: .zero, grams: 500,
                      components: [
                        EntryComponent(name: "Паста с тунцом", calories: 400, grams: 400),
                        EntryComponent(name: "Салат", calories: 50, grams: 100),
                      ])
        }

        let state = try #require(store.batchState(of: dish))
        #expect(state.remainingGrams == 1200)
        #expect(state.remainingServings == 3)
    }

    /// Чужая еда в том же приёме кастрюлю не трогает.
    @Test func otherFoodInTheSameMealDoesNotCount() throws {
        let dish = pot()
        store.add(name: "Хлеб с маслом",
                  calories: 300, macros: .zero, grams: 120,
                  components: [EntryComponent(name: "Хлеб", calories: 300, grams: 120)])

        let state = try #require(store.batchState(of: dish))
        #expect(state.remainingGrams == 3200)
    }

    /// Съеденное до того, как сварили, — из прошлой кастрюли.
    @Test func mealsFromBeforeTheBatchDoNotCount() throws {
        store.addDish(name: "Паста с тунцом",
                      ingredients: [DishIngredient(foodName: "Паста",
                                                   caloriesPer100g: 100,
                                                   macrosPer100g: Macros(protein: 5, fat: 2, carbs: 15),
                                                   grams: 3200)],
                      servingGrams: 400)
        let dish = store.dishes[0]
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        store.add(name: dish.name, calories: 400, macros: .zero, grams: 400, date: yesterday)
        store.startBatch(of: dish, grams: 3200)

        let state = try #require(store.batchState(of: dish))
        #expect(state.remainingGrams == 3200)
    }
}
