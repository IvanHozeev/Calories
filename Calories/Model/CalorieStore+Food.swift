import Foundation

/// Дневник со стороны еды: из чего собран день, что предложить на остаток
/// приёма и к какой категории относится продукт.
///
/// Вынесено из `CalorieStore`, который дорос до полутора тысяч строк и стал
/// местом, где рядом живут расписание приёмов, замеры тела, план, история
/// расхода и вот это. Здесь только вопросы к дневнику — ни одной записи в
/// базу: всё, что меняет данные, осталось в самом сторе, вместе с контекстом
/// SwiftData и настройками, к которым у расширения в другом файле доступа нет.
/// Это не ограничение, а граница: изменения идут через методы стора, и то, что
/// их нельзя написать здесь, — свойство, а не неудобство.
extension CalorieStore {
    /// Категории ингредиентов блюда.
    ///
    /// У блюда состав известен точно, в отличие от приёма пищи, где его
    /// приходится восстанавливать из склеенного имени. Повторы схлопываются:
    /// курица с говядиной — это одно мясо, а не две вилки.
    func foodCategories(of dish: Dish) -> [FoodCategory] {
        var seen: Set<FoodCategory> = []
        var found: [FoodCategory] = []
        for ingredient in dish.ingredients {
            guard let match = category(ofProductNamed: ingredient.foodName),
                  seen.insert(match).inserted else { continue }
            found.append(match)
        }
        return found
    }

    private func category(ofProductNamed name: String) -> FoodCategory? {
        categoryByFoodName[name]
    }

    /// Есть ли уже такой продукт среди своих. По названию: у продукта из базы
    /// и у своей копии разные идентификаторы, а человек различает их по имени.
    func isInMyFoods(_ food: FoodItem) -> Bool {
        customFoods.contains { $0.name == food.name }
    }

    /// Недавнее — выводится из фактических записей дневника, а не из списка имён,
    /// который приходилось сопоставлять с каталогами. Продукт из Open Food Facts или
    /// со сканера штрихкода ни в своих продуктах, ни во встроенной базе не лежит,
    /// поэтому в «Недавнем» он раньше не появлялся вовсе.
    ///
    /// Берём только записи с указанным весом: без него пересчитать на 100 г нельзя,
    /// а быстрые записи «столько-то калорий» переиспользовать всё равно нечего.
    /// Недавнее — это и съеденное, и заведённое.
    ///
    /// Раньше сюда попадало только съеденное из дневника, и свежесозданный
    /// продукт было не найти: в списке по категориям он лежит среди тех, что
    /// завели полгода назад. Но заводят продукт ровно тогда, когда собираются
    /// им пользоваться, — значит он такой же недавний, как только что съеденный.
    ///
    /// Считается в `rebuildCaches`, а не в геттере. Вычисляемым оно пробегало всю
    /// историю дневника и создавало объекты SwiftData на каждую перерисовку —
    /// то есть на каждое нажатие клавиши в поиске, и экран добавления заметно
    /// подтормаживал на вводе.
    /// Что предложить на оставшиеся калории ближайшего приёма.
    ///
    /// Берём то, что человек уже ел за последний месяц: чужие рекомендации
    /// читаются как навязчивый совет, а собственный вчерашний творог — как
    /// подсказка. Порядок решают точность попадания, привычная порция и
    /// недобранный макрос.
    func mealSuggestions(remaining: Int, days: Int = 30) -> [MealSuggestions.Candidate] {
        guard remaining >= MealSuggestions.minimumRemaining else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast

        // Берём приёмы целиком: полдник на 400 ккал — это «творог с бананом»,
        // как человек его и ест, а не «творог 180 г». Одинаковые приёмы
        // считаем одним и помним, сколько раз он их ел.
        var byName: [String: (parts: [EntryComponent], calories: Int, macros: Macros, times: Int)] = [:]
        for entry in entries where entry.date >= cutoff {
            let existing = byName[entry.name]
            byName[entry.name] = (entry.composition, entry.calories, entry.macros, (existing?.times ?? 0) + 1)
        }

        let options = byName.map { name, value in
            MealSuggestions.Option(name: name, parts: value.parts, calories: value.calories,
                                   macros: value.macros, timesEaten: value.times)
        }
        let scaled = MealSuggestions.suggest(remaining: remaining, from: options, leadingMacro: focusMacro)

        // Пары добираем только тогда, когда готовых приёмов не хватило.
        // Свой вчерашний ужин — лучшая подсказка, какую можно дать; пара
        // собирается, когда подходящего ужина не было.
        guard scaled.count < MealSuggestions.limit else { return scaled }
        let pairs = MealSuggestions.pair(remaining: remaining,
                                         protein: proteinRemainingForMeal(remaining: remaining),
                                         from: pairPool(since: cutoff),
                                         limit: MealSuggestions.limit - scaled.count)
        // Пара, повторяющая состав уже предложенного приёма, — та же подсказка
        // другими словами.
        let shownNames = Set(scaled.flatMap { $0.parts.map(\.name) })
        return scaled + pairs.filter { Set($0.parts.map(\.name)).isDisjoint(with: shownNames) }
    }

