import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Расписание приёмов пищи

struct MealScheduleTests {

    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: Date()))!
    }

    private func input(count: Int = 4, goal: Int = 2800,
                       entries: [(Date, Int)] = [], now: Date? = nil) -> MealSchedule.Input {
        .init(wake: at(7), sleep: at(23), mealCount: count, dailyGoal: goal,
              entries: entries.map { (date: $0.0, calories: $0.1) }, now: now ?? at(7, 30))
    }

    /// Настройки расписания — одни на всё приложение.
    ///
    /// Их было два экземпляра: тумблер в настройках писал в свой, «Сегодня»
    /// читало своё, прочитанное на запуске, — и включённое деление дня не
    /// появлялось до перезапуска приложения. Значения читаются в `init`, так
    /// что два экземпляра расходятся навсегда, и ловится это только так.
    @MainActor
    @Test func theScheduleSettingsAreShared() {
        #expect(MealScheduleSettings.shared === MealScheduleSettings.shared)

        let defaults = TestDefaults.make()
        let one = MealScheduleSettings(defaults: defaults)
        let another = MealScheduleSettings(defaults: defaults)
        one.isEnabled = true
        #expect(another.isEnabled == false,
                "Второй экземпляр не узнаёт об изменении — поэтому он и должен быть один")
        #expect(MealScheduleSettings(defaults: defaults).isEnabled,
                "В хранилище значение всё же попало")
    }

    /// Окна называются как приёмы в дневнике, а не «приём 4 из 5»: иначе
    /// расписание и записи выглядят как разные вещи.
    @Test func windowsAreNamedAfterRealMeals() {
        #expect(MealSchedule.periods(count: 3) == [.breakfast, .lunch, .dinner])
        #expect(MealSchedule.periods(count: 5) ==
                [.breakfast, .secondBreakfast, .lunch, .afternoonSnack, .dinner])
        #expect(MealSchedule.periods(count: 6).last == .secondDinner)
    }

    /// Едят не поровну: завтрак, обед и ужин — основа дня, между ними
    /// перекусы. При равном делении «полдник на 550 ккал» выглядел как обед,
    /// которого никто не ест.
    @Test func mainMealsGetMoreThanSnacks() {
        let slots = MealSchedule.slots(input(count: 5, goal: 3000, now: at(6)))
        let byPeriod = Dictionary(uniqueKeysWithValues: slots.map { ($0.period, $0.calories) })

        let lunch = try! #require(byPeriod[.lunch])
        let snack = try! #require(byPeriod[.afternoonSnack])
        #expect(lunch > snack, "Обед крупнее полдника")
        #expect(Double(snack) / Double(lunch) < 0.7, "И заметно, а не на десяток калорий")
        #expect(byPeriod[.breakfast] == lunch, "Основные приёмы между собой равны")
        #expect(slots.reduce(0) { $0 + $1.calories } == 3000, "Но в сумме это всё равно дневная норма")
    }

    /// Настоящий случай: встал в пять, поел — а первый приём стоял на шесть,
    /// и еда не попадала никуда. Калории из остатка вычитались, но в
    /// расписании их не было: приём показывал «съедено 0» после завтрака.
    @Test func foodBeforeTheFirstWindowStillCounts() {
        let slots = MealSchedule.slots(input(entries: [(at(5), 600)], now: at(9)))

        #expect(slots.first?.consumed == 600, "Завтрак в пять — это завтрак, а не ничей")
        #expect(slots.reduce(0) { $0 + $1.consumed } == 600,
                "Сумма по приёмам обязана сходиться со съеденным за день")
    }

    /// Ночной перекус после отбоя — та же история с другого конца суток.
    @Test func foodAfterTheLastWindowStillCounts() {
        let slots = MealSchedule.slots(input(entries: [(at(23, 40), 300)], now: at(23, 50)))
        #expect(slots.reduce(0) { $0 + $1.consumed } == 300)
    }

    /// Времени будильника приложению взять неоткуда — в iOS такого доступа
    /// нет. Зато первая еда дня говорит о подъёме не хуже: поел в пять —
    /// значит день начался в пять, и окна раздвигаются от него.
    @Test func theDayStartsWhenYouActuallyAte() {
        let early = MealSchedule.slots(input(entries: [(at(5), 400)], now: at(9)))
        let usual = MealSchedule.slots(input(entries: [], now: at(9)))

        // Начало первого окна у обоих — начало суток (туда попадает всё, что
        // съедено до расписания), поэтому смотрим, где окно кончается: у
        // раннего подъёма приёмы разъезжаются по более длинному дню.
        #expect(early.first!.end < usual.first!.end,
                "Поел раньше — и день начался раньше")
        #expect(early.count == usual.count, "Число приёмов от этого не меняется")
    }

    /// А вот перекус в полпервого ночи подъёмом не считается: иначе одна
    /// булка ночью переставила бы весь следующий день.
    @Test func aMidnightSnackDoesNotMoveTheWholeDay() {
        let withSnack = MealSchedule.slots(input(entries: [(at(0, 30), 200)], now: at(9)))
        let plain = MealSchedule.slots(input(entries: [], now: at(9)))

        #expect(withSnack.first!.start == plain.first!.start)
        #expect(withSnack.reduce(0) { $0 + $1.consumed } == 200, "Но съеденное всё равно учтено")
    }

    /// День раскладывается от подъёма до отбоя: первый через 45 минут после
    /// подъёма, последний за час до сна, остальные — поровну между ними.
    @Test func theDayIsSplitBetweenWakingAndSleep() {
        let times = MealSchedule.times(wake: at(7), sleep: at(23), count: 4)
        #expect(times.count == 4)
        #expect(times[0] == at(7, 45))
        #expect(times[3] == at(22))
        let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }
        #expect(gaps.allSatisfy { abs($0 - gaps[0]) < 1 })
    }

    /// Норма делится поровну, а остаток от деления достаётся последнему окну:
    /// сумма по приёмам обязана сходиться с дневной нормой.
    @Test func caloriesAddUpToTheDailyTarget() {
        let slots = MealSchedule.slots(input(goal: 2801))
        #expect(slots.count == 4)
        #expect(slots.reduce(0) { $0 + $1.calories } == 2801)
    }

    /// Пропущенное окно не сгорает: его калории расходятся по оставшимся.
    @Test func aMissedWindowIsSpreadOverWhatIsLeft() {
        // Полдень: первые два окна прошли, съедено ноль.
        let slots = MealSchedule.slots(input(now: at(15)))
        let missed = slots.filter { $0.state == .missed }
        #expect(!missed.isEmpty)
        let ahead = slots.filter { $0.state == .upcoming || $0.state == .current }
        #expect(ahead.reduce(0) { $0 + $1.calories } == 2800)
        #expect(ahead.allSatisfy { $0.calories > 2800 / 4 })
    }

    /// Съеденное попадает в своё окно и уменьшает то, что осталось на день.
    @Test func whatIsEatenCountsAgainstTheDay() {
        // В одиннадцать первое окно уже закрыто: его граница — середина
        // между первым и вторым приёмом.
        let slots = MealSchedule.slots(input(entries: [(at(8), 700)], now: at(11)))
        #expect(slots[0].consumed == 700)
        #expect(slots[0].state == .done)
        let ahead = slots.filter { $0.state != .done && $0.state != .missed }
        #expect(ahead.reduce(0) { $0 + $1.calories } == 2100)
    }

    /// Переел за день — оставшимся окнам достаётся ноль, а не отрицательное.
    @Test func overeatingLeavesNothingRatherThanNegatives() {
        let slots = MealSchedule.slots(input(entries: [(at(8), 3200)], now: at(11)))
        #expect(slots.allSatisfy { $0.calories >= 0 })
        #expect(slots.filter { $0.state == .upcoming }.allSatisfy { $0.calories == 0 })
    }

    /// Ближайшее окно — то, что идёт сейчас, иначе следующее по времени.
    @Test func theNextWindowIsTheCurrentOneOrTheOneAfter() throws {
        let slots = MealSchedule.slots(input(now: at(9)))
        let next = try #require(MealSchedule.nextSlot(slots, now: at(9)))
        #expect(next.start <= at(9))
        let later = try #require(MealSchedule.nextSlot(slots.filter { $0.state == .upcoming }, now: at(9)))
        #expect(later.start > at(9))
    }

    /// Ложится за полночь — расписание не схлопывается.
    @Test func aLateBedtimeStillWorks() {
        let times = MealSchedule.times(wake: at(11), sleep: at(2), count: 3)
        #expect(times.count == 3)
        #expect(times[2] > times[0])
    }
}

