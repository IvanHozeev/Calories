import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Микронутриенты за день

/// Главное здесь — не арифметика, а честность про то, на какой части дня
/// число посчитано. Витаминов не будет ни у своей еды, ни у товаров из
/// Open Food Facts, и «железо 8 мг» при половине дня без данных читается как
/// дефицит, которого может не быть.
@MainActor
@Suite(.serialized)
struct MicronutrientDayTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
        store.dailyGoal = 2000
    }

    /// Продукт из встроенной базы, у которого точно есть состав.
    private func spinach() -> FoodItem {
        FoodDatabase.items.first { !$0.micronutrients.isEmpty && $0.name == "Spinach" }
            ?? FoodDatabase.items.first { !$0.micronutrients.isEmpty }!
    }

    @Test func anEmptyDayHasNothingAndNoCoverage() {
        let day = store.micronutrients(on: Date())
        #expect(day.totals.isEmpty)
        #expect(day.coverage == 0)
        #expect(!day.isTrustworthy)
    }

    @Test func aKnownProductContributesItsNutrientsScaledByWeight() {
        let food = spinach()
        let ironPer100g = food.micronutrients[.iron]
        store.add(name: food.name, calories: 46, macros: food.macrosPer100g, grams: 200)

        let day = store.micronutrients(on: Date())
        #expect(day.coverage == 1)
        if let ironPer100g {
            // Двести грамм — двойная порция состава.
            #expect(abs((day.totals[.iron] ?? 0) - ironPer100g * 2) < 0.001)
        }
    }

    @Test func foodWeKnowNothingAboutLowersCoverageInsteadOfCountingAsZero() {
        // Своя еда состава не несёт. Прибавить ноль означало бы объявить
        // дефицит там, где данных просто нет.
        let food = spinach()
        store.add(name: food.name, calories: 100, macros: food.macrosPer100g, grams: 100)
        store.add(name: "Шаурма у дома", calories: 900, macros: .zero, grams: 400)

        let day = store.micronutrients(on: Date())
        #expect(day.totalCalories == 1000)
        #expect(day.coveredCalories == 100)
        #expect(abs(day.coverage - 0.1) < 0.001)
        #expect(!day.isTrustworthy, "На десятой части дня показывать число нельзя")
    }

    // MARK: - Блюда

    @Test func aDishTakesItsCompositionFromIngredients() {
        let food = spinach()
        let ironPer100g = food.micronutrients[.iron] ?? 0
        // Двести грамм известного и ничего больше: состав блюда на сто грамм
        // обязан совпасть с составом продукта на сто грамм.
        let profile = DishNutrients.profile(
            of: [DishIngredient(foodName: food.name,
                                caloriesPer100g: 23, macrosPer100g: .zero, grams: 200)],
            composition: { _ in food.micronutrients }
        )
        #expect(profile?.coverage == 1)
        #expect(abs((profile?.per100g[.iron] ?? 0) - ironPer100g) < 0.001)
    }

    @Test func anUnknownIngredientLowersDishCoverageWithoutInflatingIt() {
        let food = spinach()
        let ironPer100g = food.micronutrients[.iron] ?? 0
        let profile = DishNutrients.profile(
            of: [
                DishIngredient(foodName: food.name,
                               caloriesPer100g: 23, macrosPer100g: .zero, grams: 100),
                DishIngredient(foodName: "Бабушкин соус",
                               caloriesPer100g: 300, macrosPer100g: .zero, grams: 100)
            ],
            composition: { name in name == food.name ? food.micronutrients : nil }
        )
        #expect(abs((profile?.coverage ?? 0) - 0.5) < 0.001)
        // Половина блюда без состава не получает состав второй половины:
        // на сто грамм блюда железа ровно половина от продукта.
        #expect(abs((profile?.per100g[.iron] ?? 0) - ironPer100g / 2) < 0.001)
    }

    @Test func aDishOfOnlyUnknownFoodHasNoProfileAtAll() {
        let profile = DishNutrients.profile(
            of: [DishIngredient(foodName: "Соус", caloriesPer100g: 300,
                                macrosPer100g: .zero, grams: 100)],
            composition: { _ in nil }
        )
        #expect(profile == nil, "Пустой состав — это отсутствие данных, а не нули")
    }

    @Test func aHalfKnownDishCoversOnlyHalfOfItsCaloriesInTheDay() {
        let food = spinach()
        let dish = Dish(name: "Салат из непонятного", ingredients: [
            DishIngredient(foodName: food.name, caloriesPer100g: 23,
                           macrosPer100g: .zero, grams: 100),
            DishIngredient(foodName: "Бабушкин соус", caloriesPer100g: 300,
                           macrosPer100g: .zero, grams: 100)
        ])
        container.mainContext.insert(dish)
        store.refresh()

        store.add(name: dish.name, calories: 400, macros: .zero, grams: 200)
        let day = store.micronutrients(on: Date())
        #expect(day.totalCalories == 400)
        // Половина ингредиентов без состава — половина калорий записи остаётся
        // непокрытой, иначе день объявлен изученным сильнее, чем он изучен.
        #expect(day.coveredCalories == 200)
    }

    @Test func fiberIsCountedOnItsOwnCoverageNotTheVitaminOne() {
        // Товар из Open Food Facts приносит одну клетчатку: витаминов там нет
        // и не будет. Раньше такой день прятал клетчатку вместе с витаминами,
        // хотя по ней он посчитан целиком.
        let yogurt = FoodItem(name: "Йогурт из магазина", caloriesPer100g: 60, protein: 5, fat: 2, carbs: 4)
        yogurt.micronutrients = Micronutrients([.fiber: 2])
        container.mainContext.insert(yogurt)
        store.refresh()
        store.add(name: yogurt.name, calories: 600, macros: .zero, grams: 1000)

        let day = store.micronutrients(on: Date())
        #expect(day.fiberCoverage == 1, "Клетчатка известна у всего съеденного")
        #expect(day.fiber == 20, "2 г на сто грамм при килограмме — двадцать грамм")
        #expect(!day.isTrustworthy, "Витаминов у такой еды нет, и день по ним не покрыт")
    }

    @Test func fiberHidesWhenMostOfTheDayIsUnknown() {
        let yogurt = FoodItem(name: "Йогурт из магазина", caloriesPer100g: 60, protein: 5, fat: 2, carbs: 4)
        yogurt.micronutrients = Micronutrients([.fiber: 2])
        container.mainContext.insert(yogurt)
        store.refresh()
        store.add(name: yogurt.name, calories: 100, macros: .zero, grams: 100)
        store.add(name: "Шаурма у дома", calories: 900, macros: .zero, grams: 400)

        let day = store.micronutrients(on: Date())
        #expect(day.fiber == nil, "На десятой части дня число про клетчатку — выдумка")
    }

    @Test func anEntryWithoutWeightCannotBeCounted() {
        // «Просто 300 ккал» — состав задан на сто грамм, а граммов нет.
        store.add(name: "Быстрая запись", calories: 300)
        let day = store.micronutrients(on: Date())
        #expect(day.coveredCalories == 0)
        #expect(day.totalCalories == 300)
    }

    @Test func theShareOfTheNormIsHiddenUntilTheDayIsCoveredEnough() {
        let food = spinach()
        store.add(name: food.name, calories: 50, macros: food.macrosPer100g, grams: 100)
        store.add(name: "Неизвестное", calories: 950, macros: .zero, grams: 300)
        #expect(store.shareOfDailyValue(.iron, on: Date()) == nil,
                "При покрытии 5% доля нормы — выдумка")

        store.add(name: food.name, calories: 2000, macros: food.macrosPer100g, grams: 100)
        let share = store.shareOfDailyValue(.iron, on: Date())
        #expect(share != nil, "Когда день покрыт, долю показывать можно")
    }

    @Test func aPortionIsMarkedOnlyForWhatItIsGenuinelyRichIn() {
        // Порог — пятая часть суточной нормы, привычная граница «хороший
        // источник». Ниже неё значки были бы на каждой строке: следовые
        // количества почти всего есть почти во всём.
        let nutrients = Micronutrients([.iron: 3.6, .zinc: 0.1])
        let marked = nutrients.notable(inGrams: 100)
        #expect(marked == [.iron], "3.6 мг железа — это 20% нормы, 0.1 мг цинка — меньше процента")
    }

    @Test func aBiggerPortionCrossesTheThresholdWhereASmallOneDoesNot() {
        // Значок относится к съеденному, а не к ста граммам: полбанки тунца и
        // ложка тунца — разные вещи.
        let nutrients = Micronutrients([.iron: 1.8])
        #expect(nutrients.notable(inGrams: 100).isEmpty)
        #expect(nutrients.notable(inGrams: 300) == [.iron])
    }

    @Test func theHeaviestContributionComesFirst() {
        // Показываем не больше трёх значков, поэтому порядок решает, какие
        // именно человек увидит.
        let nutrients = Micronutrients([.iron: 5.4, .calcium: 1300, .zinc: 2.2])
        let marked = nutrients.notable(inGrams: 100)
        #expect(marked.first == .calcium, "Кальций на сто процентов нормы, железо на тридцать")
        #expect(marked.count == 3)
    }

    @Test func nothingIsMarkedWhenCompositionIsUnknown() {
        #expect(Micronutrients().notable(inGrams: 200).isEmpty)
    }

    @Test func everyNutrientHasASymbolForTheBadge() {
        // Значок подписан символом, а не названием: «Ca» помещается в строку,
        // «Кальций» нет. Пустой символ оставил бы пустую капсулу.
        var seen = Set<String>()
        for nutrient in Micronutrient.allCases {
            #expect(!nutrient.symbol.isEmpty)
            #expect(nutrient.symbol.count <= 3)
            #expect(seen.insert(nutrient.symbol).inserted, "\(nutrient.symbol) повторяется")
        }
    }

    @Test func sodiumIsACeilingAndNotAGoal() {
        // Единственный нутриент в списке, который не надо «набирать». Если
        // показать его как недовыполненную норму, человек начнёт досаливать.
        #expect(Micronutrient.sodium.isCeiling)
        for nutrient in Micronutrient.allCases where nutrient != .sodium {
            #expect(!nutrient.isCeiling, "\(nutrient.rawValue) целью быть должен")
        }
    }

    @Test func everyNutrientHasANormToCompareWith() {
        for nutrient in Micronutrient.allCases {
            #expect(nutrient.dailyValue > 0, "\(nutrient.rawValue) не с чем сравнивать")
        }
    }
}

