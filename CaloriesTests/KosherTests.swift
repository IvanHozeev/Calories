import Testing
import Foundation
import SwiftData
@testable import Calories

/// Кашрут: статус еды, запрет по виду и ожидание между мясным и молочным.
///
/// Тесты здесь проверяют не галаху, а то, что приложение не врёт: не выдаёт
/// догадку за знание, не теряет ожидание и не называет кошерным то, о чём
/// знать не может.
/// Набор последовательный, как и все, где поднимается хранилище: параллельные
/// контейнеры SwiftData роняют процесс целиком, и падает при этом не тот тест,
/// который виноват, а все разом — включая те, где нет ни базы, ни дат.
@MainActor
@Suite(.serialized)
struct KosherTests {
    /// Контейнер держим свойством, а не местной переменной в помощнике.
    ///
    /// Помощник, который заводил контейнер и возвращал одно хранилище,
    /// освобождал его на выходе — а контекст без своего контейнера мёртв, и
    /// первое же обращение к нему валило процесс трапом внутри SwiftData.
    /// Падал при этом весь набор разом, включая тесты, где нет ни базы, ни
    /// дат, поэтому виноватого в списке не было видно.
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


    // MARK: - Статус

    @Test func categoriesThatLineUpWithKashrutDecideByThemselves() {
        #expect(KosherStatus.byCategory(.meat) == .meat)
        #expect(KosherStatus.byCategory(.dairy) == .dairy)
        #expect(KosherStatus.byCategory(.fish) == .parve)
        #expect(KosherStatus.byCategory(.produce) == .parve)
        #expect(KosherStatus.byCategory(.grains) == .parve)
        #expect(KosherStatus.byCategory(.legumes) == .parve)
        #expect(KosherStatus.byCategory(.mushrooms) == .parve)
    }

    /// Ради этого яйца и уехали в свою категорию: пока они лежали с сыром,
    /// значение по умолчанию запрещало мясо после яичницы.
    @Test func anEggIsNotDairy() {
        #expect(KosherStatus.byCategory(.eggs) == .parve)
        let egg = FoodCatalog.all.first { $0.en == "Egg" }
        #expect(egg?.kosherStatus == .parve)
        #expect(FoodCatalog.all.first { $0.en == "Boiled egg" }?.kosherStatus == .parve)
    }

    /// Там, где рецепт решает всё, честный ответ — «не знаю».
    @Test func categoriesThatDependOnTheRecipeStayUnknown() {
        #expect(KosherStatus.byCategory(.sweets) == .unknown)
        #expect(KosherStatus.byCategory(.drinks) == .unknown)
        #expect(KosherStatus.byCategory(.dishes) == .unknown)
        #expect(KosherStatus.byCategory(.fats) == .unknown)
        // Печенье бывает и на сливочном масле, и на растительном.
        #expect(FoodCatalog.all.first { $0.en == "Shortbread" }?.kosherStatus == .unknown)
    }

    @Test func theNamedListFixesWhatTheCategoryCannot() {
        func status(_ en: String) -> KosherStatus? {
            FoodCatalog.all.first { $0.en == en }?.kosherStatus
        }
        #expect(status("Ice cream") == .dairy)
        #expect(status("Latte") == .dairy)
        #expect(status("Butter") == .dairy)
        #expect(status("Water") == .parve)
        #expect(status("Chicken soup") == .meat)
        #expect(status("Salo") == .meat)
        #expect(status("Vinegret") == .parve)
    }

    // MARK: - Запрет по виду

    /// Две оси независимы: сало одновременно мясное по ожиданию и
    /// запрещённое по виду.
    @Test func whatIsForbiddenBySpeciesIsStillMeatForTheWait() {
        let salo = FoodCatalog.all.first { $0.en == "Salo" }
        #expect(salo?.kosherVerdict == .forbidden)
        #expect(salo?.kosherStatus == .meat)
    }

    @Test func forbiddenMeansSpeciesAndNothingElse() {
        func verdict(_ en: String) -> KosherVerdict? {
            FoodCatalog.all.first { $0.en == en }?.kosherVerdict
        }
        #expect(verdict("Pork") == .forbidden)
        #expect(verdict("Bacon") == .forbidden)
        #expect(verdict("Rabbit") == .forbidden)
        #expect(verdict("Shrimp") == .forbidden)
        #expect(verdict("Squid") == .forbidden)
        // Говядина кошерного вида, но был ли забой кошерным — приложение не
        // знает и утверждать не берётся.
        #expect(verdict("Beef") == .unknown)
        #expect(verdict("Salmon") == .unknown)
        // Сосиски бывают и говяжьими, и индюшачьими.
        #expect(verdict("Frankfurters") == .unknown)
        // Крабовые палочки делают из минтая, несмотря на имя.
        #expect(verdict("Crab sticks") == .unknown)
    }