// MARK: - Напоминания об окнах приёмов

/// Категория и её действия — договор между двумя далёкими файлами: одна
/// сторона регистрирует кнопки в шторке, другая ловит ответ по тем же
/// идентификаторам. Опечатка в любой из них не ломает ни сборку, ни экран —
/// кнопка просто перестаёт работать, и заметить это можно лишь на телефоне.
struct MealReminderCategoryTests {

    @MainActor
    @Test func theCategoryOffersSnoozeAndSkip() {
        let category = MealReminders.notificationCategory
        #expect(category.identifier == MealReminders.category)
        let actions = category.actions.map(\.identifier)
        #expect(actions == [MealReminders.snoozeAction, MealReminders.skipAction],
                "Отложить идёт первым: им пользуются чаще, чем пропуском")
    }

    @Test func snoozeIsHalfAnHour() {
        // Полчаса — окно приёма ещё не закрылось, и напоминание попадёт в него,
        // а не придёт к следующему.
        #expect(MealReminders.snooze == 30 * 60)
    }

    @Test func remindersOfTheScheduleAreToldApartByTheirPrefix() {
        // По префиксу снимаются старые напоминания об окнах, не трогая обычные
        // (завтрак, обед, ужин) из настроек: они живут в том же центре.
        #expect(MealReminders.prefix.hasPrefix("meal-window"))
        #expect(!MealReminders.prefix.isEmpty)
    }
}