// MARK: - Связь своего продукта с каталогом

/// Свой продукт может занять витамины у строки каталога: с упаковки человек
/// переписывает калории и БЖУ, а витаминов там не бывает. Значения при этом
/// копируются, а не читаются по ссылке — иначе правка каталога молча меняла бы
/// историю дневника задним числом.
@MainActor
@Suite(.serialized)
struct CatalogLinkTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    @Test func ownNumbersSurviveTakingVitaminsFromTheCatalog() {
        let source = FoodCatalog.all.first { !$0.micronutrients.isEmpty }!
        store.addCustomFood(name: "Творог мой", caloriesPer100g: 90,
                            protein: 17, fat: 1, carbs: 3, category: .dairy,
                            micronutrients: source.micronutrients, catalogID: source.id)

        let saved = store.customFoods.first!
        // Числа с упаковки точнее любого справочника — их не трогаем.
        #expect(saved.caloriesPer100g == 90)
        #expect(saved.protein == 17)
        #expect(!saved.micronutrients.isEmpty)
        #expect(saved.catalogID == source.id)
    }

    @Test func theLinkIsRememberedSoItCanBeShownAndUndone() {
        let source = FoodCatalog.all.first { !$0.micronutrients.isEmpty }!
        store.addCustomFood(name: "Своё", caloriesPer100g: 100, protein: 5, fat: 5, carbs: 5,
                            micronutrients: source.micronutrients, catalogID: source.id)
        let food = store.customFoods.first!

        store.updateCustomFood(food, name: "Своё", caloriesPer100g: 100,
                               protein: 5, fat: 5, carbs: 5,
                               micronutrients: Micronutrients(), catalogID: nil)
        #expect(store.customFoods.first?.micronutrients.isEmpty == true)
        #expect(store.customFoods.first?.catalogID == nil)
    }

    @Test func theLinkSurvivesABackupAndRestore() throws {
        let source = FoodCatalog.all.first { !$0.micronutrients.isEmpty }!
        store.addCustomFood(name: "Творог мой", caloriesPer100g: 90,
                            protein: 17, fat: 1, carbs: 3, category: .dairy,
                            micronutrients: source.micronutrients, catalogID: source.id)

        let backup = store.makeBackup()
        store.addCustomFood(name: "Лишний", caloriesPer100g: 1, protein: 0, fat: 0, carbs: 0)
        store.restore(from: backup)

        let restored = store.customFoods.first { $0.name == "Творог мой" }
        #expect(store.customFoods.count == 1)
        #expect(restored?.catalogID == source.id)
        #expect(restored?.micronutrients.isEmpty == false)
    }
}

