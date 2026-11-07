import Testing
import Foundation
import SwiftData
import UIKit
@testable import Calories

/// Партия — одна сваренная кастрюля.
///
/// Проверяем не столько арифметику остатка, сколько то, когда приложение
/// открывает рот. Напоминание «доешь сегодня» ценно ровно один раз; если оно
/// приходит за три дня или на пустую кастрюлю, человек перестаёт его читать,
/// и вместе с ним перестаёт читать все остальные.
@Suite struct DishBatchTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    // MARK: - Остаток

    @Test func whatIsLeftAndHowManyServings() {
        let state = DishBatch.state(cookedAt: day(-1), totalGrams: 4000,
                                    eatenGrams: 800, servingGrams: 400)
        #expect(state.remainingGrams == 3200)
        #expect(state.remainingServings == 8)
        #expect(!state.isFinished)
    }

    /// Съели больше, чем сварили, — остаток ноль, а не минус.
    @Test func eatingMoreThanCookedLeavesNothing() {
        let state = DishBatch.state(cookedAt: day(-2), totalGrams: 1000,
                                    eatenGrams: 1200, servingGrams: 300)
        #expect(state.remainingGrams == 0)
        #expect(state.isFinished)
    }

    /// Без порции остаток всё равно виден — просто в граммах.
    @Test func withoutAServingItIsJustGrams() {
        let state = DishBatch.state(cookedAt: day(-1), totalGrams: 2000,
                                    eatenGrams: 500, servingGrams: nil)
        #expect(state.remainingGrams == 1500)
        #expect(state.remainingServings == nil)
    }

    // MARK: - Прогноз

    @Test func thePaceSaysWhenItRunsOut() throws {
        // Сварено три дня назад, съедено 1200 — это 400 в день (день готовки
        // считается). Осталось 800, то есть ещё на два дня.
        let state = DishBatch.state(cookedAt: day(-3), totalGrams: 2000,
                                    eatenGrams: 1200, servingGrams: 400)
        #expect(state.dailyPace == 300)
        let runsOut = try #require(state.runsOutOn)
        let daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                               to: calendar.startOfDay(for: runsOut)).day
        #expect(daysLeft == 3)
    }

    /// Ничего не съедено — судить не по чему, и приложение молчит, а не
    /// выдумывает «хватит навсегда».
    @Test func anUntouchedBatchHasNoPace() {
        let state = DishBatch.state(cookedAt: day(0), totalGrams: 4000,
                                    eatenGrams: 0, servingGrams: 400)
        #expect(state.dailyPace == nil)
        #expect(state.runsOutOn == nil)
        #expect(DishBatch.advice(state) == nil)
    }

    // MARK: - Что говорить

    /// Последний съедобный день — единственный момент, когда стоит сказать
    /// «доешь».
    @Test func theLastGoodDaySaysEatToday() {
        let cooked = day(-DishBatch.shelfLifeDays)
        let state = DishBatch.state(cookedAt: cooked, totalGrams: 2000,
                                    eatenGrams: 1500, servingGrams: 400)
        #expect(DishBatch.advice(state) == .eatToday(servingsLeft: 1.25))
    }

    /// Срок вышел — это уже не про запас.
    @Test func pastTheShelfLifeItIsNotFoodAnyMore() {
        let cooked = day(-(DishBatch.shelfLifeDays + 1))
        let state = DishBatch.state(cookedAt: cooked, totalGrams: 2000,
                                    eatenGrams: 500, servingGrams: 400)
        #expect(DishBatch.advice(state) == .spoiled)
    }

    /// Кончается завтра — вот теперь «пора готовить». Не за три дня: такое
    /// напоминание забудется.
    @Test func runningOutTomorrowSuggestsCookingAgain() throws {
        // Сварено вчера, съедено 1000 за два дня — 500 в день, осталось 500.
        let state = DishBatch.state(cookedAt: day(-1), totalGrams: 1500,
                                    eatenGrams: 1000, servingGrams: 500)
        guard case .cookAgain = try #require(DishBatch.advice(state)) else {
            Issue.record("Ожидали предложение приготовить снова")
            return
        }
    }

    /// Запаса ещё много — молчим.
    @Test func plentyLeftMeansSilence() {
        let state = DishBatch.state(cookedAt: day(0), totalGrams: 4000,
                                    eatenGrams: 400, servingGrams: 400)
        #expect(DishBatch.advice(state) == nil)
    }

    /// Пустая партия не советует ничего: ни доесть, ни выбросить.
    @Test func anEmptyBatchIsSilent() {
        let state = DishBatch.state(cookedAt: day(-5), totalGrams: 1000,
                                    eatenGrams: 1000, servingGrams: 250)
        #expect(DishBatch.advice(state) == nil)
    }

    /// Срок важнее запаса: даже когда еды много, испорченная остаётся
    /// испорченной.
    @Test func spoilageOutranksTheForecast() {
        let state = DishBatch.state(cookedAt: day(-10), totalGrams: 4000,
                                    eatenGrams: 400, servingGrams: 400)
        #expect(DishBatch.advice(state) == .spoiled)
    }
}