// MARK: - Расход по факту

struct AdaptiveTDEETests {

    private func days(_ count: Int, calories: Int?, startWeight: Double, perDay: Double,
                      weighEvery: Int = 1) -> [AdaptiveTDEE.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: -(count - 1 - offset), to: today)!
            let weight = offset % weighEvery == 0 ? startWeight + perDay * Double(offset) : nil
            return AdaptiveTDEE.Day(date: date, weightKg: weight, calories: calories)
        }
    }

    /// Случай, ради которого всё и затевалось: две недели по 3300 ккал, а вес
    /// уходит по 100 г в день. Значит, тратится около 4070, а не 3300.
    @Test func twoWeeksOfLosingOn3300_showsAboutFourThousand() throws {
        let result = try #require(AdaptiveTDEE.estimate(days(14, calories: 3300, startWeight: 80, perDay: -0.1)))
        #expect(abs(result.tdee - 4070) < 30)
        #expect(abs(result.weeklyRateKg + 0.7) < 0.05)
        #expect(result.confidence == .high)
    }

    /// Держит вес — значит, ест ровно свой расход.
    @Test func steadyWeight_meansIntakeIsTheExpenditure() throws {
        let result = try #require(AdaptiveTDEE.estimate(days(14, calories: 2700, startWeight: 80, perDay: 0)))
        #expect(abs(result.tdee - 2700) < 10)
        #expect(abs(result.weeklyRateKg) < 0.01)
    }

    /// Набирает — расход ниже съеденного.
    @Test func gainingWeight_meansEatingAboveTheExpenditure() throws {
        let result = try #require(AdaptiveTDEE.estimate(days(14, calories: 3000, startWeight: 80, perDay: 0.05)))
        #expect(abs(result.tdee - (3000 - 385)) < 30)
    }

    /// Взвешивания через день — оценка та же: наклон считается по точкам,
    /// а не по числу дней.
    @Test func weighingEveryOtherDay_stillWorks() throws {
        let result = try #require(AdaptiveTDEE.estimate(days(14, calories: 3300, startWeight: 80, perDay: -0.1, weighEvery: 2)))
        #expect(abs(result.tdee - 4070) < 60)
    }

    /// Без дневника считать нечего: среднее по паре дней не говорит, сколько ест человек.
    @Test func withoutLoggedDays_thereIsNoEstimate() {
        #expect(AdaptiveTDEE.estimate(days(14, calories: nil, startWeight: 80, perDay: -0.1)) == nil)
    }

    /// Двух взвешиваний подряд мало: это наклон по воде.
    @Test func withoutSpreadOutWeighIns_thereIsNoEstimate() {
        let weighed = days(14, calories: 3000, startWeight: 80, perDay: -0.1, weighEvery: 13)
        #expect(AdaptiveTDEE.estimate(weighed) == nil)
    }

    /// Неполный дневник понижает доверие, но оценку не отменяет.
    @Test func gapsInTheDiaryLowerConfidence() throws {
        var input = days(14, calories: 3300, startWeight: 80, perDay: -0.1)
        for index in stride(from: 0, to: 6, by: 1) {
            input[index] = AdaptiveTDEE.Day(date: input[index].date, weightKg: input[index].weightKg, calories: nil)
        }
        let result = try #require(AdaptiveTDEE.estimate(input))
        #expect(result.confidence != .high)
    }

    /// Сглаживание тянет оценку к новой, но не прыгает на неё целиком.
    @Test func smoothingMovesTowardsTheNewEstimate() {
        let next = AdaptiveTDEE.smoothed(previous: 2700, estimate: 4070)
        #expect(next > 2700 && next < 4070)
        #expect(AdaptiveTDEE.smoothed(previous: nil, estimate: 4070) == 4070)
    }

    /// Тренд сглаживает шум весов и держится, когда не взвешивались.
    @Test func trendSmoothsAndHoldsThroughGaps() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let input: [AdaptiveTDEE.Day] = (0..<5).map { offset in
            let date = calendar.date(byAdding: .day, value: -(4 - offset), to: today)!
            // Один день с «плюс два килограмма» после солёного ужина.
            let weight: Double? = offset == 2 ? 82 : (offset == 3 ? nil : 80)
            return AdaptiveTDEE.Day(date: date, weightKg: weight, calories: 2500)
        }
        let trend = AdaptiveTDEE.trend(input)
        let spikeDay = calendar.date(byAdding: .day, value: -2, to: today)!
        let gapDay = calendar.date(byAdding: .day, value: -1, to: today)!
        let spike = try #require(trend[spikeDay])
        #expect(spike < 80.5, "Тренд не должен прыгать за одним взвешиванием")
        #expect(trend[gapDay] == spike, "День без взвешивания держит последний тренд")
    }
}

