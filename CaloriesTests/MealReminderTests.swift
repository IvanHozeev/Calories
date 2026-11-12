import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import Calories

/// Напоминания о приёмах: как делится норма и что написано в теле.
///
/// Сама постановка в центр уведомлений отсюда не проверяется — его не
/// подменить, — а вот арифметика проверяется, и она тут не декоративная:
/// число из напоминания человек читает, не открывая приложение, и считает
/// его правдой.
@MainActor
@Suite(.serialized)
struct MealReminderTests {
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

    private func settings(count: Int) -> MealScheduleSettings {
        let settings = MealScheduleSettings(defaults: TestDefaults.make())
        settings.count = count
        return settings
    }

    /// Норма дня расходится по приёмам без потерь.
    ///
    /// Округление каждого приёма по отдельности может увести сумму от нормы;
    /// на глаз этого не видно — видно только то, что к ужину «почему-то
    /// осталось меньше». Допуск в число приёмов: больше чем по половине
    /// килокалории на приём округление дать не может.
    @Test
    func thePlanSplitsTheWholeGoal() throws {
        store.adaptedTodayGoal = 2500
        for count in MealSchedule.allowedCounts {
            let meals = MealReminders.plannedMeals(settings: settings(count: count), store: store)
            #expect(meals.count == count)
            let total = meals.reduce(0) { $0 + $1.calories }
            #expect(abs(total - 2500) <= count,
                    "При \(count) приёмах сумма \(total) вместо 2500")
        }
    }

    /// Едят не поровну: завтрак, обед и ужин крупнее перекусов.
    ///
    /// Пока норма делилась на равные части, полдник выходил на пятьсот с
    /// лишним килокалорий — то есть выглядел полноценным обедом, которого
    /// никто не ест.
    @Test
    func theMainMealsAreBiggerThanTheSnacks() {
        store.adaptedTodayGoal = 2500
        let meals = MealReminders.plannedMeals(settings: settings(count: 5), store: store)
        let periods = MealSchedule.periods(count: 5)
        #expect(meals.count == periods.count)

        for (meal, period) in zip(meals, periods) where MealSchedule.weight(of: period) < 1 {
            let main = zip(meals, periods)
                .filter { MealSchedule.weight(of: $0.1) == 1 }
                .map(\.0.calories)
            #expect(main.allSatisfy { $0 > meal.calories },
                    "Перекус \(meal.calories) не меньше основного приёма")
        }
    }

    /// Без нормы плана нет: лучше молчать, чем звать поесть ноль килокалорий.
    @Test
    func thereIsNoPlanWithoutAGoal() {
        store.adaptedTodayGoal = 0
        #expect(MealReminders.plannedMeals(settings: settings(count: 4), store: store).isEmpty)
    }

    /// У каждого приёма есть имя: «полдник», а не «приём 3 из 5».
    @Test
    func everyMealIsNamed() {
        store.adaptedTodayGoal = 2000
        let meals = MealReminders.plannedMeals(settings: settings(count: 4), store: store)
        #expect(meals.allSatisfy { !$0.title.isEmpty })
        #expect(Set(meals.map(\.title)).count == meals.count, "Имена приёмов повторяются")
    }

    /// Тело напоминания называет число, а пример — только если он есть.
    ///
    /// Текст не сравниваем: набор идёт на английской локали. Проверяем то,
    /// что от языка не зависит, — что число попало в строку и что пример
    /// появляется ровно тогда, когда его передали.
    @Test
    func theBodyNamesTheCaloriesAndTheExampleIfThereIsOne() {
        let bare = MealReminders.body(for: .init(title: "Обед", calories: 640, suggestion: nil))
        #expect(bare.contains("640"))

        let withExample = MealReminders.body(
            for: .init(title: "Обед", calories: 640, suggestion: "Греча с курицей"))
        #expect(withExample.contains("640"))
        #expect(withExample.contains("Греча с курицей"))
        #expect(withExample.count > bare.count)
    }

    /// Ответить на напоминание можно не открывая приложение: отложить и
    /// пропустить. Если действия потеряются, напоминание станет обычным
    /// «не забудь», от которого и уходили.
    @Test
    func theNotificationOffersBothAnswers() {
        let category = MealReminders.notificationCategory
        #expect(category.identifier == MealReminders.category)
        #expect(category.actions.map(\.identifier)
                == [MealReminders.snoozeAction, MealReminders.skipAction])
        #expect(MealReminders.snooze == 30 * 60)
    }

    // MARK: - «Съел как обычно»

    /// Три похожих завтрака на разные дни: столько нужно, чтобы набор стал привычным.
    private func seedUsualBreakfast() {
        let cal = Calendar.current
        for daysAgo in 1...3 {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
            let parts = [
                EntryComponent(name: "Овсянка", calories: 150, macros: Macros(protein: 5, fat: 3, carbs: 27), grams: 200),
                EntryComponent(name: "Банан", calories: 90, macros: Macros(protein: 1, fat: 0, carbs: 22), grams: 100),
            ]
            store.add(name: "Овсянка, Банан", calories: 240,
                      macros: Macros(protein: 6, fat: 3, carbs: 49), date: morning, components: parts)
        }
    }

    @Test func theUsualButtonLogsTheUsualMealOfThatWindow() {
        seedUsualBreakfast()
        let before = store.entries.count
        let logged = MealReminders.logUsualMeal(period: .breakfast, store: store)
        #expect(logged != nil)
        #expect(store.entries.count == before + 1)
        let entry = store.entries.first
        #expect(entry?.name == "Овсянка, Банан")
        #expect(entry?.calories == 240)
        #expect(entry?.composition.map(\.name) == ["Овсянка", "Банан"])
    }

    @Test func withoutAUsualMealNothingIsLogged() {
        let before = store.entries.count
        #expect(MealReminders.logUsualMeal(period: .breakfast, store: store) == nil)
        #expect(store.entries.count == before)
    }

    @Test func aBreakfastHabitIsNotLoggedForDinner() {
        seedUsualBreakfast()
        let before = store.entries.count
        #expect(MealReminders.logUsualMeal(period: .dinner, store: store) == nil)
        #expect(store.entries.count == before)
    }

    @Test func theUsualCategoryCarriesThreeButtonsAndTheOtherTwo() {
        #expect(MealReminders.notificationCategoryWithUsual.actions.map(\.identifier)
                == [MealReminders.usualAction, MealReminders.snoozeAction, MealReminders.skipAction])
        #expect(MealReminders.notificationCategory.actions.map(\.identifier)
                == [MealReminders.snoozeAction, MealReminders.skipAction])
    }

    @Test func plannedMealsKnowTheirWindowAndWhetherThereIsAHabit() {
        seedUsualBreakfast()
        let meals = MealReminders.plannedMeals(settings: settings(count: 3), store: store)
        #expect(meals.first?.period == .breakfast)
        #expect(meals.first?.hasUsualMeal == true)
        #expect(meals.last?.hasUsualMeal == false)
    }
}
