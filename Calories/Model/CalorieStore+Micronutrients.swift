import Foundation

/// Витамины и минералы за день — и на какой части дня это посчитано.
///
/// Доля здесь важнее самих чисел. Микронутриенты есть у продуктов встроенной
/// базы, но их никогда не будет у своей еды и у товаров из Open Food Facts:
/// в этих источниках таких данных просто нет. Значит любое дневное число
/// посчитано по части съеденного, и молчать об этом нельзя.
///
/// «Железо 8 мг» при половине дня без данных читается как дефицит, которого
/// может и не быть, — приложение соврёт умолчанием, а это худший вид вранья:
/// его нечем опровергнуть, потому что оно ничего не утверждало.
nonisolated struct MicronutrientDay: Equatable {
    /// Съедено за день в единицах нутриента.
    let totals: Micronutrients
    /// Калории, пришедшие из еды, про которую известен состав.
    let coveredCalories: Int
    let totalCalories: Int

    /// Какая часть дня учтена. Ноль, если день пуст.
    var coverage: Double {
        guard totalCalories > 0 else { return 0 }
        return min(1, Double(coveredCalories) / Double(totalCalories))
    }

    /// Ниже этой доли число показывать нельзя: оно уже не «примерно», а просто
    /// неверно. Половина дня без данных — это не оценка, а другой день.
    static let trustworthyCoverage = 0.6

    var isTrustworthy: Bool { coverage >= Self.trustworthyCoverage }

    static let empty = MicronutrientDay(totals: Micronutrients(), coveredCalories: 0, totalCalories: 0)
}

extension CalorieStore {
    /// Витамины и минералы за указанный день.
    func micronutrients(on date: Date) -> MicronutrientDay {
        let day = Calendar.current.startOfDay(for: date)
        let dayEntries = entriesByDay[day] ?? []
        guard !dayEntries.isEmpty else { return .empty }

        var totals = Micronutrients()
        var covered = 0.0
        var total = 0
        for entry in dayEntries {
            total += entry.calories
            // Без веса пересчитывать нечего: у записи «просто 300 ккал» нет
            // граммов, а состав задан на сто грамм. Такая запись честно
            // попадает в непокрытую часть дня, а не считается нулём.
            guard let grams = entry.grams, grams > 0,
                  let profile = nutrientProfilesByName[entry.name]
            else { continue }
            totals = totals + profile.per100g.scaled(by: grams)
            // Долей, а не целиком: у блюда из трёх ингредиентов, где состав
            // известен у двух, покрыты не все его калории. Записать их все —
            // значит объявить день изученным сильнее, чем он изучен.
            covered += Double(entry.calories) * profile.coverage
        }
        return MicronutrientDay(totals: totals,
                                coveredCalories: Int(covered.rounded()),
                                totalCalories: total)
    }

    /// Чем богата эта запись дневника. Пусто, если состав неизвестен или у
    /// записи нет веса — тогда и считать нечего.
    func notableMicronutrients(for entry: FoodEntry) -> [Micronutrient] {
        guard let grams = entry.grams, grams > 0 else { return [] }
        return notableMicronutrients(forFoodNamed: entry.name, grams: grams)
    }

    /// Чем богат продукт в такой порции.
    ///
    /// Берём из словаря, а не у самого `FoodItem`: его свойство `micronutrients`
    /// разбирает JSON при каждом обращении, а строки списка перерисовываются на
    /// каждое нажатие клавиши в поиске — в базе это под три сотни разборов на
    /// один символ.
    /// Блюдо с дырявым составом значков не получает: они говорят «богато вот
    /// этим», а по половине блюда такое утверждение — про половину блюда.
    func notableMicronutrients(forFoodNamed name: String, grams: Double) -> [Micronutrient] {
        guard let profile = nutrientProfilesByName[name], profile.isTrustworthy else { return [] }
        return profile.per100g.notable(inGrams: grams)
    }

    /// Доля суточной нормы по нутриенту — то, что показывают шкалой.
    ///
    /// Для натрия это доля потолка, а не выполнение цели: у него `isCeiling`,
    /// и трактовать его как недобор нельзя.
    func shareOfDailyValue(_ nutrient: Micronutrient, on date: Date) -> Double? {
        let day = micronutrients(on: date)
        guard day.isTrustworthy, let amount = day.totals[nutrient] else { return nil }
        return amount / nutrient.dailyValue
    }
}

/// Состав источника еды и то, насколько он вообще известен.
///
/// У продукта покрытие всегда полное: либо состав есть, либо продукта нет
/// в словаре. У блюда иначе — оно собрано из нескольких ингредиентов, и часть
/// из них может быть своими продуктами без состава. Тогда сумма посчитана
/// честно, но по неполному блюду, и молчать об этом нельзя ровно по той же
/// причине, по какой нельзя молчать о неполном дне: недобор, которого нет,
/// нечем опровергнуть.
nonisolated struct NutrientProfile: Equatable {
    let per100g: Micronutrients
    /// Доля массы, про которую состав известен. Единица у продукта, у блюда —
    /// сколько его граммов пришло из ингредиентов, найденных в базе.
    let coverage: Double

    init(per100g: Micronutrients, coverage: Double = 1) {
        self.per100g = per100g
        self.coverage = coverage
    }

    /// Стоит ли вообще показывать этот состав.
    ///
    /// Порог тот же, что у дня: ниже него число не «примерное», а про другую
    /// еду. Показать значки по трети блюда — значит сказать, чего в нём нет,
    /// имея в виду всего лишь, что мы этого не видели.
    var isTrustworthy: Bool { coverage >= MicronutrientDay.trustworthyCoverage }
}

nonisolated enum DishNutrients {
    /// Состав блюда на 100 г — по составу его ингредиентов.
    ///
    /// Считается на полный вес блюда, а не на вес известных ингредиентов.
    /// Второе выглядит точнее, но врёт в опасную сторону: неизвестная треть
    /// молча получила бы состав известных двух, и блюдо стало бы богаче, чем
    /// оно есть. Занижение вместе с честно названным покрытием — то же самое
    /// незнание, но сказанное вслух.
    static func profile(of ingredients: [DishIngredient],
                        composition: (String) -> Micronutrients?) -> NutrientProfile? {
        let totalGrams = ingredients.reduce(0) { $0 + $1.grams }
        guard totalGrams > 0 else { return nil }

        var totals = Micronutrients()
        var knownGrams = 0.0
        for ingredient in ingredients {
            guard ingredient.grams > 0, let per100g = composition(ingredient.foodName) else { continue }
            totals = totals + per100g.scaled(by: ingredient.grams)
            knownGrams += ingredient.grams
        }
        guard knownGrams > 0 else { return nil }

        // Обратно на сотню грамм блюда: суммы выше уже в единицах нутриента на
        // всю массу, а словарь везде хранит «на 100 г». `scaled(by:)` делит на
        // сотню, поэтому множитель — не 100/вес, а вдесятеро тысячный.
        let per100gOfDish = totals.scaled(by: 10_000 / totalGrams)
        return NutrientProfile(per100g: per100gOfDish, coverage: knownGrams / totalGrams)
    }
}