// MARK: - Расход по факту в сторе

@MainActor
@Suite(.serialized)
struct AdaptiveTDEEStoreTests {

    private let container: ModelContainer
    private let store: CalorieStore
    private let defaults: UserDefaults

    init() async throws {
        defaults = TestDefaults.make()
        defaults.set(true, forKey: "is_premium")
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext, defaults: defaults, groupDefaults: nil)
        store.isPremium = true
        store.updateProfile(UserProfile(weightKg: 80, heightCm: 175, age: 25, sex: .male,
                                        activityLevel: .moderate, goal: .maintenance,
                                        proteinPerKg: 1.7, fatPerKg: 0.8))
    }

    /// Две недели по 3300 ккал с уходящим весом: приложение должно понять, что
    /// расход около 4000, а не 2700 по формуле, и поднять норму.
    private func feedLosingWeeks() {
        let calendar = Calendar.current
        for offset in stride(from: 13, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            store.add(name: "День", calories: 3300, date: date)
            store.addWeight(80 - 0.1 * Double(13 - offset), date: date)
        }
    }

    @Test func expenditureIsReadFromTheDiaryAndTheScale() throws {
        feedLosingWeeks()
        let fact = try #require(store.adaptiveTDEE)
        #expect(abs(fact.tdee - 4070) < 60)
        let smoothed = try #require(store.smoothedTDEE)
        #expect(smoothed > 3000, "Сглаженная оценка должна уйти от формулы к факту")
        #expect(store.workingTDEE == smoothed)
    }

    /// Выключили — считаем по формуле, как раньше.
    @Test func turningItOffFallsBackToTheFormula() throws {
        feedLosingWeeks()
        store.usesAdaptiveTDEE = false
        let profile = try #require(store.profile)
        #expect(store.workingTDEE == profile.tdee)
    }

    /// Без данных нечего и считать: пустой дневник не должен двигать норму.
    @Test func withoutDataThereIsNoEstimate() {
        #expect(store.adaptiveTDEE == nil)
        #expect(store.workingTDEE == store.profile?.tdee)
    }

    /// План считает дневную норму от факта: та же сушка на большем расходе
    /// даёт большую норму, а не тот же дефицит от формулы.
    @Test func thePlanCountsFromTheFact() throws {
        feedLosingWeeks()
        store.startPlan(Plan(startDate: Date(), startWeightKg: 80,
                             phases: [PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: 0.5)]))
        let withFact = store.effectiveGoal(for: Date())
        store.usesAdaptiveTDEE = false
        let withFormula = store.effectiveGoal(for: Date())
        #expect(withFact > withFormula + 300)
    }
}