    // MARK: - Приём целиком

    @Test func meatOutweighsEverythingInOneMeal() {
        #expect(KosherStatus.of([.parve, .meat, .unknown]) == .meat)
        #expect(KosherStatus.of([.parve, .dairy]) == .dairy)
        #expect(KosherStatus.of([.parve, .unknown]) == .parve)
        #expect(KosherStatus.of([.unknown]) == .unknown)
        // Смешанная тарелка ждёт как мясная.
        #expect(KosherStatus.of([.meat, .dairy]) == .meat)
    }

    @Test func mixingIsItsOwnAnswerNotAStatus() {
        #expect(KosherStatus.isMixed([.meat, .dairy]))
        #expect(!KosherStatus.isMixed([.meat, .parve]))
        #expect(!KosherStatus.isMixed([.dairy, .unknown]))
    }

    // MARK: - Ожидание

    @Test func parveStartsNoWait() {
        let at = Date()
        #expect(KosherClock.wait(after: .parve, at: at) == nil)
        #expect(KosherClock.wait(after: .unknown, at: at) == nil)
    }

    @Test func theWaitAfterMeatFollowsTheCustom() {
        let at = Date()
        for minutes in KosherCustom.afterMeatOptions {
            var custom = KosherCustom()
            custom.afterMeat = minutes
            let wait = KosherClock.wait(after: .meat, at: at, custom: custom)
            #expect(wait?.blocked == .dairy)
            #expect(wait?.until == at.addingTimeInterval(Double(minutes) * 60))
        }
    }

    /// По букве закона после молочного ждать не нужно — и ноль минут должен
    /// значить «ожидания нет», а не «ожидание длиной в ноль».
    @Test func noWaitAfterDairyMeansNoWaitAtAll() {
        var custom = KosherCustom()
        custom.afterDairy = 0
        #expect(KosherClock.wait(after: .dairy, at: Date(), custom: custom) == nil)
        custom.afterDairy = 30
        #expect(KosherClock.wait(after: .dairy, at: Date(), custom: custom)?.blocked == .meat)
    }

    /// Тот случай, ради которого ожидание после молочного вообще нужно.
    @Test func hardCheeseIsWaitedOutLikeMeat() {
        let at = Date()
        var custom = KosherCustom()
        custom.afterDairy = 30
        custom.afterMeat = 360
        let wait = KosherClock.wait(after: .dairy, at: at, hardCheese: true, custom: custom)
        #expect(wait?.until == at.addingTimeInterval(360 * 60))
        // Выключил обычай — сыр снова обычное молочное.
        custom.hardCheeseLikeMeat = false
        let plain = KosherClock.wait(after: .dairy, at: at, hardCheese: true, custom: custom)
        #expect(plain?.until == at.addingTimeInterval(30 * 60))
    }

    /// Съел курицу в час и сыр в два — молочного ждать до семи, а мясного
    /// после сыра уже можно. Обе правды нужны одновременно.
    @Test func bothWaitsCanRunAtOnce() {
        let now = Date()
        var custom = KosherCustom()
        custom.afterMeat = 360
        custom.afterDairy = 30
        let waits = KosherClock.waits(
            from: [(status: .meat, date: now.addingTimeInterval(-3600), hardCheese: false),
                   (status: .dairy, date: now.addingTimeInterval(-600), hardCheese: false)],
            now: now, custom: custom)
        #expect(waits.count == 2)
        #expect(waits.contains { $0.blocked == .dairy })
        #expect(waits.contains { $0.blocked == .meat })
    }

    @Test func theLongestWaitWins() {
        let now = Date()
        let waits = KosherClock.waits(
            from: [(status: .meat, date: now.addingTimeInterval(-5 * 3600), hardCheese: false),
                   (status: .meat, date: now.addingTimeInterval(-3600), hardCheese: false)],
            now: now)
        #expect(waits.count == 1)
        #expect(waits.first?.until == now.addingTimeInterval(-3600).addingTimeInterval(360 * 60))
    }

    @Test func aFinishedWaitDisappears() {
        let now = Date()
        let waits = KosherClock.waits(
            from: [(status: .meat, date: now.addingTimeInterval(-7 * 3600), hardCheese: false)],
            now: now)
        #expect(waits.isEmpty)
    }

    // MARK: - По дневнику


    /// Свой продукт человек называет как хочет — угадывать по имени нельзя,
    /// но категорию он выбрал сам, и ей можно верить.
    @Test func ownFoodTakesItsStatusFromTheCategoryUntilItIsSet() throws {
        store.addCustomFood(name: "אבקת חלבון", caloriesPer100g: 380,
                            protein: 75, fat: 5, carbs: 10, category: .dairy)
        let food = try #require(store.customFoods.first)
        #expect(food.kosherStatus == .dairy)
        food.kosherStatus = .parve
        #expect(food.kosherStatus == .parve)
    }

