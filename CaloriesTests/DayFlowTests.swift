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
    }

    /// Завтрак в восемь, обед в час, ужин в семь — у всех одинаково.
    ///
    /// Время считалось от подъёма, и у вставшего в пять завтрак приходился на
    /// без четверти шесть, а обед на десять утра. Формально стройно, на деле
    /// бесполезно: люди завтракают в восемь.
    @Test func theMainMealsStandOnTheirOwnHours() throws {
        let slots = MealSchedule.slots(input(count: 3, now: at(7)))
        #expect(try #require(slots.first).time == at(8))
        #expect(try #require(slots.first { $0.period == .lunch }).time == at(13))
        #expect(try #require(slots.first { $0.period == .dinner }).time == at(19))
    }

    /// Промежуточные — ровно посередине между соседями.
    @Test func theInBetweenMealsSitInTheMiddle() throws {
        let slots = MealSchedule.slots(input(count: 6, now: at(7)))
        #expect(try #require(slots.first { $0.period == .secondBreakfast }).time == at(10, 30))
        #expect(try #require(slots.first { $0.period == .afternoonSnack }).time == at(16))
        // Второй ужин — между ужином и последним сроком (за час до отбоя в 23:00).
        #expect(try #require(slots.first { $0.period == .secondDinner }).time == at(20, 30))
    }

    /// Отбой — единственное, что человек задаёт сам, и двигает он только
    /// второй ужин.
    @Test func onlyTheLastMealFollowsBedtime() throws {
        let early = MealSchedule.slots(.init(wake: at(7), sleep: at(21), mealCount: 6,
                                             dailyGoal: 2800, entries: [], now: at(7)))
        #expect(try #require(early.first).time == at(8))
        #expect(try #require(early.first { $0.period == .secondDinner }).time == at(19, 30))
    }

    /// Съеденный приём закрыт сразу, не дожидаясь конца окна: позавтракал —
    /// звать его завтракать ещё час бессмысленно.
    @Test func eatingClosesTheMealRightAway() throws {
        let slots = MealSchedule.slots(input(count: 3, entries: [(at(8), 700)], now: at(8, 30)))
        #expect(try #require(slots.first).state == .done)
        #expect(try #require(MealSchedule.nextSlot(slots, now: at(8, 30))).period == .lunch)
    }

    /// А несъеденный истекает по времени: завтракать в обед никто не станет.
    @Test func anUneatenMealStillExpiresWithItsWindow() throws {
        let slots = MealSchedule.slots(input(count: 3, now: at(12)))
        #expect(try #require(slots.first).state == .missed)
        #expect(try #require(MealSchedule.nextSlot(slots, now: at(12))).period == .lunch)
    }

    /// Съеденное внутри окна продолжает считаться в тот же приём — перебором,
    /// а не в никуда.
    @Test func foodInsideTheWindowKeepsAddingAsAnOvershoot() throws {
        let slots = MealSchedule.slots(input(count: 3, entries: [(at(8), 700), (at(9, 30), 400)],
                                             now: at(9, 45)))
        let breakfast = try #require(slots.first)
        #expect(breakfast.consumed == 1100)
        #expect(breakfast.overeaten > 0)
    }

    /// Остаток нормы делится между приёмами, что впереди, — по весу: на обед
    /// отводится больше, чем на полдник.
    @Test func whatIsLeftIsSplitByTheWeightOfTheMealsAhead() throws {
        let slots = MealSchedule.slots(input(count: 4, goal: 2800, entries: [(at(8), 800)],
                                             now: at(8, 30)))
        let ahead = slots.filter { $0.state == .current || $0.state == .upcoming }
        #expect(ahead.reduce(0) { $0 + $1.calories } == 2000)
        let lunch = try #require(ahead.first { $0.period == .lunch })
        let snack = try #require(ahead.first { $0.period == .afternoonSnack })
        #expect(lunch.calories > snack.calories)
    }

    /// Съеденное мимо всех окон — ночью или на рассвете — не пропадает: оно
    /// идёт отдельной строкой и считается за день наравне с остальным.
    @Test func foodOutsideEveryWindowBecomesASnack() throws {
        let slots = MealSchedule.slots(input(count: 3, entries: [(at(2), 300)], now: at(7)))
        let snack = try #require(slots.last)
        #expect(snack.period == .nightSnack)
        #expect(snack.consumed == 300)
        #expect(try #require(MealSchedule.nextSlot(slots, now: at(7))).period == .breakfast)
    }

    /// Названия приёмов — не номера: «полдник» человек понимает сразу.
    @Test func mealsAreNamedNotNumbered() {
        #expect(MealSchedule.periods(count: 3) == [.breakfast, .lunch, .dinner])
        #expect(MealSchedule.periods(count: 5).contains(.afternoonSnack))
    }

    /// Едят не поровну: завтрак, обед и ужин — основа дня.
    @Test func mainMealsAreBiggerThanSnacks() {
        #expect(MealSchedule.weight(of: .lunch) > MealSchedule.weight(of: .afternoonSnack))
    }
}