// MARK: - Недавнее

/// «Недавнее» — это и съеденное, и заведённое. И считается оно один раз на
/// изменение данных: вычисляемым свойством оно пробегало всю историю дневника
/// и создавало объекты SwiftData на каждую перерисовку, то есть на каждое
/// нажатие клавиши в поиске.
@MainActor
@Suite(.serialized)
struct RecentFoodTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    @Test func itIsCachedRatherThanRebuiltOnEveryRead() {
        store.add(name: "Овсянка", calories: 300, grams: 250)
        let first = store.recentFoods.first
        let second = store.recentFoods.first
        #expect(first != nil)
        #expect(first === second,
                "Недавнее обязано быть кэшем: пересобираясь на каждое чтение, оно тормозит ввод")
    }

    @Test func aLongHistoryDoesNotProduceALongList() {
        // Раньше объект создавался на каждое уникальное название за всю историю.
        for index in 0..<200 {
            store.add(name: "Продукт \(index)", calories: 100, grams: 100,
                      date: Date().addingTimeInterval(-Double(index) * 3600))
        }
        #expect(store.recentFoods.count == CalorieStore.recentLimit)
    }

    @Test func aJustCreatedProductCountsAsRecent() {
        // Продукт заводят ровно тогда, когда собираются им пользоваться.
        store.addCustomFood(name: "Мой творог", caloriesPer100g: 90,
                            protein: 17, fat: 1, carbs: 3, category: .dairy)
        #expect(store.recentFoods.contains { $0.name == "Мой творог" })
    }

    @Test func eatenAndCreatedAreOrderedTogetherByRecency() {
        store.add(name: "Съеденное давно", calories: 200, grams: 100,
                  date: Date().addingTimeInterval(-86_400))
        store.addCustomFood(name: "Заведённое сейчас", caloriesPer100g: 100,
                            protein: 1, fat: 1, carbs: 1)
        #expect(store.recentFoods.first?.name == "Заведённое сейчас")
    }
}

