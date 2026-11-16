import Testing
import Foundation
import SwiftData
@testable import Calories

/// Сырое и готовое, партии и подсказки по рецепту.
///
/// Всё это считается от веса, и ошибка здесь тихая: человек взвешивает на
/// тарелке двести пятьдесят грамм отварных макарон, а приложение берёт их
/// за сухие — и записывает втрое больше калорий, не сказав ни слова.
@MainActor
@Suite(.serialized)
struct CookedFoodTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func ingredient(_ name: String, grams: Double = 100,
                            caloriesPer100g: Int = 350) -> DishIngredient {
        DishIngredient(foodName: name, caloriesPer100g: caloriesPer100g,
                       macrosPer100g: Macros(protein: 12, fat: 1, carbs: 70), grams: grams)
    }

    // MARK: - Партии

    /// Съели кастрюлю — партии больше нет, и напоминать о ней нечего.
    @Test
    func endingABatchClearsIt() throws {
        store.addDish(name: "Плов", ingredients: [ingredient("Рис", grams: 500)])
        let dish = try #require(store.dishes.first)

        store.startBatch(of: dish, grams: 1500)
        #expect(store.batchState(of: dish) != nil)
        #expect(!store.liveBatches().isEmpty)

        store.endBatch(of: dish)
        #expect(store.batchState(of: dish) == nil)
        #expect(store.liveBatches().isEmpty)
        #expect(store.batchHint() == nil)
    }

    /// Порядок срочности: испортилось важнее, чем доесть, а доесть важнее,
    /// чем сварить ещё. Из одной кастрюли говорит самая срочная.
    @Test
    func spoiledSpeaksBeforeEverythingElse() {
        let soon = Date().addingTimeInterval(86_400)
        #expect(store.rank(.spoiled) < store.rank(.eatToday(servingsLeft: 2)))
        #expect(store.rank(.eatToday(servingsLeft: 2)) < store.rank(.cookAgain(runsOutOn: soon)))
    }

    // MARK: - Подсказка по рецепту

    /// Две позиции рецепта в приёме и больше половины его веса — похоже,
    /// человек готовит именно его.
    @Test
    func theDraftIsRecognisedAsARecipe() throws {
        store.addDish(name: "Паста с курицей", ingredients: [
            ingredient("Макароны", grams: 200),
            ingredient("Курица", grams: 300),
            ingredient("Масло оливковое", grams: 10)
        ])
        let hint = store.recipeHint(for: ["Макароны", "Курица"])
        #expect(hint?.dish.name == "Паста с курицей")
        #expect(hint?.covered == 2)
    }

    /// Одна позиция — совпадение, а не рецепт: масло есть в каждом втором.
    @Test
    func oneIngredientIsNotARecipe() {
        store.addDish(name: "Паста с курицей", ingredients: [
            ingredient("Макароны", grams: 200),
            ingredient("Курица", grams: 300)
        ])
        #expect(store.recipeHint(for: ["Макароны"]) == nil)
        #expect(store.recipeHint(for: []) == nil)
    }

    /// Свой это продукт или из базы — вопрос имени, и отвечать на него
    /// надо одинаково, кто бы ни спрашивал.
    @Test
    func aFoodKnowsWhetherItIsMine() throws {
        store.addCustomFood(name: "Гречка", caloriesPer100g: 330,
                            protein: 12, fat: 3, carbs: 62, category: .grains)
        let mine = try #require(store.customFoods.first)
        #expect(store.isInMyFoods(mine))
    }
}