// MARK: - Повтор приёма

/// Люди едят одно и то же: та же овсянка с теми же добавками по утрам, тот же
/// обед на работе. Собирать такой приём заново из пяти позиций — пять поисков
/// и пять экранов порции вместо одного нажатия.
@MainActor
@Suite(.serialized)
struct RecentMealsTests {

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

    private func parts(_ names: [String]) -> [EntryComponent] {
        names.map { EntryComponent(name: $0, calories: 200, macros: Macros(protein: 10, fat: 5, carbs: 20), grams: 100) }
    }

    @Test func mealsOfSeveralItemsComeBackForRepeating() throws {
        store.add(name: "Овсянка, банан, мёд", calories: 600, components: parts(["Овсянка", "Банан", "Мёд"]))
        let meal = try #require(store.recentMeals().first)
        #expect(meal.components.count == 3)
    }

    /// Запись из одного продукта в этот список не идёт: для неё уже есть
    /// «Недавнее», и вторая строка о том же только засоряет экран.
    @Test func aSingleProductIsNotAMeal() {
        store.add(name: "Творог", calories: 180)
        #expect(store.recentMeals().isEmpty)
    }

    /// Один и тот же приём, съеденный пять раз за неделю, — одна строка.
    @Test func theSameMealAppearsOnce() {
        for _ in 0..<3 {
            store.add(name: "Овсянка, банан", calories: 500, components: parts(["Овсянка", "Банан"]))
        }
        #expect(store.recentMeals().count == 1)
    }

    /// Съеденное полгода назад — уже не «недавнее».
    @Test func oldMealsFallOutOfTheList() {
        let longAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        store.add(name: "Плов, салат", calories: 800, date: longAgo, components: parts(["Плов", "Салат"]))
        #expect(store.recentMeals().isEmpty)
    }

    /// Копия приёма сохраняет состав: без него приём из пяти продуктов
    /// превращается в строку без начинки, и разбор дня перестаёт видеть, из
    /// каких категорий он собран.
    @Test func copyingAMealKeepsItsComposition() throws {
        store.add(name: "Гречка, курица", calories: 700, components: parts(["Гречка", "Курица"]))
        let original = try #require(store.entries.first)
        store.add(name: original.name, calories: original.calories,
                  macros: original.macros, grams: original.grams, components: original.components)
        #expect(store.entries.count == 2)
        #expect(store.entries.allSatisfy { $0.components.count == 2 })
    }
}

// MARK: - Сон

/// Браслет пишет каждую фазу отдельной записью, а человеку нужна ночь целиком.
/// Собрать из десятка отрезков «лёг, встал, спал столько-то» — работа
/// приложения; от неё же зависит подъём, по которому строится день.
struct SleepAnalysisTests {

