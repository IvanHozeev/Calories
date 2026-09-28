import Testing
@testable import Calories

/// Кто одалживает витамины своим продуктам.
///
/// Сравниваем русские названия, а не показываемые: набор идёт на английской
/// локали, и `localizedName` там вернёт английское.
struct VitaminDonorTests {
    private func donors(_ name: String, _ kcal: Int, _ protein: Double,
                        _ fat: Double, _ carbs: Double, limit: Int = 3) -> [String] {
        FoodCatalog.donors(forName: name, caloriesPer100g: kcal,
                           macrosPer100g: Macros(protein: protein, fat: fat, carbs: carbs),
                           limit: limit).compactMap(\.ru)
    }

    /// Совпадения по слову мало: «овсяное» есть и у молока, и у печенья, а
    /// печенье в девять раз калорийнее. Раньше состав печенья и предлагался.
    @Test func aNamesakeWithOtherNumbersIsNotOffered() {
        let found = donors("Овсяное молоко без сахара", 52, 0.3, 1.5, 6.6)
        #expect(!found.contains { $0.contains("Печенье") })
    }

    /// Фасоль в томате на сотню килокалорий — не сухая фасоль на триста.
    @Test func dryBeansDoNotFeedCookedOnes() {
        let beans = FoodCatalog.all.first { $0.ru == "Фасоль сухая" }
        let dry = try? #require(beans)
        #expect(dry.map { FoodCatalog.fits(calories: 100,
                                           macros: Macros(protein: 5, fat: 0.5, carbs: 15),
                                           donor: $0) } == false)
    }

    /// Свой продукт с тем же названием и теми же числами получает себя же.
    @Test func theSameFoodFindsItself() {
        #expect(donors("Банан", 89, 1.1, 0.3, 23).first == "Банан")
    }

    /// Еда названа коротким словом, а бренд — длинным. Раньше ключом было
    /// самое длинное слово, и «Pro 40 Protein Drink» искался по «drink».
    @Test func theBrandDoesNotDecideWhatTheFoodIs() {
        // Напиток на 55 ккал: батончик на 350 ему не донор, как бы ни совпадали
        // слова.
        #expect(donors("Pro 40 Protein Drink Salted Caramel", 55, 4.2, 1.0, 6.0).isEmpty)
        // А батончик с похожими числами — донор, хотя «protein» стоит в нём
        // четвёртым словом.
        #expect(donors("Allin extra soft protein bar", 377, 25, 12, 40)
                    .contains("Батончик протеиновый"))
    }

    /// Продукт без своих чисел проверять нечем — тогда сита нет.
    @Test func foodWithoutNumbersIsNotFiltered() {
        #expect(!donors("Хумус", 0, 0, 0, 0).isEmpty)
    }

    /// Выбор руками числами не ограничен: человек знает свою еду лучше нас.
    /// Но одолжить можно только то, у чего витамины есть.
    @Test func theManualSearchOffersOnlyFoodsWithVitamins() {
        let found = FoodCatalog.vitaminSources(matching: "молоко")
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { !$0.micronutrients.isEmpty })
        #expect(FoodCatalog.vitaminSources(matching: "").isEmpty)
    }

    /// Каталог дозаполнили по USDA: то, что раньше было пустым, теперь
    /// одалживать можно. Проверяем на молочном — там пропусков было больше всего.
    @Test func theCatalogKnowsWhatItUsedToLeaveEmpty() throws {
        for name in ["Творог 9%", "Кефир 1%", "Сливки 10%", "Брынза", "Судак"] {
            let food = try #require(FoodCatalog.all.first { $0.ru == name },
                                    "\(name) пропал из каталога")
            #expect(food.micronutrients.hasVitamins, "\(name) без витаминов")
        }
    }
}
