import Testing
import Foundation
import SwiftData
@testable import Calories

/// Клетчатка и витамины составного приёма.
///
/// Из жизни: клетчатка на «Сегодня» стояла прочерком, хотя человек вписывал её
/// в состав и логировал блюда с ней. Причина оказалась в том, что состав
/// искали по имени записи, а у составного приёма имя — склейка («Протеин,
/// Молоко 3%»), под которой продукта нет; вес у такой записи общий, а состав
/// задан на сто грамм каждого ингредиента. Почти все приёмы здесь составные,
/// поэтому день оставался пустым.
@MainActor
@Suite(.serialized)
struct CompositeNutrientTests {

    private let container: ModelContainer
    private let store: CalorieStore

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(),
                             groupDefaults: nil)
    }

    /// Свой продукт с клетчаткой — как его заводит человек.
    private func addOatmeal() {
        store.addCustomFood(name: "Овсянка", caloriesPer100g: 370,
                            protein: 12, fat: 7, carbs: 62,
                            micronutrients: Micronutrients([.fiber: 10]))
    }

    @Test func fiberCountsInsideACompositeMeal() throws {
        addOatmeal()
        // Приём из двух позиций: имя — склейка, вес общий.
        store.add(name: "Овсянка, Молоко",
                  calories: 420,
                  macros: Macros(protein: 18, fat: 10, carbs: 60),
                  grams: 280,
                  components: [
                    EntryComponent(name: "Овсянка", calories: 300,
                                   macros: Macros(protein: 10, fat: 6, carbs: 50), grams: 80),
                    EntryComponent(name: "Молоко", calories: 120,
                                   macros: Macros(protein: 8, fat: 4, carbs: 10), grams: 200),
                  ])

        let fiber = try #require(store.micronutrients(on: Date()).fiber)
        // 80 г овсянки — это 8 г клетчатки.
        #expect(abs(fiber - 8) < 0.01)
    }

    /// Одиночная запись считается ровно как раньше — путь на оба случая один.
    @Test func aPlainEntryStillCounts() throws {
        addOatmeal()
        store.add(name: "Овсянка", calories: 370,
                  macros: Macros(protein: 12, fat: 7, carbs: 62), grams: 100)

        let fiber = try #require(store.micronutrients(on: Date()).fiber)
        #expect(abs(fiber - 10) < 0.01)
    }

    /// Незнакомая половина приёма не превращается в ноль: считаем, что знаем,
    /// и не объявляем день изученным целиком.
    @Test func anUnknownPartIsNotZero() throws {
        addOatmeal()
        store.add(name: "Овсянка, Неизвестное",
                  calories: 500,
                  macros: Macros(protein: 12, fat: 7, carbs: 80),
                  grams: 300,
                  components: [
                    EntryComponent(name: "Овсянка", calories: 300,
                                   macros: Macros(protein: 10, fat: 6, carbs: 50), grams: 80),
                    EntryComponent(name: "Неизвестное", calories: 200,
                                   macros: Macros(protein: 2, fat: 1, carbs: 30), grams: 220),
                  ])

        let day = store.micronutrients(on: Date())
        #expect(abs((day.fiber ?? 0) - 8) < 0.01)
        #expect(day.totalCalories == 500)
    }

    /// Клетчатка показывается по тому, что известно, а не ждёт, пока состав
    /// наберётся на шесть десятых дня.
    ///
    /// Из жизни: у человека десятки своих продуктов, клетчатка проставлена у
    /// части, и витаминный порог не набирался никогда — на экране стоял
    /// прочерк при заполненном составе. Прочерк читается как «ты её не ел».
    @Test func fiberShowsWhatIsKnownEvenOnAThinDay() throws {
        addOatmeal()
        // Известная десятая часть дня и большой неизвестный остаток.
        store.add(name: "Овсянка", calories: 300,
                  macros: Macros(protein: 10, fat: 6, carbs: 50), grams: 80)
        store.add(name: "Шаурма", calories: 2700,
                  macros: Macros(protein: 80, fat: 120, carbs: 300))

        let day = store.micronutrients(on: Date())
        let fiber = try #require(day.fiber, "Известную клетчатку нельзя прятать за порогом")
        #expect(abs(fiber - 8) < 0.01)
        #expect(day.fiberIsPartial, "Про остальной день мы не знаем — это нижняя граница")
    }

    /// Когда известен весь день, оговорки не нужно.
    @Test func aFullyKnownDayIsNotPartial() {
        addOatmeal()
        store.add(name: "Овсянка", calories: 370,
                  macros: Macros(protein: 12, fat: 7, carbs: 62), grams: 100)
        #expect(!store.micronutrients(on: Date()).fiberIsPartial)
    }

    /// Запись без веса считать нечем — и это не ноль, а «неизвестно».
    @Test func anEntryWithoutGramsIsNotCounted() {
        addOatmeal()
        store.add(name: "Овсянка", calories: 370,
                  macros: Macros(protein: 12, fat: 7, carbs: 62))
        #expect(store.micronutrients(on: Date()).fiber == nil)
    }
}