    private let calendar = Calendar.current

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .init(day: day, hour: hour, minute: minute), to: base)!
    }

    private func segment(_ from: Date, _ to: Date) -> SleepAnalysis.Segment {
        .init(start: from, end: to)
    }

    @Test func phasesOfOneNightBecomeOneNight() throws {
        let night = try #require(SleepAnalysis.nights(from: [
            segment(at(-1, 23, 40), at(0, 1, 20)),
            segment(at(0, 1, 25), at(0, 3, 50)),
            segment(at(0, 4, 0), at(0, 7, 10))
        ]).first)

        #expect(night.bed == at(-1, 23, 40))
        #expect(night.wake == at(0, 7, 10))
        // Пробуждения посреди ночи в часы сна не идут.
        #expect(abs(night.hours - 7.25) < 0.01)
    }

    /// Браслет отдаёт ночь крупными кусками с долгими перерывами. Ночь из
    /// шести часов не должна разваливаться на две по три с подъёмом посреди
    /// ночи — человек вставал, но ложился обратно.
    @Test func longGapsInsideANightStillMakeOneNight() throws {
        let night = try #require(SleepAnalysis.nights(from: [
            segment(at(-1, 23, 30), at(0, 1, 15)),
            segment(at(0, 3, 30), at(0, 7, 40))
        ]).first)
        #expect(night.wake == at(0, 7, 40))
        #expect(abs(night.hours - 5.9) < 0.05)
    }

    /// А вот дневной сон — отдельный: от утреннего подъёма до него проходит
    /// куда больше, чем перерыв внутри ночи.
    @Test func anAfternoonSleepIsItsOwn() {
        let nights = SleepAnalysis.nights(from: [
            segment(at(-1, 23, 0), at(0, 6, 30)),
            segment(at(0, 14, 0), at(0, 17, 30))
        ])
        #expect(nights.count == 2)
        #expect(nights.first?.wake == at(0, 6, 30))
    }

    /// Дневная дрёма не должна объявлять подъёмом четыре часа дня.
    @Test func aNapIsNotANight() {
        let nights = SleepAnalysis.nights(from: [segment(at(0, 14, 0), at(0, 15, 30))])
        #expect(nights.isEmpty)
    }

    @Test func aNightBelongsToTheDayItEndedOn() throws {
        let nights = SleepAnalysis.nights(from: [segment(at(-1, 23, 0), at(0, 7, 0))])
        #expect(SleepAnalysis.night(for: at(0, 12), in: nights) != nil)
        #expect(SleepAnalysis.night(for: at(-1, 12), in: nights) == nil)
        let night = try #require(nights.first)
        #expect(night.hours == 8)
    }

    /// Браслеты часто пишут только «в постели», без фаз. Требовать фазы —
    /// значит не видеть их сна вовсе и остаться без подъёма.
    @Test func withoutPhasesTimeInBedCountsAsSleep() throws {
        let inBed = [segment(at(-1, 23, 0), at(0, 6, 0))]
        let chosen = SleepAnalysis.segments(asleep: [], inBed: inBed)
        #expect(chosen == inBed)
        let night = try #require(SleepAnalysis.nights(from: chosen).first)
        #expect(night.wake == at(0, 6, 0))
    }

    /// А у тех, кто пишет и то и другое, «в постели» шире сна: полтора часа с
    /// телефоном перед сном не должны попасть в ночь.
    @Test func phasesWinOverTimeInBedWhenBothExist() {
        let asleep = [segment(at(0, 0, 30), at(0, 6, 0))]
        let inBed = [segment(at(-1, 23, 0), at(0, 6, 0))]
        #expect(SleepAnalysis.segments(asleep: asleep, inBed: inBed) == asleep)
    }

    /// Недосып считается от собственной привычки, а не от «восьми часов» из
    /// учебника: у каждого своя норма, и чужая цифра здесь только мешает.
    @Test func theShortfallIsMeasuredAgainstYourOwnAverage() {
        #expect(SleepAnalysis.shortfall(hours: 5, usual: 7.5) == 2.5)
        #expect(SleepAnalysis.shortfall(hours: 9, usual: 7.5) == 0)
    }
}

// MARK: - Пульс в покое

/// Готовую величину «пульс в покое» пишут только часы Apple; браслет отдаёт
/// сырой пульс, и покой приходится находить самим — по дну ночи.
struct RestingPulseTests {

    private let calendar = Calendar.current

    private func hour(_ day: Int, _ hour: Int, _ average: Double) -> RestingPulse.Hour {
        let base = calendar.startOfDay(for: Date())
        return .init(start: calendar.date(byAdding: .init(day: day, hour: hour), to: base)!,
                     average: average)
    }

    /// Дно ночи, а не среднее по ней: среднее тянут вверх пробуждения и
    /// сновидения, а нас интересует то состояние, до которого организм
    /// успевает опуститься.
    @Test func theNightsFloorIsTheRestingRate() throws {
        let byDay = RestingPulse.daily(from: [
            hour(0, 1, 56), hour(0, 2, 51), hour(0, 3, 48), hour(0, 4, 53)
        ])
        let today = calendar.startOfDay(for: Date())
        #expect(byDay[today] == 48)
    }

    /// Случайное касание датчика ночью — не измерение покоя.
    @Test func oneLonelyHourIsNotEnough() {
        let byDay = RestingPulse.daily(from: [hour(0, 3, 47)])
        #expect(byDay.isEmpty)
    }