// MARK: - Предложение витаминов

/// Метка «здесь есть что взять» на своём продукте. Важно не то, что она
/// появляется, а то, что она не появляется зря: позвать зайти туда, где брать
/// нечего или уже взято, — хуже, чем не звать вовсе.
@MainActor
@Suite(.serialized)
struct VitaminOfferTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    @Test func aProductThatCouldBorrowVitaminsIsMarked() {
        // Название не совпадает с каталогом дословно, но поиск его находит.
        store.addCustomFood(name: "Spinach mine", caloriesPer100g: 23,
                            protein: 2.9, fat: 0.4, carbs: 3.6, category: .produce)
        let food = store.customFoods.first!
        #expect(store.foodsOfferedVitamins.contains(food.id))
    }

    @Test func aProductThatAlreadyHasVitaminsIsNotMarked() {
        let source = FoodCatalog.all.first { !$0.micronutrients.isEmpty }!
        store.addCustomFood(name: "Spinach mine", caloriesPer100g: 23,
                            protein: 2.9, fat: 0.4, carbs: 3.6, category: .produce,
                            micronutrients: source.micronutrients, catalogID: source.id)
        let food = store.customFoods.first!
        #expect(!store.foodsOfferedVitamins.contains(food.id))
    }

    @Test func aProductNamedExactlyLikeACatalogueRowIsNotMarked() {
        // Точное совпадение и так подтягивает состав по названию — звать
        // никуда не надо, брать уже нечего.
        let source = FoodCatalog.all.first { !$0.micronutrients.isEmpty }!
        store.addCustomFood(name: source.localizedName, caloriesPer100g: 50,
                            protein: 1, fat: 1, carbs: 1)
        let food = store.customFoods.first!
        #expect(!store.foodsOfferedVitamins.contains(food.id))
    }

    @Test func somethingWithNoCounterpartIsNotMarked() {
        // Раньше здесь была «Шаурма у Ашота»: у блюд каталога состава не было,
        // и предлагать им было нечего. Теперь он есть — считается по рецепту, —
        // и своя шаурма честно находит себе пару. Нужен пример, которого
        // в каталоге нет вовсе.
        store.addCustomFood(name: "Соус бабушкин", caloriesPer100g: 210,
                            protein: 12, fat: 10, carbs: 17)
        let food = store.customFoods.first!
        #expect(!store.foodsOfferedVitamins.contains(food.id))
    }

    @Test func everyDishInTheCatalogueKnowsItsComposition() {
        // Тридцать блюд каталога жили с макросами и без единого витамина, и день
        // из домашней еды показывал низкое покрытие, хотя ел человек ровно то,
        // про что каталог всё знает. Состав им считает сборщик по рецептам.
        let dishes = FoodCatalog.all.filter { $0.foodCategory == .dishes }
        #expect(dishes.count >= 25, "Блюда из каталога пропали")
        let without = dishes.filter { $0.micronutrients.isEmpty }
        #expect(without.isEmpty, "Без состава остались: \(without.map(\.en))")
    }

    @Test func aPartlyKnownDishSaysSoInsteadOfClaimingFullCoverage() {
        // У блюда, собранного из ингредиентов, часть которых без данных,
        // покрытие меньше единицы — и приложение по нему решает, показывать ли
        // значки. Заявить полное покрытие значило бы соврать умолчанием.
        let profiles = FoodCatalog.nutrientProfilesByName
        let partial = profiles.values.filter { $0.coverage < 0.999 }
        #expect(!partial.isEmpty, "Хотя бы у одного блюда покрытие неполное")
        #expect(profiles.values.allSatisfy { $0.coverage > 0 && $0.coverage <= 1 })
    }

    @Test func boiledPotatoIsNotASourceOfVitaminA() {
        // Автоподбор привязал картофель к сладкому картофелю, и варёная
        // картошка числилась с 961 мкг витамина A — то есть получала значок «A»
        // ни за что, а блюда с картошкой раздувались следом.
        let potato = FoodCatalog.all.first { $0.ru == "Картофель варёный" }
        let vitaminA = try! #require(potato).micronutrients[.vitaminA] ?? 0
        #expect(vitaminA < 10, "Витамина A в варёной картошке практически нет")
    }

    @Test func aDishFromTheCatalogueCanNowLendItsVitamins() {
        // Обратная сторона той же правки, и ради неё всё затевалось: домашняя
        // шаурма подтягивает состав у каталожной.
        store.addCustomFood(name: "Шаурма у Ашота", caloriesPer100g: 210,
                            protein: 12, fat: 10, carbs: 17)
        let food = store.customFoods.first!
        #expect(store.foodsOfferedVitamins.contains(food.id))
    }
}