    /// Сколько белка просится в этот приём.
    ///
    /// Не весь дневной остаток: если человек не добрал сорок граммов, а приём
    /// на четыреста килокалорий, в него столько не положить. Берём долю,
    /// пропорциональную калориям приёма в остатке дня, — и не меньше того, что
    /// в эти калории вообще влезает.
    private func proteinRemainingForMeal(remaining: Int) -> Double {
        guard let target = proteinTarget else { return 0 }
        let left = max(0, target - macrosToday.protein)
        let dayLeft = max(1, adaptedTodayGoal - consumedToday)
        let share = min(1, Double(remaining) / Double(dayLeft))
        return left * share
    }

    /// Продукты, из которых собираем пару: то, что человек ел сам.
    ///
    /// Только свои и съеденные — каталог целиком сюда пускать нельзя: подсказка
    /// из трёхсот незнакомых позиций читается как реклама, а не как помощь.
    private func pairPool(since cutoff: Date) -> [MealSuggestions.Food] {
        var times: [String: Int] = [:]
        for entry in entries where entry.date >= cutoff {
            for part in entry.composition where part.grams ?? 0 > 0 {
                times[part.name, default: 0] += 1
            }
        }
        return times.compactMap { name, count in
            guard let per100 = perHundredGrams(named: name), per100.calories > 0 else { return nil }
            return MealSuggestions.Food(name: name, caloriesPer100g: per100.calories,
                                        macrosPer100g: per100.macros, timesEaten: count)
        }
    }

    /// Недавние приёмы пищи — те, что собраны из нескольких продуктов.
    ///
    /// Люди едят одно и то же: та же овсянка с теми же добавками по утрам, тот
    /// же обед на работе. Собирать такой приём заново из пяти позиций — пять
    /// поисков и пять экранов порции вместо одного нажатия.
    ///
    /// Из одного продукта приёмы сюда не идут: для них уже есть «Недавнее»,
    /// и дублировать их второй строкой значит засорять список тем же самым.
    func recentMeals(limit: Int = 10, days: Int = 30) -> [FoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        var seen = Set<String>()
        var result: [FoodEntry] = []
        // `entries` уже отсортированы по убыванию даты — значит первое
        // встреченное имя и есть последний раз, когда это ели.
        for entry in entries where entry.date >= cutoff && entry.components.count >= 2 {
            guard !seen.contains(entry.name) else { continue }
            seen.insert(entry.name)
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    /// Из каких категорий продуктов собран день.
    ///
    /// Считается по составу приёма, а не по имени записи: у приёма из
    /// нескольких продуктов имя склеенное, и категории у него нет. Блюдо
    /// раскладывается на ингредиенты — «гречка с тунцом» это крупа и рыба,
    /// а не одна безымянная строка.
    func categoryBreakdown(on date: Date) -> [DayCategories.Part] {
        let day = Calendar.current.startOfDay(for: date)
        var items: [(category: FoodCategory?, calories: Int)] = []
        for entry in entriesByDay[day] ?? [] {
            if entry.components.isEmpty {
                items.append(contentsOf: split(named: entry.name, calories: entry.calories))
            } else {
                for component in entry.components {
                    items.append(contentsOf: split(named: component.name, calories: component.calories))
                }
            }
        }
        return DayCategories.split(items)
    }

    /// Калории одного названия по категориям: продукт — своей категорией,
    /// блюдо — по ингредиентам, всё остальное — в неизвестное.
    private func split(named name: String, calories: Int) -> [(category: FoodCategory?, calories: Int)] {
        if let category = categoryByFoodName[name] { return [(category, calories)] }
        if let dish = dishes.first(where: { $0.name == name }) {
            let total = dish.ingredients.reduce(0) { $0 + $1.calories }
            guard total > 0 else { return [(FoodCategory.dishes, calories)] }
            return dish.ingredients.map { ingredient in
                let share = Double(ingredient.calories) / Double(total)
                return (categoryByFoodName[ingredient.foodName],
                        Int((Double(calories) * share).rounded()))
            }
        }
        return [(nil, calories)]
    }

    /// Названия продуктов из склеенного имени приёма.
    ///
    /// Длинное имя обрезается многоточием, поэтому последний кусок может не
    /// совпасть ни с чем — он просто не найдётся и будет пропущен.
    static func joinedNameParts(_ name: String) -> [String] {
        name.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                     .trimmingCharacters(in: CharacterSet(charactersIn: "…")) }
            .filter { !$0.isEmpty }
    }

    /// Сколько строк держим в «Недавнем». Больше — это уже не «недавнее»,
    /// а второй список всего подряд, по которому снова надо искать глазами.
    static let recentLimit = 12
}
