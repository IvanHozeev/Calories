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

    // MARK: - Уваривание

    /// Коэффициент берётся свой, если его мерили, и справочный по категории,
    /// если нет. У каждой плиты и кастрюли он свой, но крупы ведут себя
    /// достаточно одинаково, чтобы не спрашивать с порога.
    @Test
    func anOwnYieldBeatsTheReferenceOne() {
        store.addCustomFood(name: "Гречка", caloriesPer100g: 330,
                            protein: 12, fat: 3, carbs: 62, category: .grains)
        #expect(store.cookingYield(forFoodNamed: "Гречка") == CookingYield.reference[.grains])

        store.setCookingYield(2.6, forFoodNamed: "Гречка")
        #expect(store.cookingYield(forFoodNamed: "Гречка") == 2.6)
    }

    /// Варится не всё: у продукта без категории с уварианием коэффициента
    /// нет, и выдумывать его не надо.
    @Test
    func whatDoesNotBoilHasNoYield() {
        store.addCustomFood(name: "Творог", caloriesPer100g: 120,
                            protein: 18, fat: 5, carbs: 3, category: .dairy)
        #expect(store.cookingYield(forFoodNamed: "Творог") == nil)
        #expect(store.cookingYield(forFoodNamed: "Чего нет вовсе") == nil)
    }

    /// Нелепое число не запоминается: коэффициент в десять раз — это
    /// опечатка, а не измерение, и жить с ней пришлось бы молча.
    @Test
    func anImplausibleYieldIsRefused() {
        store.addCustomFood(name: "Рис", caloriesPer100g: 340,
                            protein: 7, fat: 1, carbs: 75, category: .grains)
        store.setCookingYield(10, forFoodNamed: "Рис")
        #expect(store.cookingYield(forFoodNamed: "Рис") == CookingYield.reference[.grains])
    }

    /// Энергия при варке не появляется и не исчезает — она размазывается
    /// по большему весу. Вес вверх, калории на сто грамм вниз, итог тот же.
    @Test
    func boilingMovesTheWeightNotTheEnergy() throws {
        store.addCustomFood(name: "Макароны", caloriesPer100g: 350,
                            protein: 12, fat: 1, carbs: 70, category: .grains)
        store.setCookingYield(2.5, forFoodNamed: "Макароны")

        let dry = ingredient("Макароны", grams: 100, caloriesPer100g: 350)
        let cooked = store.cooked(dry)

        #expect(cooked.grams == 250)
        #expect(cooked.caloriesPer100g == 140)
        // Итог тот же с точностью до округления на сто грамм.
        #expect(abs(cooked.calories - dry.calories) <= 1)
        #expect(abs(cooked.macros.protein - dry.macros.protein) < 0.5)
    }

    /// Продукт без коэффициента возвращается как есть — не тронутым.
    @Test
    func whatDoesNotBoilComesBackUnchanged() {
        let raw = ingredient("Творог", grams: 200, caloriesPer100g: 120)
        let same = store.cooked(raw)
        #expect(same.grams == raw.grams)
        #expect(same.caloriesPer100g == raw.caloriesPer100g)
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
