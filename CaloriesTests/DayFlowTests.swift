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

        #expect(slots.reduce(0) { $0 + $1.consumed } == 600,
                "Сумма по приёмам обязана сходиться со съеденным за день")
    }

    /// Ночной перекус после отбоя — та же история с другого конца суток.
    @Test func foodAfterTheLastWindowStillCounts() {
        let slots = MealSchedule.slots(input(entries: [(at(23, 40), 300)], now: at(23, 50)))
        #expect(slots.reduce(0) { $0 + $1.consumed } == 300)
    }

    /// Перебор в отдельном приёме виден: закрытое окно знает не только
    /// съеденное, но и то, сколько на него отводилось.
    @Test func aWindowKnowsHowMuchItWentOver() {
        // На завтрак при норме 3000 и пяти приёмах приходится около 700.
        let slots = MealSchedule.slots(input(count: 5, goal: 3000,
                                             entries: [(at(8), 1100)], now: at(13)))
        let breakfast = try! #require(slots.first { $0.period == .breakfast })

        #expect(breakfast.planned > 0, "План на окно известен")
        #expect(breakfast.overeaten == breakfast.consumed - breakfast.planned)
        #expect(breakfast.overeaten > 300, "Съел больше плана — это и показываем")
    }

    /// Уложился — никакого перебора, даже если день в целом перебран.
    @Test func aWindowWithinItsShareHasNoOvershoot() {
        let slots = MealSchedule.slots(input(count: 5, goal: 3000,
                                             entries: [(at(8), 400)], now: at(13)))
        let breakfast = try! #require(slots.first { $0.period == .breakfast })
        #expect(breakfast.overeaten == 0)
    }

    /// Съеденное мимо окон идёт отдельной строкой «Перекус», а не растворяется
    /// в первом приёме: «завтрак с 00:00» — это не завтрак, а свалка.
    @Test func foodOutsideTheWindowsBecomesASnack() {
        // Полвторого ночи: подъёмом это не считается (раньше четырёх утра),
        // и ни в одно окно дня не попадает.
        let slots = MealSchedule.slots(input(entries: [(at(1, 30), 250)], now: at(9)))

        let snack = try! #require(slots.last)
        #expect(snack.period == .nightSnack)
        #expect(snack.consumed == 250)
        #expect(slots.first?.period == .breakfast, "Завтрак остаётся завтраком")
        #expect(slots.first?.consumed == 0)
    }

    /// Без еды мимо расписания лишней строки не появляется.
    @Test func withoutStraysThereIsNoSnackRow() {
        let slots = MealSchedule.slots(input(entries: [(at(8), 500)], now: at(9)))
        #expect(!slots.contains { $0.period == .nightSnack })
    }

    /// Окна стоят от подъёма и до часа перед отбоем, а не от полуночи.
    @Test func theFirstWindowStartsAtWakingNotAtMidnight() {
        let slots = MealSchedule.slots(input(now: at(9)))
        let calendar = Calendar.current

        let first = try! #require(slots.first)
        #expect(calendar.component(.hour, from: first.start) >= 6,
                "Завтрак начинается с подъёма, а не в полночь")
        let last = try! #require(slots.last)
        #expect(calendar.component(.hour, from: last.end) <= 23,
                "Последнее окно закрывается к отбою")
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
    /// всё равно уходит вниз — значит тратится заметно больше, чем 3300.
    @Test func twoWeeksOfLosingOn3300_showsAboutFourThousand() throws {
        let result = try #require(AdaptiveTDEE.estimate(days(14, calories: 3300, startWeight: 80, perDay: -0.1)))
        #expect(abs(result.tdee - 4070) < 30)
        #expect(abs(result.weeklyRateKg + 0.7) < 0.05)
        #expect(result.confidence == .high)
    }

    /// Держит вес — значит, ест ровно свой расход.
    /// Шум весов — не тренд. Двести грамм в неделю это соль, вода и час
    /// взвешивания; читая их как профицит, приложение срезало норму, человек
    /// ел меньше, окно помнило прежний рост — и норма ползла вниз каждый день.
    @Test func scaleNoiseDoesNotMoveTheExpenditure() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(-13 * 86_400)
        // Вес гуляет в пределах двухсот грамм, съедено ровно 3000 каждый день.
        let wobble: [Double] = [80.0, 80.1, 79.9, 80.05, 80.1, 79.95, 80.0,
                                80.05, 80.1, 80.0, 79.95, 80.05, 80.1, 80.05]
        let days = (0..<14).map { offset in
            AdaptiveTDEE.Day(date: start.addingTimeInterval(Double(offset) * 86_400),
                             weightKg: wobble[offset], calories: 3000)
        }

        let result = try #require(AdaptiveTDEE.estimate(days))
        #expect(abs(result.tdee - 3000) < 1,
                "Вес стоит — значит тратится ровно столько, сколько съедено")
    }

    /// Настоящий тренд мёртвую зону проходит и расход двигает.
    @Test func arealTrendStillCounts() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(-13 * 86_400)
        let days = (0..<14).map { offset in
            // Полкило в неделю вниз — это уже не шум.
            AdaptiveTDEE.Day(date: start.addingTimeInterval(Double(offset) * 86_400),
                             weightKg: 80 - Double(offset) * 0.5 / 7, calories: 2500)
        }

        let result = try #require(AdaptiveTDEE.estimate(days))
        #expect(result.tdee > 3000, "Теряя полкило в неделю на 2500, тратишь заметно больше")
    }

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

