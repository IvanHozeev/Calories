import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Test helpers

/// Одноразовый контейнер настроек на каждый тест.
///
/// Юнит-тесты хостятся внутри процесса Calories.app (TEST_HOST), поэтому
/// `UserDefaults.standard` в них — это боевые настройки пользователя: профиль, план,
/// цель, премиум. Любая запись или очистка `.standard` из тестов уничтожает реальные
/// данные на устройстве/симуляторе. Поэтому сторы всегда получают отдельный suite.
enum TestDefaults {
    static func make() -> UserDefaults {
        let name = "tests.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? UserDefaults()
    }
}

// MARK: - CalorieStore

@MainActor
@Suite(.serialized)
struct CalorieStoreTests {

    private let container: ModelContainer
    private let store: CalorieStore
    private let defaults: UserDefaults

    init() async throws {
        defaults = TestDefaults.make()
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext, defaults: defaults, groupDefaults: nil)
        store.dailyGoal = 2000
    }

    @Test func trialGivesPremiumForTwoWeeks() {
        #expect(!store.isPremium)
        store.startTrialIfNeeded()
        #expect(store.isPremium)
        #expect(store.trialDaysLeft == CalorieStore.trialDays)
        #expect(!store.hasPurchasedPremium)
    }

    @Test func expiredTrialTakesPremiumAway() {
        store.startTrialIfNeeded(now: Date().addingTimeInterval(-15 * 86_400))
        #expect(!store.isPremium)
        #expect(store.trialDaysLeft == nil)
    }

    @Test func trialStartsOnlyOnce() {
        let old = Date().addingTimeInterval(-20 * 86_400)
        store.startTrialIfNeeded(now: old)
        store.startTrialIfNeeded()
        #expect(!store.isTrialActive)
    }

    @Test func trialEnded_onlyAfterTrialAndWithoutPurchase() {
        #expect(!store.trialEnded)
        store.startTrialIfNeeded(now: Date().addingTimeInterval(-15 * 86_400))
        #expect(store.trialEnded)
        store.isPremium = true
        #expect(!store.trialEnded)
    }

    @Test func trialSummary_countsLoggedDaysWithinTheTrial() {
        // От полудня: иначе поздно вечером запись «через час» уезжала на
        // следующие сутки, и тест насчитывал три дня вместо двух.
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .hour, value: 12,
                                  to: calendar.startOfDay(for: Date().addingTimeInterval(-15 * 86_400)))!
        store.startTrialIfNeeded(now: start)
        store.add(name: "A", calories: 500, date: start.addingTimeInterval(86_400))
        store.add(name: "B", calories: 500, date: start.addingTimeInterval(2 * 86_400))
        store.add(name: "C", calories: 500, date: start.addingTimeInterval(2 * 86_400 + 3600))
        // Запись после конца пробного периода в итог не входит.
        store.add(name: "D", calories: 500, date: Date())
        #expect(store.trialSummary?.loggedDays == 2)
    }

    @Test func weekStrip_goesBackToTheFirstEntryAndEndsToday() {
        #expect(store.weekStripWeeks().count == 1)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        store.add(name: "A", calories: 500, date: calendar.date(byAdding: .day, value: -8, to: today)!.addingTimeInterval(3600))
        let weeks = store.weekStripWeeks()
        #expect(weeks.count == 2)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.last?.last?.date == today)
        #expect(weeks.first?.first?.date == calendar.date(byAdding: .day, value: -13, to: today))
    }

    @Test func weekStrip_isCappedAtTwelveWeeks() {
        store.add(name: "A", calories: 500, date: Date().addingTimeInterval(-200 * 86_400))
        #expect(store.weekStripWeeks().count == 12)
    }

    @Test func purchaseOutlivesTheTrial() {
        store.startTrialIfNeeded(now: Date().addingTimeInterval(-15 * 86_400))
        store.isPremium = true
        #expect(store.isPremium)
        #expect(store.hasPurchasedPremium)
    }

    @Test func dishServingDefaultsToTheWholeBatch() {
        // Без своей порции подставляется полный вес — так было и раньше.
        let dish = Dish(name: "Борщ", ingredients: [
            DishIngredient(foodName: "Свёкла", caloriesPer100g: 43, macrosPer100g: .zero, grams: 300),
            DishIngredient(foodName: "Говядина", caloriesPer100g: 250, macrosPer100g: .zero, grams: 400),
        ])
        #expect(dish.totalGrams == 700)
        #expect(dish.servingGrams == 700)

        // А с указанной — она и подставится: готовят на несколько раз
        dish.defaultServingGrams = 350
        #expect(dish.servingGrams == 350)
    }

    @Test func dishWithoutIngredientsFallsBackToAHundredGrams() {
        // Пустое блюдо не должно давать ноль в поле массы.
        let empty = Dish(name: "Пусто")
        #expect(empty.servingGrams == 100)
    }

    @Test func dishShowsCategoriesOfItsIngredients() {
        // У блюда состав известен точно, восстанавливать его из имени не нужно.
        store.addCustomFood(name: "Мой рис", caloriesPer100g: 130, protein: 3, fat: 0, carbs: 28, category: .grains)
        store.addCustomFood(name: "Моя курица", caloriesPer100g: 165, protein: 31, fat: 4, carbs: 0, category: .meat)
        store.addCustomFood(name: "Моя индейка", caloriesPer100g: 150, protein: 29, fat: 3, carbs: 0, category: .meat)

        let dish = Dish(name: "Обед", ingredients: [
            DishIngredient(foodName: "Моя курица", caloriesPer100g: 165, macrosPer100g: Macros(protein: 31, fat: 4, carbs: 0), grams: 150),
            DishIngredient(foodName: "Мой рис", caloriesPer100g: 130, macrosPer100g: Macros(protein: 3, fat: 0, carbs: 28), grams: 200),
            DishIngredient(foodName: "Моя индейка", caloriesPer100g: 150, macrosPer100g: Macros(protein: 29, fat: 3, carbs: 0), grams: 100),
        ])

        // Порядок как в составе, два мяса схлопываются в одно
        #expect(store.foodCategories(of: dish) == [.meat, .grains])

        // Незнакомый ингредиент просто пропускается
        let mystery = Dish(name: "Загадка", ingredients: [
            DishIngredient(foodName: "Неизвестно что", caloriesPer100g: 100, macrosPer100g: .zero, grams: 100)
        ])
        #expect(store.foodCategories(of: mystery).isEmpty)
    }

    @Test func diaryRowShowsCategoryOfAFreshCustomProduct() {
        // Ровно сценарий из жизни: завёл свой хлеб, съел, посмотрел в дневник.
        store.addCustomFood(name: "Хлеб с семенами", caloriesPer100g: 280, protein: 9, fat: 6, carbs: 45, category: .grains)
        store.add(name: "Хлеб с семенами", calories: 140, macros: Macros(protein: 4.5, fat: 3, carbs: 22.5), grams: 50)

        let entry = store.entries.first { $0.name == "Хлеб с семенами" }
        #expect(entry != nil, "Запись не попала в дневник")
        #expect(store.foodCategories(forEntryNamed: "Хлеб с семенами") == [.grains])
    }

    @Test func recentFoodsKeepTheirCategory() {
        // Недавнее пересобирается из записей дневника: категорию оно должно
        // восстанавливать по названию, иначе весь список показывает «Другое».
        store.addCustomFood(name: "Мой творог", caloriesPer100g: 120, protein: 18, fat: 5, carbs: 3, category: .dairy)
        store.add(name: "Мой творог", calories: 240, macros: Macros(protein: 36, fat: 10, carbs: 6), grams: 200)

        let recent = store.recentFoods.first { $0.name == "Мой творог" }
        #expect(recent?.foodCategory == .dairy)
    }

    @Test func entryCategoriesAreRecoveredFromTheJoinedName() {
        // Запись дневника категорий не хранит: приём пищи собирается из нескольких
        // продуктов. Зато его имя склеено из названий через запятую.
        store.addCustomFood(name: "Мой протеин", caloriesPer100g: 380, protein: 80, fat: 5, carbs: 5, category: .dairy)
        store.addCustomFood(name: "Мой батончик", caloriesPer100g: 400, protein: 20, fat: 15, carbs: 45, category: .sweets)

        #expect(store.foodCategories(forEntryNamed: "Мой протеин") == [.dairy])
        #expect(store.foodCategories(forEntryNamed: "Мой протеин, Мой батончик") == [.dairy, .sweets])

        // Незнакомый кусок пропускается, а не отменяет остальные значки
        #expect(store.foodCategories(forEntryNamed: "Мой протеин, Неизвестно что") == [.dairy])
        #expect(store.foodCategories(forEntryNamed: "Приём пищи").isEmpty)
        #expect(store.foodCategories(forEntryNamed: "").isEmpty)
    }

    @Test func entryCategoriesCollapseRepeats() {
        // Курица с говядиной — это одно мясо, а не две одинаковые вилки подряд.
        store.addCustomFood(name: "Курочка", caloriesPer100g: 165, protein: 31, fat: 4, carbs: 0, category: .meat)
        store.addCustomFood(name: "Говядинка", caloriesPer100g: 250, protein: 26, fat: 15, carbs: 0, category: .meat)
        #expect(store.foodCategories(forEntryNamed: "Курочка, Говядинка") == [.meat])
    }

    @Test func entryCategoriesSurviveATruncatedName() {
        // Длинные имена обрезаются многоточием — обрубок не должен ломать разбор.
        store.addCustomFood(name: "Мой протеин", caloriesPer100g: 380, protein: 80, fat: 5, carbs: 5, category: .dairy)
        #expect(store.foodCategories(forEntryNamed: "Мой протеин, Овсянка на в…") == [.dairy])
    }

    // MARK: Initial state

    @Test func initialState_noEntries() {
        #expect(store.todayEntries.isEmpty)
        #expect(store.consumedToday == 0)
    }

    @Test func initialState_sevenDaysHistory() {
        #expect(store.lastSevenDays.count == 7)
    }

    // MARK: Фиксация целей

    /// lockPastGoals лочит дни пачкой, а adaptedGoal(for:) читает цели предыдущих дней
    /// недели. Раньше словарь goalsByDay внутри цикла не обновлялся, а порядок обхода Set
    /// был случайным — из-за чего одни и те же данные давали разные цели в истории
    /// в зависимости от того, когда пользователь открыл приложение.
    @Test func lockPastGoals_isIndependentOfWhenAppWasOpened() {
        let calendar = Calendar.current
        store.isPremium = true
        store.dailyGoal = 2000

        // Пять прошедших дней подряд с недобором.
        for offset in stride(from: 5, through: 1, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            store.add(name: "День \(offset)", calories: 1500, date: date)
        }
        store.lockPastGoals()
        let lockedAtOnce = store.goalRecords
            .sorted { $0.date < $1.date }
            .map(\.goal)

        #expect(lockedAtOnce.count == 5)
        // Значения должны быть воспроизводимыми: повторный вызов ничего не меняет.
        store.lockPastGoals()
        let again = store.goalRecords.sorted { $0.date < $1.date }.map(\.goal)
        #expect(again == lockedAtOnce, "Повторная фиксация не должна менять уже записанные цели")
    }

    // MARK: Смена суток

    /// Кэши «сегодня» собираются один раз, поэтому после полуночи приложение показывало
    /// вчерашний день, пока пользователь не потянет список или не добавит запись.
    @Test func refreshIfDayChanged_rebuildsWhenDayRolledOver() {
        store.add(name: "Вчера", calories: 500,
                  date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        store.add(name: "Сегодня", calories: 300)

        #expect(store.consumedToday == 300)

        // Кэш собран на сегодня — повторный вызов ничего не меняет и стоит дёшево.
        store.refreshIfDayChanged()
        #expect(store.consumedToday == 300)
        #expect(store.todayEntries.count == 1)
    }

    // MARK: Недавнее

    /// Раньше «недавнее» искало продукт по имени в своих продуктах и встроенной базе,
    /// поэтому съеденное из внешней базы или со сканера туда не попадало никогда.
    @Test func recentFoods_includesFoodNotInAnyCatalogue() {
        store.add(name: "Батончик из сканера", calories: 200,
                  macros: Macros(protein: 10, fat: 5, carbs: 20), grams: 50)

        let recent = store.recentFoods
        #expect(recent.first?.name == "Батончик из сканера")
        // 200 ккал на 50 г — значит 400 на 100 г.
        #expect(recent.first?.caloriesPer100g == 400)
        #expect(recent.first?.defaultGrams == 50)
    }

    @Test func recentFoods_newestFirstAndDeduplicated() {
        store.add(name: "Первый", calories: 100, grams: 100, date: Date().addingTimeInterval(-300))
        store.add(name: "Второй", calories: 100, grams: 100, date: Date().addingTimeInterval(-200))
        store.add(name: "Первый", calories: 100, grams: 100, date: Date().addingTimeInterval(-100))

        #expect(store.recentFoods.map(\.name) == ["Первый", "Второй"])
    }

    @Test func recentFoods_skipsEntriesWithoutWeight() {
        store.add(name: "Быстрая запись", calories: 500)

        #expect(store.recentFoods.isEmpty,
                "Без веса пересчитать на 100 г нельзя, такие записи в недавнем не нужны")
    }

    /// Приём из нескольких продуктов раньше уходил в дневник одной строкой
    /// со склеенным именем и без веса — и продукты внутри него в «Недавнем»
    /// не появлялись вовсе. Протеин, съеденный двенадцать раз за месяц, не
    /// показывался ни разу, потому что в одиночку его не записывали никогда.
    @Test func recentFoods_seeProductsInsideAMealOfSeveral() {
        store.add(name: "Хала, Молоко, Whey Protein", calories: 700,
                  macros: Macros(protein: 40, fat: 15, carbs: 90), grams: nil,
                  date: Date(), components: [
                      EntryComponent(name: "Хала", calories: 300,
                                     macros: Macros(protein: 9, fat: 5, carbs: 55), grams: 100),
                      EntryComponent(name: "Молоко", calories: 100,
                                     macros: Macros(protein: 6, fat: 3, carbs: 10), grams: 200),
                      EntryComponent(name: "Whey Protein", calories: 300,
                                     macros: Macros(protein: 25, fat: 7, carbs: 25), grams: 30),
                  ])

        let names = store.recentFoods.map(\.name)
        #expect(names.contains("Whey Protein"), "Продукт внутри приёма — тоже недавний")
        #expect(names.contains("Молоко"))
        #expect(!names.contains("Хала, Молоко, Whey Protein"),
                "Склеенное имя приёма — не продукт, добавить его заново нельзя")

        // Пересчёт на сто грамм идёт по весу самого продукта, а не всего приёма.
        let whey = store.recentFoods.first { $0.name == "Whey Protein" }
        #expect(whey?.caloriesPer100g == 1000)
        #expect(whey?.defaultGrams == 30)
    }

    /// Записи, сделанные до того, как состав начали хранить, — всё, что от
    /// состава осталось, это склеенное имя. Разбираем его, иначе месяцы
    /// истории так и останутся невидимыми для «Недавнего».
    @Test func recentFoods_recoverProductsFromOldJoinedNames() {
        store.addCustomFood(name: "Whey Protein", caloriesPer100g: 400,
                            protein: 80, fat: 5, carbs: 10)
        store.add(name: "Хала, Whey Protein", calories: 700,
                  macros: Macros(protein: 40, fat: 15, carbs: 90))

        #expect(store.recentFoods.map(\.name).contains("Whey Protein"),
                "Продукт из старой склеенной записи должен найтись по имени")
    }

    // MARK: Состав рациона по категориям

    /// Диаграмма состава должна брать категории из состава приёма: у приёма
    /// из нескольких продуктов имя склеенное, и категории у него нет вовсе.
    @Test func categoryBreakdown_readsTheMealsComposition() {
        store.addCustomFood(name: "Хала", caloriesPer100g: 300, protein: 9, fat: 5, carbs: 55,
                            category: .grains)
        store.addCustomFood(name: "Молоко", caloriesPer100g: 50, protein: 3, fat: 2, carbs: 5,
                            category: .dairy)
        store.add(name: "Хала, Молоко", calories: 400, components: [
            EntryComponent(name: "Хала", calories: 300, grams: 100),
            EntryComponent(name: "Молоко", calories: 100, grams: 200),
        ])

        let parts = store.categoryBreakdown(on: Date())
        #expect(parts.first?.category == .grains)
        #expect(parts.first?.calories == 300)
        #expect(abs((parts.first?.share ?? 0) - 0.75) < 0.001)
        #expect(parts.contains { $0.category == .dairy && $0.calories == 100 })
    }

    /// Блюдо — не одна безымянная строка: «гречка с тунцом» это крупа и рыба,
    /// и раскладывается она по ингредиентам, пропорционально их калориям.
    @Test func categoryBreakdown_splitsADishIntoItsIngredients() {
        store.addCustomFood(name: "Гречка", caloriesPer100g: 100, protein: 3, fat: 1, carbs: 20,
                            category: .grains)
        store.addCustomFood(name: "Тунец", caloriesPer100g: 100, protein: 25, fat: 1, carbs: 0,
                            category: .fish)
        let dish = Dish(name: "Гречка с тунцом", ingredients: [
            DishIngredient(foodName: "Гречка", caloriesPer100g: 100, macrosPer100g: .zero, grams: 300),
            DishIngredient(foodName: "Тунец", caloriesPer100g: 100, macrosPer100g: .zero, grams: 100),
        ])
        container.mainContext.insert(dish)
        store.refresh()
        store.add(name: dish.name, calories: 400, grams: 400)

        let parts = store.categoryBreakdown(on: Date())
        #expect(parts.first { $0.category == .grains }?.calories == 300)
        #expect(parts.first { $0.category == .fish }?.calories == 100)
    }

    /// Еда, про которую состав неизвестен, не растворяется по остальным и не
    /// прячется: это дыра в данных, и она должна быть видна как дыра — но
    /// всегда последней, потому что частью рациона она не является.
    @Test func categoryBreakdown_keepsTheUnknownLastAndHonest() {
        store.addCustomFood(name: "Хала", caloriesPer100g: 300, protein: 9, fat: 5, carbs: 55,
                            category: .grains)
        store.add(name: "Хала", calories: 300, grams: 100)
        store.add(name: "Шаурма у дома", calories: 900)

        let parts = store.categoryBreakdown(on: Date())
        #expect(parts.last?.category == nil)
        #expect(parts.last?.calories == 900)
        #expect(parts.first?.category == .grains, "Известное идёт первым, даже если его меньше")
    }

    @Test func categoryBreakdown_isEmptyForADayWithoutFood() {
        #expect(store.categoryBreakdown(on: Date()).isEmpty)
    }

    // MARK: Порядок приёмов пищи

    /// Ночной перекус идёт с 23:00 до 05:00, поэтому запись в 00:30 — самая ранняя за день,
    /// хотя её приём пищи стоит последним в MealPeriod. Порядок групп должен идти
    /// от свежей записи к старой по фактическому времени.
    @Test func groupedTodayEntries_orderedByActualTime() {
        let calendar = Calendar.current
        func today(hour: Int, minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }

        store.add(name: "Ночной", calories: 100, date: today(hour: 0, minute: 30))
        store.add(name: "Завтрак", calories: 200, date: today(hour: 9, minute: 0))
        store.add(name: "Ужин", calories: 300, date: today(hour: 19, minute: 0))

        let periods = store.groupedTodayEntries.map(\.period)
        #expect(periods == [.dinner, .breakfast, .nightSnack],
                "Группы должны идти от поздней записи к ранней, а не в порядке перечисления")
    }

    @Test func groupedTodayEntries_newestFirstInsideGroup() {
        let calendar = Calendar.current
        func today(hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        }

        store.add(name: "Раньше", calories: 100, date: today(hour: 18))
        store.add(name: "Позже", calories: 200, date: today(hour: 20))

        let dinner = store.groupedTodayEntries.first { $0.period == .dinner }
        #expect(dinner?.entries.map(\.name) == ["Позже", "Раньше"])
    }

    // MARK: Add entries

    @Test func add_updatesConsumedToday() {
        store.add(name: "Яблоко", calories: 80)
        #expect(store.consumedToday == 80)
    }

    @Test func add_multiple_sumsCalories() {
        store.add(name: "A", calories: 200)
        store.add(name: "B", calories: 300)
        #expect(store.consumedToday == 500)
    }

    @Test func add_appearsInTodayEntries() {
        store.add(name: "Банан", calories: 90)
        #expect(store.todayEntries.count == 1)
        #expect(store.todayEntries.first?.name == "Банан")
    }

    @Test func add_withMacros_updatesMacrosToday() {
        store.add(name: "Курица", calories: 200, macros: Macros(protein: 30, fat: 5, carbs: 0))
        #expect(store.macrosToday.protein == 30)
        #expect(store.macrosToday.fat == 5)
    }

    @Test func add_macros_summedFromMultipleEntries() {
        store.add(name: "A", calories: 0, macros: Macros(protein: 20, fat: 5, carbs: 10))
        store.add(name: "B", calories: 0, macros: Macros(protein: 10, fat: 5, carbs: 30))
        #expect(store.macrosToday.protein == 30)
        #expect(store.macrosToday.carbs == 40)
    }

    // MARK: Delete entries

    @Test func delete_removesFromConsumedToday() {
        store.add(name: "X", calories: 150)
        let entry = store.todayEntries[0]
        store.delete(entry: entry)
        #expect(store.consumedToday == 0)
        #expect(store.todayEntries.isEmpty)
    }

    // MARK: Update entries

    @Test func updateEntry_changesCalories() {
        store.add(name: "Y", calories: 100)
        let entry = store.todayEntries[0]
        store.updateEntry(entry, name: "Y", calories: 250, macros: .zero, grams: nil, date: Date())
        #expect(store.consumedToday == 250)
    }

    @Test func updateEntry_changesName() {
        store.add(name: "Старое", calories: 100)
        let entry = store.todayEntries[0]
        store.updateEntry(entry, name: "Новое", calories: 100, macros: .zero, grams: nil, date: Date())
        #expect(store.todayEntries.first?.name == "Новое")
    }

    // MARK: Date separation

    @Test func pastEntry_notInTodayEntries() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        store.add(name: "Вчера", calories: 100, date: yesterday)
        #expect(store.todayEntries.isEmpty)
    }

    @Test func pastEntry_appearsInPastDays() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        store.add(name: "Вчера", calories: 300, date: yesterday)
        let s = store.lastSevenDays.first { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        #expect(s?.totalCalories == 300)
    }

    @Test func todayEntry_notInPastDays() {
        store.add(name: "Сегодня", calories: 100)
        let pastSummaries = store.lastSevenDays.filter { !Calendar.current.isDateInToday($0.date) }
        #expect(pastSummaries.allSatisfy { $0.totalCalories == 0 })
    }

    // MARK: Progress

    @Test func progress_zero_whenNoEntries() {
        #expect(store.progress == 0)
    }

    @Test func progress_one_whenAtGoal() {
        store.add(name: "X", calories: 2000)
        #expect(store.progress == 1.0)
    }

    @Test func progress_capsAtOne_whenOverGoal() {
        store.add(name: "X", calories: 3000)
        #expect(store.progress == 1.0)
    }

    @Test func remaining_calculatedCorrectly() {
        store.add(name: "X", calories: 500)
        #expect(store.remaining == 1500)
    }

    @Test func remaining_negative_whenOverGoal() {
        store.add(name: "X", calories: 2500)
        #expect(store.remaining == -500)
    }

    // MARK: Streak

    @Test func streak_zero_withNoEntries() {
        #expect(store.streak == 0)
    }

    @Test func streak_positive_whenTodayOnGoal() {
        store.add(name: "X", calories: 1800)
        #expect(store.streak >= 1)
    }

    @Test func loggingStreak_positive_withTodayEntry() {
        store.add(name: "X", calories: 100)
        #expect(store.loggingStreak >= 1)
    }

    @Test func loggingStreak_zero_withNoEntries() {
        #expect(store.loggingStreak == 0)
    }

    // MARK: Day summary

    @Test func summary_forToday_includesEntries() {
        store.add(name: "A", calories: 400)
        store.add(name: "B", calories: 600)
        let today = store.lastSevenDays.first { Calendar.current.isDateInToday($0.date) }
        #expect(today?.totalCalories == 1000)
    }

    @Test func summary_forYesterday_emptyWithNoData() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let s = store.lastSevenDays.first { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        #expect(s?.totalCalories == 0)
    }

    // MARK: Weight

    @Test func latestWeight_nil_initially() {
        #expect(store.latestWeight == nil)
    }

    @Test func addWeight_updatesLatestWeight() {
        store.addWeight(70.5)
        #expect(abs((store.latestWeight?.weightKg ?? 0) - 70.5) < 0.01)
    }

    @Test func addWeight_setsHasWeighedToday() {
        store.addWeight(72.0)
        #expect(store.hasWeighedToday)
    }

    @Test func deleteWeight_removesEntry() {
        store.addWeight(68.0)
        store.deleteWeight(store.weightEntries.first!)
        #expect(store.latestWeight == nil)
    }

    @Test func addWeight_multipleEntries_chronologicalOrder() {
        let d1 = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let d2 = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        store.addWeight(65.0, date: d1)
        store.addWeight(66.0, date: d2)
        store.addWeight(67.0)
        #expect(store.weightEntries.count == 3)
        #expect(store.weightEntries.first!.weightKg <= store.weightEntries.last!.weightKg)
    }

    // MARK: Custom foods

    @Test func addCustomFood_appearsInList() {
        store.addCustomFood(name: "Протеин", caloriesPer100g: 400, protein: 80, fat: 5, carbs: 5)
        #expect(store.customFoods.contains { $0.name == "Протеин" })
    }

    @Test func deleteCustomFood_removesIt() {
        store.addCustomFood(name: "Удалить", caloriesPer100g: 100, protein: 0, fat: 0, carbs: 0)
        let item = store.customFoods.first { $0.name == "Удалить" }!
        store.deleteCustomFood(item)
        #expect(!store.customFoods.contains { $0.name == "Удалить" })
    }

    @Test func customFoods_sortedAlphabetically() {
        store.addCustomFood(name: "Б", caloriesPer100g: 100, protein: 0, fat: 0, carbs: 0)
        store.addCustomFood(name: "А", caloriesPer100g: 100, protein: 0, fat: 0, carbs: 0)
        store.addCustomFood(name: "В", caloriesPer100g: 100, protein: 0, fat: 0, carbs: 0)
        let names = store.customFoods.map(\.name)
        #expect(names == names.sorted())
    }

    // MARK: Dishes

    @Test func addDish_appearsInList() {
        let ingredients = [DishIngredient(foodName: "Рис", caloriesPer100g: 350, macrosPer100g: .zero, grams: 100)]
        store.addDish(name: "Ризотто", ingredients: ingredients)
        #expect(store.dishes.contains { $0.name == "Ризотто" })
    }

    @Test func deleteDish_removesIt() {
        let ingredients = [DishIngredient(foodName: "Паста", caloriesPer100g: 300, macrosPer100g: .zero, grams: 100)]
        store.addDish(name: "Временное", ingredients: ingredients)
        let dish = store.dishes.first { $0.name == "Временное" }!
        store.deleteDish(dish)
        #expect(!store.dishes.contains { $0.name == "Временное" })
    }

}