    @Test func aDishIsReadThroughItsIngredients() throws {
        store.addCustomFood(name: "Курица моя", caloriesPer100g: 165,
                            protein: 31, fat: 3.6, carbs: 0, category: .meat)
        store.addCustomFood(name: "Сливки мои", caloriesPer100g: 200,
                            protein: 3, fat: 20, carbs: 4, category: .dairy)
        store.addDish(name: "Курица в сливках", ingredients: [
            DishIngredient(foodName: "Курица моя", caloriesPer100g: 165,
                           macrosPer100g: Macros(protein: 31, fat: 3.6, carbs: 0), grams: 200),
            DishIngredient(foodName: "Сливки мои", caloriesPer100g: 200,
                           macrosPer100g: Macros(protein: 3, fat: 20, carbs: 4), grams: 100),
        ])

        let parts = store.kosherParts(named: "Курица в сливках").map(\.status)
        #expect(KosherStatus.isMixed(parts))
        #expect(KosherStatus.of(parts) == .meat)
    }

    @Test func theDiaryKnowsWhatIsStillBeingWaitedOut() throws {
        store.addCustomFood(name: "Курица моя", caloriesPer100g: 165,
                            protein: 31, fat: 3.6, carbs: 0, category: .meat)
        let now = Date()
        store.add(name: "Курица моя", calories: 300,
                  macros: Macros(protein: 56, fat: 7, carbs: 0),
                  grams: 180, date: now.addingTimeInterval(-3600))

        let waits = store.kosherWaits(now: now)
        #expect(waits.count == 1)
        #expect(waits.first?.blocked == .dairy)
        #expect(waits.first?.eaten == .meat)
    }

    /// Неизвестное не запускает отсчёт: иначе любой продукт из глобального
    /// поиска молча запрещал бы половину еды.
    @Test func unknownFoodStartsNothing() throws {
        let now = Date()
        store.add(name: "Что-то с полки", calories: 300,
                  macros: Macros(protein: 10, fat: 10, carbs: 30),
                  grams: 100, date: now.addingTimeInterval(-600))
        #expect(store.kosherWaits(now: now).isEmpty)
    }
}

/// Настройки кашрута: что приложение помнит и чего не выдумывает.
@MainActor
@Suite(.serialized)
struct KosherSettingsTests {

    @Test func theDefaultCustomIsTheCommonOne() {
        let settings = KosherSettings(defaults: TestDefaults.make())
        #expect(!settings.isEnabled)
        #expect(settings.afterMeat == 360)
        // По букве закона после молочного ждать не нужно — ноль и есть
        // значение, а не «не задано».
        #expect(settings.afterDairy == 0)
        #expect(settings.hardCheeseLikeMeat)
        #expect(settings.warnsMixing)
    }

    @Test func aChosenCustomSurvivesARestart() {
        let defaults = TestDefaults.make()
        let first = KosherSettings(defaults: defaults)
        first.isEnabled = true
        first.afterMeat = 330
        first.afterDairy = 30
        first.hardCheeseLikeMeat = false

        let second = KosherSettings(defaults: defaults)
        #expect(second.isEnabled)
        #expect(second.afterMeat == 330)
        #expect(second.afterDairy == 30)
        #expect(!second.hardCheeseLikeMeat)
    }

    /// Чужое число в настройках — не повод считать по нему.
    @Test func anUnknownCustomFallsBackToTheCommonOne() {
        let defaults = TestDefaults.make()
        defaults.set(275, forKey: KosherSettings.afterMeatKey)
        defaults.set(17, forKey: KosherSettings.afterDairyKey)
        let settings = KosherSettings(defaults: defaults)
        #expect(settings.afterMeat == 360)
        #expect(settings.afterDairy == 0)
    }

    /// Обычай человек знает в часах — так он и подписан.
    @Test func theCustomIsNamedInHoursAndMinutes() {
        #expect(KosherWaitText.title(minutes: 0) == String(localized: "Не ждать"))
        #expect(KosherWaitText.title(minutes: 360).contains("6"))
        #expect(KosherWaitText.title(minutes: 330).contains("5"))
        #expect(KosherWaitText.title(minutes: 330).contains("30"))
        #expect(KosherWaitText.title(minutes: 30).contains("30"))
    }

    @Test func settingsHandTheCounterItsCustom() {
        let settings = KosherSettings(defaults: TestDefaults.make())
        settings.afterMeat = 180
        settings.afterDairy = 60
        let at = Date()
        let wait = KosherClock.wait(after: .meat, at: at, custom: settings.custom)
        #expect(wait?.until == at.addingTimeInterval(180 * 60))
    }
}
