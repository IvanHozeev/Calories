import Testing
@testable import Calories

/// Кто одалживает витамины своим продуктам.
///
/// Сравниваем русские названия, а не показываемые: набор идёт на английской
/// локали, и `localizedName` там вернёт английское.
struct VitaminDonorTests {
    private func donors(_ name: String, _ kcal: Int, _ protein: Double,
                        _ fat: Double, _ carbs: Double,
                        category: FoodCategory = .other, limit: Int = 3) -> [String] {
        FoodCatalog.donors(forName: name, caloriesPer100g: kcal,
                           macrosPer100g: Macros(protein: protein, fat: fat, carbs: carbs),
                           category: category, limit: limit).compactMap(\.ru)
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

    /// Категория решает больше, чем слова: на выгрузке USDA пары, похожие только
    /// по калориям и макросам, расходились по веществам в 1.5–3.6 раза, а с
    /// совпадающей категорией — в 1.2–1.7.
    @Test func aDonorFromAnotherShelfIsRefused() throws {
        let milk = try #require(FoodCatalog.all.first { $0.ru == "Молоко 1.5%" })
        let numbers = Macros(protein: 2.9, fat: 1.5, carbs: 4.7)
        #expect(FoodCatalog.fits(calories: 44, macros: numbers, category: .dairy, donor: milk))
        #expect(!FoodCatalog.fits(calories: 44, macros: numbers, category: .produce, donor: milk))
        // Неизвестная категория ничего не утверждает — её и не сверяем.
        #expect(FoodCatalog.fits(calories: 44, macros: numbers, category: .other, donor: milk))
    }

    /// Обогащённому продукту донора по классу быть не может: премикс — решение
    /// завода. У таких строк в USDA витамина A в восемь раз больше обычного.
    @Test func aFortifiedLabelGetsNoClassDonor() {
        #expect(donors("Молоко обогащённое витаминами", 44, 2.9, 1.5, 4.7, category: .dairy).isEmpty)
        #expect(donors("Enriched wheat flour", 364, 10, 1, 76, category: .grains).isEmpty)
    }

    /// Переносим не состав целиком: витамины A и C зависят от сорта и нагрева,
    /// а соль добавляет технолог — в четверти случаев перенос насыпал бы её
    /// туда, где её нет.
    @Test func theUntransferableNutrientsStayBehind() throws {
        let banana = try #require(FoodCatalog.all.first { $0.ru == "Банан" })
        let borrowed = banana.micronutrients.transferable()
        #expect(borrowed[.potassium] == banana.micronutrients[.potassium])
        #expect(borrowed[.magnesium] != nil)
        #expect(borrowed[.vitaminA] == nil)
        #expect(borrowed[.vitaminC] == nil)
        #expect(borrowed[.sodium] == nil)
    }

    /// Оценка стоит меньше измерения: день, собранный из перенесённых составов,
    /// держится ровно на пороге доверия и показывается со знаком «≈».
    @Test func anEstimateIsWorthLessThanAMeasurement() {
        let measured = NutrientProfile(per100g: Micronutrients([.potassium: 300]))
        let estimated = NutrientProfile(per100g: Micronutrients([.potassium: 300]),
                                        coverage: NutrientProfile.estimateCoverage)
        #expect(measured.coverage > estimated.coverage)
        #expect(estimated.isTrustworthy, "Оценку показывать можно")
        let day = MicronutrientDay(totals: Micronutrients([.potassium: 300]),
                                   coveredCalories: 1200, fiberCoveredCalories: 0,
                                   estimatedCalories: 800, totalCalories: 2000)
        #expect(day.hasEstimates)
        #expect(!MicronutrientDay.empty.hasEstimates)
    }
}
