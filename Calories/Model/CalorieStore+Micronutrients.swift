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
        var covered = 0
        var total = 0
        for entry in dayEntries {
            total += entry.calories
            // Без веса пересчитывать нечего: у записи «просто 300 ккал» нет
            // граммов, а состав задан на сто грамм. Такая запись честно
            // попадает в непокрытую часть дня, а не считается нулём.
            guard let grams = entry.grams, grams > 0,
                  let per100g = micronutrientsByFoodName[entry.name]
            else { continue }
            totals = totals + per100g.scaled(by: grams)
            covered += entry.calories
        }
        return MicronutrientDay(totals: totals, coveredCalories: covered, totalCalories: total)
    }

    /// Чем богата эта запись дневника. Пусто, если состав неизвестен или у
    /// записи нет веса — тогда и считать нечего.
    func notableMicronutrients(for entry: FoodEntry) -> [Micronutrient] {
        guard let grams = entry.grams, grams > 0,
              let per100g = micronutrientsByFoodName[entry.name]
        else { return [] }
        return per100g.notable(inGrams: grams)
    }

    /// Чем богат продукт в такой порции.
    ///
    /// Берём из словаря, а не у самого `FoodItem`: его свойство `micronutrients`
    /// разбирает JSON при каждом обращении, а строки списка перерисовываются на
    /// каждое нажатие клавиши в поиске — в базе это под три сотни разборов на
    /// один символ.
    func notableMicronutrients(forFoodNamed name: String, grams: Double) -> [Micronutrient] {
        guard let per100g = micronutrientsByFoodName[name] else { return [] }
        return per100g.notable(inGrams: grams)
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