// MARK: - Трендовый вес

/// Дневной вес почти целиком шум: соль, углеводы, гликоген и вода дают
/// колебания больше килограмма, а натурал в дефиците теряет граммов семьдесят
/// в день. На этом шуме приложение раньше строило норму плана, цели по макросам
/// и вердикт по составу тела.
@MainActor
@Suite(.serialized)
struct WeightTrendTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func weigh(_ kg: Double, daysAgo: Int) {
        store.addWeight(kg, date: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    @Test func oneSaltyDayDoesNotMoveTheCurrentWeight() {
        weigh(77.0, daysAgo: 3)
        weigh(77.2, daysAgo: 2)
        weigh(77.1, daysAgo: 1)
        // Солёный ужин — плюс килограмм воды наутро.
        weigh(78.2, daysAgo: 0)

        let trend = store.weightKg ?? 0
        #expect(abs(trend - 77.375) < 0.01)
        #expect(trend < 78.0, "Последнее взвешивание не должно тянуть текущий вес за собой")
    }

    @Test func theWindowIsMeasuredInDaysNotInWeighIns() {
        // Человек встаёт на весы нерегулярно: «последние семь записей» у одного
        // укладываются в неделю, у другого растягиваются на месяц.
        weigh(85, daysAgo: 60)
        weigh(84, daysAgo: 45)
        weigh(83, daysAgo: 30)
        weigh(77, daysAgo: 1)

        let trend = store.weightKg ?? 0
        #expect(abs(trend - 77) < 0.01, "Старые взвешивания не должны участвовать в сегодняшнем тренде")
    }

    @Test func anOldWeighInIsStillBetterThanNothing() {
        // Окно пустое — отдаём ближайшее взвешивание: это не хуже того, что
        // было до тренда.
        weigh(80, daysAgo: 40)
        #expect(abs((store.weightKg ?? 0) - 80) < 0.01)
    }

    @Test func withoutAnyWeighInsTheProfileStillAnswers() {
        store.updateProfile(UserProfile(weightKg: 75, heightCm: 180, age: 30, sex: .male,
                                        activityLevel: .moderate, goal: .maintenance,
                                        proteinPerKg: 2))
        #expect(abs((store.weightKg ?? 0) - 75) < 0.01)
    }

    @Test func aTrendCanBeAskedForAnyDayNotJustToday() {
        // Разбор состава тела сравнивает две даты, и обе должны быть трендовыми.
        weigh(80.0, daysAgo: 31)
        weigh(80.4, daysAgo: 30)
        weigh(79.8, daysAgo: 29)
        let month = Date().addingTimeInterval(-30 * 86_400)
        #expect(abs((store.weightTrend(on: month) ?? 0) - 80.066) < 0.01)
    }
}