    /// Дневной пульс в покой не идёт: человек в это время ходит.
    @Test func daytimeHoursAreIgnored() {
        let byDay = RestingPulse.daily(from: [hour(0, 13, 70), hour(0, 15, 68), hour(0, 17, 72)])
        #expect(byDay.isEmpty)
    }

    /// Одна ночь ничего не значит — можно выпить вина или лечь в жару.
    /// Говорить стоит про неделю против месяца.
    @Test func theRiseIsMeasuredWeekAgainstMonth() {
        #expect(RestingPulse.rise(recent: [53, 54, 55], usual: [48, 48, 49, 47, 48, 50, 49]) == 6)
        #expect(RestingPulse.rise(recent: [49], usual: [48, 48, 49, 47, 48, 50, 49]) == nil)
    }

    /// Один-два удара — погрешность оптического датчика, а не усталость.
    @Test func aTinyRiseIsNotWorthMentioning() {
        #expect(!RestingPulse.isNotable(rise: 2))
        #expect(RestingPulse.isNotable(rise: 4))
        #expect(!RestingPulse.isNotable(rise: nil))
    }
}

// MARK: - Поправка на активность

/// Неделя у живого человека не ровная: смена на ногах и выходной на диване
/// отличаются в разы. Недельный расход об этом молчит, и без поправки один
/// день требует дефицита, которого нет, а другой прощает перебор.
struct StepAdjustmentTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func history(_ steps: [Int], endingDaysAgo: Int = 1) -> [ActivityDay] {
        steps.enumerated().map { index, value in
            let offset = endingDaysAgo + (steps.count - 1 - index)
            return ActivityDay(date: calendar.date(byAdding: .day, value: -offset, to: today)!, steps: value)
        }
    }

    /// Период привыкания: пока приложение не видело двух недель, оно не знает,
    /// что для этого человека обычный день, и не гадает.
    @Test func thereIsNoBaselineUntilTwoWeeksAreLogged() {
        #expect(ActivityAdjustment.baseline(from: history(Array(repeating: 9_000, count: 13))) == nil)
        #expect(ActivityAdjustment.baseline(from: history(Array(repeating: 9_000, count: 14)))?.steps == 9_000)
    }

    /// Сегодняшний день ещё идёт, и в среднее он бы попал огрызком.
    @Test func todayDoesNotDragTheBaselineDown() {
        var days = history(Array(repeating: 10_000, count: 20))
        days.append(ActivityDay(date: today, steps: 300))
        #expect(ActivityAdjustment.baseline(from: days)?.steps == 10_000)
    }

    /// День без шагов — это не «лежал», а «браслет остался на зарядке».
    @Test func daysWithoutStepsStayOutOfTheAverage() {
        var days = history(Array(repeating: 10_000, count: 20))
        days.append(contentsOf: history(Array(repeating: 0, count: 3), endingDaysAgo: 22))
        #expect(ActivityAdjustment.baseline(from: days)?.steps == 10_000)
    }

    private func steps(_ count: Int) -> ActivityDay { ActivityDay(date: today, steps: count) }
    private func spent(_ kcal: Int) -> ActivityDay {
        ActivityDay(date: today, steps: 10_000, activeCalories: kcal)
    }
    private let stepsOnly = ActivityAdjustment.Baseline(steps: 10_000, activeCalories: nil)

    /// Источники считают по-разному: браслет на запястье видит то, чего
    /// телефон в кармане не замечает. Пока среднее собрано из телефонных дней,
    /// браслетный день сравнивать с ним нельзя — счёт начинается заново.
    @Test func changingTheSourceStartsTheCountOver() {
        var days = history(Array(repeating: 10_000, count: 20))
        days = days.map { var day = $0; day.stepSource = "phone"; return day }
        #expect(ActivityAdjustment.baseline(from: days)?.steps == 10_000)

        // Последний день записан браслетом — телефонные дни больше не в счёт.
        days[days.count - 1].stepSource = "band"
        #expect(ActivityAdjustment.baseline(from: days)?.steps == nil)
    }

    @Test func aBusyDayRaisesTheDayAndAQuietOneLowersIt() {
        let busy = ActivityAdjustment.adjustment(day: steps(20_000), baseline: stepsOnly,
                                                 weightKg: 76, expenditure: 3_200)
        let quiet = ActivityAdjustment.adjustment(day: steps(2_000), baseline: stepsOnly,
                                                  weightKg: 76, expenditure: 3_200)
        // Десять тысяч шагов сверх обычного — около трёхсот килокалорий.
        #expect(busy > 250 && busy < 320)
        #expect(quiet < -200 && quiet > -260)
    }

    /// Утром шагов нет ни у кого. Срезать за это норму — значит требовать
    /// голодать за то, чего человек ещё не успел сделать.
    @Test func theDayInProgressNeverLosesCalories() {
        let morning = ActivityAdjustment.adjustment(day: steps(400), baseline: stepsOnly,
                                                    weightKg: 76, expenditure: 3_200, partialDay: true)
        #expect(morning == 0)
        let walked = ActivityAdjustment.adjustment(day: steps(18_000), baseline: stepsOnly,
                                                   weightKg: 76, expenditure: 3_200, partialDay: true)
        #expect(walked > 200)
    }

    /// Браслет считает и зал, и велосипед — всё, чего шаги не видят. Если он
    /// пишет калории, считать надо по ним, а не по шагам.
    @Test func spentCaloriesWinOverStepsWhenTheBandWritesThem() {
        let baseline = ActivityAdjustment.Baseline(steps: 10_000, activeCalories: 700)
        // Шагов ровно как обычно, но потрачено на триста больше — был зал.
        let gym = ActivityAdjustment.adjustment(day: spent(1_000), baseline: baseline,
                                                weightKg: 76, expenditure: 3_200)
        #expect(gym == 300)
    }

    /// Пока браслета нет, считаем по шагам — молчать из-за отсутствия калорий
    /// было бы хуже, чем считать косвенно.
    @Test func stepsStillWorkWhenThereAreNoSpentCalories() {
        let baseline = ActivityAdjustment.Baseline(steps: 10_000, activeCalories: nil)
        let busy = ActivityAdjustment.adjustment(day: steps(20_000), baseline: baseline,
                                                 weightKg: 76, expenditure: 3_200)
        #expect(busy > 250)
    }

    /// Потолок нужен не ради шагов, а ради ошибок в них: телефон, проехавший
    /// день в машине, не должен переписать норму в полтора раза.
    @Test func anAbsurdReadingCannotRewriteTheDay() {
        let absurd = ActivityAdjustment.adjustment(day: steps(90_000), baseline: stepsOnly,
                                                   weightKg: 76, expenditure: 3_200)
        #expect(absurd == 3_200 * ActivityAdjustment.maxShareOfExpenditure)
    }

    @Test func withoutDataThereIsNoAdjustment() {
        #expect(ActivityAdjustment.adjustment(day: nil, baseline: stepsOnly,
                                              weightKg: 76, expenditure: 3_200) == 0)
        #expect(ActivityAdjustment.adjustment(day: steps(20_000), baseline: nil,
                                              weightKg: 76, expenditure: 3_200) == 0)
        // Без веса шаги в килокалории не перевести.
        #expect(ActivityAdjustment.adjustment(day: steps(20_000), baseline: stepsOnly,
                                              weightKg: nil, expenditure: 3_200) == 0)
    }

    /// Поправки считаются от личного среднего, поэтому за неделю они гасят
    /// друг друга — иначе они бы поехали в оценку расхода и та бы поплыла.
    @Test func aWholeWeekOfAdjustmentsCancelsOut() {
        let week = [4_000, 8_000, 10_000, 12_000, 16_000, 6_000, 17_500]
        let baseline = ActivityAdjustment.Baseline(steps: week.reduce(0, +) / week.count,
                                                   activeCalories: nil)
        let total = week.reduce(0.0) {
            $0 + ActivityAdjustment.adjustment(day: steps($1), baseline: baseline,
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
            ActivityDay(date: calendar.date(byAdding: .day, value: -$0, to: today)!, steps: 10_000)
        }
        let busy = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let quiet = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        history = history.map {
            if calendar.isDate($0.date, inSameDayAs: busy) { return ActivityDay(date: $0.date, steps: 22_000) }
            if calendar.isDate($0.date, inSameDayAs: quiet) { return ActivityDay(date: $0.date, steps: 2_000) }
            return $0
        }
        ActivityHistory(defaults: defaults).replace(with: history)
        store.refresh()

        #expect(store.activityBaseline?.steps != nil, "Двадцати дней хватает, чтобы выйти из периода привыкания")
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