// MARK: - Поправка на активность

/// Неделя у живого человека не ровная: смена на ногах и выходной на диване
/// отличаются в разы. Недельный расход об этом молчит, и без поправки один
/// день требует дефицита, которого нет, а другой прощает перебор.
struct StepAdjustmentTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func history(_ steps: [Int], endingDaysAgo: Int = 1) -> [StepDay] {
        steps.enumerated().map { index, value in
            let offset = endingDaysAgo + (steps.count - 1 - index)
            return StepDay(date: calendar.date(byAdding: .day, value: -offset, to: today)!, steps: value)
        }
    }

    /// Период привыкания: пока приложение не видело двух недель, оно не знает,
    /// что для этого человека обычный день, и не гадает.
    @Test func thereIsNoBaselineUntilTwoWeeksAreLogged() {
        #expect(StepAdjustment.baseline(from: history(Array(repeating: 9_000, count: 13))) == nil)
        #expect(StepAdjustment.baseline(from: history(Array(repeating: 9_000, count: 14))) == 9_000)
    }

    /// Сегодняшний день ещё идёт, и в среднее он бы попал огрызком.
    @Test func todayDoesNotDragTheBaselineDown() {
        var days = history(Array(repeating: 10_000, count: 20))
        days.append(StepDay(date: today, steps: 300))
        #expect(StepAdjustment.baseline(from: days) == 10_000)
    }

    /// День без шагов — это не «лежал», а «браслет остался на зарядке».
    @Test func daysWithoutStepsStayOutOfTheAverage() {
        var days = history(Array(repeating: 10_000, count: 20))
        days.append(contentsOf: history(Array(repeating: 0, count: 3), endingDaysAgo: 22))
        #expect(StepAdjustment.baseline(from: days) == 10_000)
    }

    @Test func aBusyDayRaisesTheDayAndAQuietOneLowersIt() {
        let busy = StepAdjustment.adjustment(steps: 20_000, baseline: 10_000,
                                             weightKg: 76, expenditure: 3_200)
        let quiet = StepAdjustment.adjustment(steps: 2_000, baseline: 10_000,
                                              weightKg: 76, expenditure: 3_200)
        // Десять тысяч шагов сверх обычного — около трёхсот килокалорий.
        #expect(busy > 250 && busy < 320)
        #expect(quiet < -200 && quiet > -260)
    }

    /// Утром шагов нет ни у кого. Срезать за это норму — значит требовать
    /// голодать за то, чего человек ещё не успел сделать.
    @Test func theDayInProgressNeverLosesCalories() {
        let morning = StepAdjustment.adjustment(steps: 400, baseline: 10_000, weightKg: 76,
                                                expenditure: 3_200, partialDay: true)
        #expect(morning == 0)
        let walked = StepAdjustment.adjustment(steps: 18_000, baseline: 10_000, weightKg: 76,
                                               expenditure: 3_200, partialDay: true)
        #expect(walked > 200)
    }

    /// Потолок нужен не ради шагов, а ради ошибок в них: телефон, проехавший
    /// день в машине, не должен переписать норму в полтора раза.
    @Test func anAbsurdReadingCannotRewriteTheDay() {
        let absurd = StepAdjustment.adjustment(steps: 90_000, baseline: 10_000,
                                               weightKg: 76, expenditure: 3_200)
        #expect(absurd == 3_200 * StepAdjustment.maxShareOfExpenditure)
    }

    @Test func withoutDataThereIsNoAdjustment() {
        #expect(StepAdjustment.adjustment(steps: nil, baseline: 10_000,
                                          weightKg: 76, expenditure: 3_200) == 0)
        #expect(StepAdjustment.adjustment(steps: 20_000, baseline: nil,
                                          weightKg: 76, expenditure: 3_200) == 0)
        #expect(StepAdjustment.adjustment(steps: 20_000, baseline: 10_000,
                                          weightKg: nil, expenditure: 3_200) == 0)
    }

    /// Поправки считаются от личного среднего, поэтому за неделю они гасят
    /// друг друга — иначе они бы поехали в оценку расхода и та бы поплыла.
    @Test func aWholeWeekOfAdjustmentsCancelsOut() {
        let steps = [4_000, 8_000, 10_000, 12_000, 16_000, 6_000, 17_500]
        let baseline = steps.reduce(0, +) / steps.count
        let total = steps.reduce(0.0) {
            $0 + StepAdjustment.adjustment(steps: $1, baseline: baseline,
                                           weightKg: 76, expenditure: 3_200)
        }
        #expect(abs(total) < 30)
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

    /// День поста в расчёт расхода не идёт совсем.
    ///
    /// Настоящий Йом Кипур: накануне вес 79.0 при обычных 75–76 (перед постом
    /// едят плотно и солено), к вечеру следующего дня 75.0. Три килограмма
    /// воды туда-обратно ломают наклон, а почти пустой день тянет вниз среднее
    /// съеденное — после поста оценка падала на шестьсот килокалорий.
    @MainActor
    @Test func aFastDayIsLeftOutOfTheExpenditure() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in (0..<14).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            store.add(name: "День", calories: 3300, date: date.addingTimeInterval(12 * 3600))
            store.addWeight(76, date: date.addingTimeInterval(7 * 3600))
        }
        let withoutFast = try #require(store.computeAdaptiveTDEE())

        // Ставим пост на середину окна — с выбросом веса накануне.
        let fastDay = try #require(calendar.date(byAdding: .day, value: -7, to: today))
        store.addWeight(79, date: fastDay.addingTimeInterval(7 * 3600))
        store.markFast(from: fastDay, to: fastDay.addingTimeInterval(20 * 3600), kind: .dry)

        let withFast = try #require(store.computeAdaptiveTDEE())
        #expect(abs(withFast.tdee - withoutFast.tdee) < 150,
                "Пост не должен сдвигать оценку расхода")
    }

    /// Норма ходячего дня должна быть выше нормы дня на диване — иначе
    /// суббота с залом и баскетболом выглядит как срыв, а не как работа.
    @MainActor
    @Test func aBusyDayGetsMoreThanAQuietOne() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        feedLosingWeeks()

        var history = (1...20).map {
            StepDay(date: calendar.date(byAdding: .day, value: -$0, to: today)!, steps: 10_000)
        }
        let busy = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let quiet = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        history = history.map {
            if calendar.isDate($0.date, inSameDayAs: busy) { return StepDay(date: $0.date, steps: 22_000) }
            if calendar.isDate($0.date, inSameDayAs: quiet) { return StepDay(date: $0.date, steps: 2_000) }
            return $0
        }
        StepHistory(defaults: defaults).replace(with: history)
        store.refresh()

        #expect(store.stepBaseline != nil, "Двадцати дней хватает, чтобы выйти из периода привыкания")
        let busyGoal = store.effectiveGoal(for: busy)
        let quietGoal = store.effectiveGoal(for: quiet)
        #expect(busyGoal > quietGoal + 300)
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