// MARK: - Свойства продуктов

struct FoodTraitTests {

    private func traits(_ kcal: Int, p: Double, f: Double, c: Double, _ category: FoodCategory? = nil) -> [FoodTrait] {
        FoodTrait.traits(caloriesPer100g: kcal, macros: Macros(protein: p, fat: f, carbs: c), category: category)
    }

    @Test func cucumber_isAlmostNoCalories() {
        #expect(traits(15, p: 0.7, f: 0.1, c: 3.6) == [.almostNoCalories])
    }

    @Test func berries_eatALot() {
        #expect(traits(45, p: 1, f: 0.3, c: 10) == [.eatALot])
    }

    @Test func sweetSoda_isNotEatALot() {
        #expect(traits(42, p: 0, f: 0, c: 10.6, .drinks).isEmpty)
    }

    @Test func chickenBreast_hasThermicEffect() {
        #expect(traits(113, p: 23.6, f: 1.9, c: 0) == [.highThermicEffect])
    }

    @Test func cod_isBothLowCalorieAndThermic() {
        // Треска — 70 ккал: не «можно много», но белковая.
        #expect(traits(70, p: 16, f: 0.6, c: 0) == [.highThermicEffect])
    }

    @Test func chocolate_isEasyToOvereat() {
        #expect(traits(540, p: 6, f: 31, c: 58) == [.easyToOvereat])
    }