// MARK: - Продукт знает свои блюда

/// Связь продукта с блюдами ищется по имени: состав блюда — снимок, в нём
/// лежат названия. Это держит историю: продукт можно удалить, а блюдо
/// останется с тем, что в него клали.
@MainActor
@Suite(.serialized)
struct FoodInDishesTests {
    /// Контейнер держим полем: локальный освобождается на выходе из init,
    /// а контекст без своего контейнера мёртв и валит весь набор трапом
    /// внутри SwiftData.
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

    private func dish(_ name: String, _ parts: [(String, Double)]) {
        store.addDish(name: name,
                      ingredients: parts.map {
                          DishIngredient(foodName: $0.0, caloriesPer100g: 100,
                                         macrosPer100g: .zero, grams: $0.1)
                      },
                      servingGrams: 0)
    }

    @Test func aFoodListsTheDishesItGoesInto() {
        dish("Салат", [("Оливковое масло", 15), ("Огурец", 200)])
        dish("Паста", [("Оливковое масло", 10), ("Спагетти", 100)])
        dish("Каша", [("Овсянка", 80)])

        let names = store.dishes(containing: "Оливковое масло").map(\.name)
        #expect(Set(names) == ["Салат", "Паста"])
        #expect(store.dishes(containing: "Овсянка").map(\.name) == ["Каша"])
    }

    @Test func theCaseOfTheNameDoesNotMatter() {
        dish("Салат", [("Оливковое масло", 15)])
        #expect(store.dishes(containing: "оливковое МАСЛО").count == 1)
    }

    @Test func aFoodInNoDishHasAnEmptyList() {
        dish("Салат", [("Оливковое масло", 15)])
        #expect(store.dishes(containing: "Гречка").isEmpty)
        #expect(store.dishes(containing: "   ").isEmpty,
                "Пустое имя не должно возвращать все блюда подряд")
    }

    /// Рядом с названием блюда стоит вес — по нему рецепт и узнают: пятнадцать
    /// граммов масла в салате и сто в заправке это разные рецепты.
    @Test func theAmountInTheDishIsKnown() {
        dish("Салат", [("Оливковое масло", 15), ("Оливковое масло", 5)])
        let salad = try! #require(store.dishes(containing: "Оливковое масло").first)
        #expect(store.grams(of: "Оливковое масло", in: salad) == 20,
                "Один продукт может лежать в составе дважды — считаем сумму")
    }
}

// MARK: - Вид рецепта

/// Салат, суп, горячее, десерт, напиток — про место за столом, а не про полку
/// в магазине. Проверяем то, что молча ломается: значок, которого нет в
/// системе, рисуется пустотой и замечается только глазами.
@MainActor
struct DishKindTests {

    @Test func everyKindHasASymbolTheSystemKnows() {
        for kind in DishKind.allCases {
            #expect(UIImage(systemName: kind.icon) != nil,
                    "У вида «\(kind.rawValue)» значок \(kind.icon), которого нет в системе")
        }
    }

    @Test func everyKindHasATitle() {
        for kind in DishKind.allCases {
            #expect(!kind.title.isEmpty)
        }
    }

    /// Старые рецепты заведены до того, как вид стали спрашивать: у них
    /// «другое», и это честный ответ, а не угадывание за человека.
    @Test func aRecipeWithoutAKindIsOther() {
        let dish = Dish(name: "Борщ")
        #expect(dish.dishKind == .other)
    }

    @Test func theKindSurvivesBeingSet() {
        let dish = Dish(name: "Борщ")
        dish.dishKind = .soup
        #expect(dish.kind == "soup")
        #expect(dish.dishKind == .soup)
    }

    /// Неизвестное значение из базы не должно ронять экран: читается как
    /// «другое». Так бывает после отката на прежнюю версию.
    @Test func anUnknownKindReadsAsOther() {
        let dish = Dish(name: "Борщ")
        dish.kind = "casserole"
        #expect(dish.dishKind == .other)
    }
}
