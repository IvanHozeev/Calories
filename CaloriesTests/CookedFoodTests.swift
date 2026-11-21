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

    // MARK: - Сухой и готовый

    /// Коэффициент — только по двум весам, которые человек сам взвесил.
    @Test
    func theFactorComesFromTwoWeights() {
        #expect(CookingYield.factor(dry: 100, cooked: 250) == 2.5)
        #expect(CookingYield.factor(dry: 0, cooked: 250) == nil)
        #expect(CookingYield.factor(dry: 100, cooked: 0) == nil)
        // Перепутанные местами или опечатка — не коэффициент.
        #expect(CookingYield.factor(dry: 100, cooked: 5000) == nil)
        #expect(CookingYield.factor(dry: 5000, cooked: 100) == nil)
    }

    /// Вода калорий не несёт: на сто грамм готового их во столько раз меньше,
    /// во сколько раз потяжелело.
    @Test
    func cookedHundredGramsCarryTheDryEnergyDividedByTheFactor() {
        let result = CookingYield.cookedPer100g(calories: 350,
                                                macros: Macros(protein: 12, fat: 1, carbs: 70), factor: 2.5)
        #expect(result.calories == 140)
        #expect(abs(result.macros.protein - 4.8) < 0.001)
        #expect(abs(result.macros.carbs - 28) < 0.001)
    }

    @Test
    func aFoodWithoutAMeasurementHasNoCookedForm() {
        store.addCustomFood(name: "Макароны", caloriesPer100g: 350,
                            protein: 12, fat: 1, carbs: 70, category: .grains)
        #expect(store.customFoods.first?.cookedPer100g == nil)
    }

    @Test
    func theMeasurementIsStoredAndCanBeCleared() throws {
        store.addCustomFood(name: "Макароны", caloriesPer100g: 350,
                            protein: 12, fat: 1, carbs: 70, category: .grains)
        store.setCookingYield(2.5, forFoodNamed: "Макароны")
        let food = try #require(store.customFoods.first)
        #expect(food.cookedPer100g?.calories == 140)

        store.setCookingYield(nil, forFoodNamed: "Макароны")
        #expect(food.cookedPer100g == nil)
        // Нелепое число не запоминается.
        store.setCookingYield(40, forFoodNamed: "Макароны")
        #expect(food.cookingYield == nil)
    }

    /// Ингредиенты, записанные до появления «готового», читаются как раньше.
    @Test
    func anOldIngredientWithoutTheFlagStillDecodes() throws {
        let json = #"{"id":"6F2A1D68-2A8B-4C57-9C53-5B6E3D6B6F10","foodName":"Рис","caloriesPer100g":340,"macrosPer100g":{"protein":7,"fat":1,"carbs":75},"grams":200}"#
        let ingredient = try JSONDecoder().decode(DishIngredient.self, from: Data(json.utf8))
        #expect(ingredient.cooked == nil)
        #expect(ingredient.grams == 200)
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