    @Test func nuts_areNotEasyToOvereat() {
        // Орехи почти один жир: легко переесть по калориям, но не то сочетание.
        #expect(!traits(650, p: 15, f: 60, c: 14).contains(.easyToOvereat))
    }

    @Test func rice_hasNoTraits() {
        #expect(traits(130, p: 2.7, f: 0.3, c: 28).isEmpty)
    }

    @Test func lowProteinWhiteFood_isNotThermic() {
        // Бульон: белок — больше половины калорий, но грамм слишком мало.
        #expect(!traits(15, p: 3, f: 0.2, c: 0).contains(.highThermicEffect))
    }
}

// MARK: - Разбор дня

struct DayAnalysisTests {

    private func input(protein: Double = 140, fat: Double = 60, carbs: Double = 300,
                       calories: Int = 2500, goal: Int = 2500,
                       isFast: Bool = false, inProgress: Bool = false) -> DayAnalysis.Input {
        .init(macros: Macros(protein: protein, fat: fat, carbs: carbs),
              calories: calories, goal: goal,
              proteinTarget: 136, fatTarget: 64, carbsTarget: 300,
              weightKg: 80, isFast: isFast, isInProgress: inProgress)
    }

    private func ids(_ advice: [DayAnalysis.Advice]) -> [String] { advice.map(\.id) }

    /// Белок закрыт и в норму попал — хвалим, а не молчим.
    @Test func aGoodDayIsCalledGood() {
        let result = DayAnalysis.advice(input())
        #expect(ids(result).contains("protein-ok"))
        #expect(ids(result).contains("calories-ok"))
        #expect(result.allSatisfy { $0.tone != .warning })
    }

    /// Недобор белка на дефиците — главное предупреждение дня.
    @Test func lowProteinIsAWarning() {
        let result = DayAnalysis.advice(input(protein: 90))
        let protein = result.first { $0.id == "protein-low" }
        #expect(protein?.tone == .warning)
    }

    /// Чуть-чуть не хватило — это замечание, а не тревога.
    @Test func almostEnoughProteinIsJustANote() {
        let result = DayAnalysis.advice(input(protein: 125))
        #expect(result.first { $0.id == "protein-close" }?.tone == .info)
        #expect(!ids(result).contains("protein-low"))
    }

    /// Жир ниже 0.5 г/кг — про гормоны, и это предупреждение.
    @Test func fatBelowTheFloorWarnsAboutHormones() {
        let result = DayAnalysis.advice(input(fat: 30))
        #expect(result.first { $0.id == "fat-low" }?.tone == .warning)
    }

    /// Углеводы ниже RDA — предупреждение про мозг и тренировки.
    @Test func lowCarbsWarn() {
        #expect(ids(DayAnalysis.advice(input(carbs: 90))).contains("carbs-low"))
    }

    /// Недобор и перебор по калориям одинаково заметны.
    @Test func bothUnderAndOverEatingAreFlagged() {
        #expect(ids(DayAnalysis.advice(input(calories: 1800))).contains("calories-low"))
        #expect(ids(DayAnalysis.advice(input(calories: 3200))).contains("calories-high"))
    }

    /// Пока день идёт, выводов не делаем: недобор в обед — не недобор.
    @Test func anUnfinishedDayIsNotJudged() {
        let result = DayAnalysis.advice(input(protein: 20, carbs: 50, calories: 600, inProgress: true))
        #expect(!ids(result).contains("protein-low"))
        #expect(!ids(result).contains("calories-low"))
    }

    /// В день голодания разбирать нечего.
    @Test func aFastDayIsLeftAlone() {
        let result = DayAnalysis.advice(input(protein: 0, fat: 0, carbs: 0, calories: 0, isFast: true))
        #expect(ids(result) == ["fast"])
    }

    /// Пустой день молчит, а не жалуется.
    @Test func anEmptyDaySaysNothing() {
        #expect(DayAnalysis.advice(input(protein: 0, fat: 0, carbs: 0, calories: 0)).isEmpty)
    }

    /// Клетчатка: мало — замечание про сытость, достаточно — похвала.
    @Test func fiberIsJudgedWhenItIsKnown() {
        var low = input(); low.fiber = 12
        #expect(ids(DayAnalysis.advice(low)).contains("fiber-low"))
        var enough = input(); enough.fiber = 34
        #expect(ids(DayAnalysis.advice(enough)).contains("fiber-ok"))
    }

    /// Про клетчатку молчим, когда состав съеденного неизвестен: ноль там
    /// значит «не посчитали», а не «не ел».
    @Test func unknownFiberIsNotJudged() {
        let result = DayAnalysis.advice(input())
        #expect(!ids(result).contains("fiber-low"))
        #expect(!ids(result).contains("fiber-ok"))
    }

    /// Состав считается в калориях: жир весит девять на грамм.
    @Test func compositionCountsCalories() throws {
        let parts = DayAnalysis.composition(Macros(protein: 100, fat: 100, carbs: 100))
        let fat = try #require(parts.first { $0.kind == .fat })
        let protein = try #require(parts.first { $0.kind == .protein })
        #expect(fat.share > protein.share)
        #expect(abs(parts.reduce(0) { $0 + $1.share } - 1) < 0.001)
        #expect(DayAnalysis.composition(.zero).isEmpty)
    }
}

// MARK: - Разбор ответов Open Food Facts

/// Ответы источника разбираются чистыми функциями, отдельно от запроса:
/// сетевой метод тестом не проверить, а разбор — единственное место, где
/// теряются данные. Клетчатка именно так и терялась: текстовый поиск её брал,
/// а ответ по штрихкоду — нет, хотя лежала она и там.
struct OpenFoodParsingTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func aScannedProductCarriesItsFiber() {
        let product = OpenFoodService.parseProduct(data("""
        {"status": 1, "product": {"product_name": "Хлеб цельнозерновой",
         "nutriments": {"energy-kcal_100g": 247, "proteins_100g": 9.5,
                        "fat_100g": 3.2, "carbohydrates_100g": 41, "fiber_100g": 6.8}}}
        """), barcode: "7290000000001")

        #expect(product?.name == "Хлеб цельнозерновой")
        #expect(product?.caloriesPer100g == 247)
        #expect(product?.micronutrients[.fiber] == 6.8,
                "Клетчатка из ответа по штрихкоду должна доезжать до продукта")
    }

    @Test func aScannedProductWithoutFiberKeepsAnEmptyComposition() {
        let product = OpenFoodService.parseProduct(data("""
        {"status": 1, "product": {"product_name": "Кола",
         "nutriments": {"energy-kcal_100g": 42, "carbohydrates_100g": 10.6}}}
        """), barcode: "5449000000996")

        #expect(product?.micronutrients.isEmpty == true,
                "Нуля клетчатки в ответе не было — значит, и утверждать нечего")
    }

    @Test func aProductWithoutCaloriesIsNotAProduct() {
        let product = OpenFoodService.parseProduct(data("""
        {"status": 1, "product": {"product_name": "Вода", "nutriments": {}}}
        """), barcode: "1")
        #expect(product == nil, "Дневник считает калории: без них запись бессмысленна")
    }

    @Test func anUnnamedProductIsNamedByItsBarcode() {
        let product = OpenFoodService.parseProduct(data("""
        {"status": 1, "product": {"product_name": "", "nutriments": {"energy-kcal_100g": 100}}}
        """), barcode: "7290000000001")
        #expect(product?.name.contains("7290000000001") == true)
    }

    @Test func aMissingProductIsNil() {
        #expect(OpenFoodService.parseProduct(data("{\"status\": 0}"), barcode: "1") == nil)
        #expect(OpenFoodService.parseProduct(data("<html>503</html>"), barcode: "1") == nil,
                "База иногда отвечает HTML — это не продукт, а сбой")
    }

    @Test func searchResultsCarryFiberAndSkipTheUnusable() throws {
        let items = try OpenFoodService.parseSearch(data("""
        {"products": [
          {"product_name": "Овсянка", "nutriments": {"energy-kcal_100g": 370, "proteins_100g": 13,
                                                     "fat_100g": 7, "carbohydrates_100g": 60, "fiber_100g": 10}},
          {"product_name": "", "nutriments": {"energy-kcal_100g": 100}},
          {"product_name": "Без калорий", "nutriments": {"proteins_100g": 5}}
        ]}
        """))

        #expect(items.count == 1, "Без имени или без калорий продукт в список не идёт")
        #expect(items.first?.micronutrients[.fiber] == 10)
    }
}

// MARK: - Разбор ответов USDA

/// У USDA берут ради витаминов и минералов: их нет больше нигде. Разбор —
/// единственное место, где они могут потеряться по дороге, и проверяется он
/// без сети, на куске настоящего ответа.
struct FoodDataCentralParsingTests {

    private func food(_ json: String) throws -> FoodDataCentralService.SearchResponse.Food {
        try JSONDecoder().decode(FoodDataCentralService.SearchResponse.Food.self, from: Data(json.utf8))
    }

    @Test func aFoodBringsItsMacrosAndMicronutrients() throws {
        // 1008 — калории, 1003/1004/1005 — белки, жиры, углеводы,
        // 1079 — клетчатка, 1089 — железо.
        let item = FoodDataCentralService.item(from: try food("""
        {"description": "Spinach, raw", "foodNutrients": [
          {"nutrientId": 1008, "value": 23}, {"nutrientId": 1003, "value": 2.86},
          {"nutrientId": 1004, "value": 0.39}, {"nutrientId": 1005, "value": 3.63},
          {"nutrientId": 1079, "value": 2.2}, {"nutrientId": 1089, "value": 2.71}]}
        """))

        #expect(item?.caloriesPer100g == 23)
        #expect(item?.protein == 2.86)
        #expect(item?.micronutrients[.fiber] == 2.2)
        #expect(item?.micronutrients[.iron] == 2.71)
    }

    @Test func aFoodWithoutCaloriesIsSkipped() throws {
        let item = FoodDataCentralService.item(from: try food("""
        {"description": "Water", "foodNutrients": [{"nutrientId": 1089, "value": 0.1}]}
        """))
        #expect(item == nil, "Дневник считает калории: без них запись не нужна")
    }

    @Test func anUnnamedFoodIsSkipped() throws {
        let item = FoodDataCentralService.item(from: try food("""
        {"description": "   ", "foodNutrients": [{"nutrientId": 1008, "value": 100}]}
        """))
        #expect(item == nil)
    }

    @Test func nutrientsThatAreNotThereStayUnknown() throws {
        let item = FoodDataCentralService.item(from: try food("""
        {"description": "Sugar", "foodNutrients": [{"nutrientId": 1008, "value": 387}]}
        """))
        #expect(item?.micronutrients[.iron] == nil,
                "Отсутствие данных — это не ноль: ноль утверждал бы дефицит")
    }
}
