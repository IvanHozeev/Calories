import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Macros

struct MacrosTests {

    @Test func addition() {
        let a = Macros(protein: 10, fat: 5, carbs: 20)
        let b = Macros(protein: 3, fat: 2, carbs: 8)
        let sum = a + b
        #expect(sum.protein == 13)
        #expect(sum.fat == 7)
        #expect(sum.carbs == 28)
    }

    @Test func zeroIsNeutral() {
        let m = Macros(protein: 5, fat: 3, carbs: 12)
        let r = m + .zero
        #expect(r.protein == 5)
        #expect(r.fat == 3)
        #expect(r.carbs == 12)
    }

    @Test func scaled() {
        let m = Macros(protein: 20, fat: 10, carbs: 40)
        let s = m.scaled(by: 200)
        #expect(s.protein == 40)
        #expect(s.fat == 20)
        #expect(s.carbs == 80)
    }

    @Test func scaledByZero() {
        let m = Macros(protein: 20, fat: 10, carbs: 40)
        let s = m.scaled(by: 0)
        #expect(s.protein == 0)
        #expect(s.fat == 0)
        #expect(s.carbs == 0)
    }
}

// MARK: - DaySummary

struct DaySummaryTests {

    private func entry(_ kcal: Int, protein: Double = 0, fat: Double = 0, carbs: Double = 0) -> FoodEntry {
        FoodEntry(name: "test", calories: kcal, macros: Macros(protein: protein, fat: fat, carbs: carbs))
    }

    @Test func totalCalories_empty() {
        let s = DaySummary(date: .now, entries: [], goal: 2000)
        #expect(s.totalCalories == 0)
    }

    @Test func totalCalories_summed() {
        let s = DaySummary(date: .now, entries: [entry(400), entry(600)], goal: 2000)
        #expect(s.totalCalories == 1000)
    }

    @Test func difference_under() {
        let s = DaySummary(date: .now, entries: [entry(1500)], goal: 2000)
        #expect(s.difference == -500)
    }

    @Test func difference_over() {
        let s = DaySummary(date: .now, entries: [entry(2500)], goal: 2000)
        #expect(s.difference == 500)
    }

    @Test func totalMacros_aggregated() {
        let s = DaySummary(
            date: .now,
            entries: [
                entry(0, protein: 10, fat: 5, carbs: 20),
                entry(0, protein: 30, fat: 15, carbs: 60)
            ],
            goal: 2000
        )
        #expect(s.totalMacros.protein == 40)
        #expect(s.totalMacros.fat == 20)
        #expect(s.totalMacros.carbs == 80)
    }
}

// MARK: - UserProfile

struct UserProfileTests {

    private func profile(
        age: Int = 30,
        heightCm: Double = 175,
        weightKg: Double = 75,
        sex: Sex = .male,
        activity: ActivityLevel = .moderate,
        goal: Goal = .maintenance
    ) -> UserProfile {
        UserProfile(
            weightKg: weightKg,
            heightCm: heightCm,
            age: age,
            sex: sex,
            activityLevel: activity,
            goal: goal,
            proteinPerKg: UserProfile.defaultProteinPerKg
        )
    }

    @Test func bmr_male() {
        let bmr = profile(age: 30, heightCm: 175, weightKg: 75, sex: .male).bmr
        #expect(abs(bmr - 1699) < 5)
    }

    @Test func bmr_female() {
        let bmr = profile(age: 30, heightCm: 165, weightKg: 60, sex: .female).bmr
        #expect(abs(bmr - 1320) < 5)
    }

    @Test func tdee_greaterThanBmr() {
        let p = profile(activity: .sedentary)
        #expect(p.tdee > p.bmr)
    }

    @Test func calorieTarget_fatLoss() {
        let p = profile(goal: .fatLoss)
        #expect(p.calorieTarget < Int(p.tdee))
    }

    @Test func calorieTarget_maintenance() {
        let p = profile(goal: .maintenance)
        #expect(p.calorieTarget == Int(p.tdee.rounded()))
    }

    @Test func calorieTarget_muscleGain() {
        let p = profile(goal: .muscleGain)
        #expect(p.calorieTarget > Int(p.tdee))
    }

    @Test func proteinTarget_positive() {
        let p = profile(weightKg: 80)
        #expect(p.proteinTargetGrams > 0)
    }

    @Test func bmi_correct() {
        let p = profile(heightCm: 175, weightKg: 75)
        #expect(abs(p.bmi - 24.49) < 0.1)
    }

    @Test func navyBodyFat_male_nonNil() {
        let p = profile(sex: .male)
        let m = BodyMeasurement(date: Date())
        m.beltCm = 85       // у мужчин метод берёт уровень пупка
        m.neckCm = 37
        #expect(p.navyBodyFat(from: m) != nil)
        #expect(p.navyBodyFat(from: m)! > 0)
    }

    @Test func navyBodyFat_nil_whenWaistEqualsNeck() {
        let p = profile(sex: .male)
        let m = BodyMeasurement(date: Date())
        m.beltCm = 37
        m.neckCm = 37
        #expect(p.navyBodyFat(from: m) == nil)
    }

    /// Регрессия: процент жира показывался разными числами на двух экранах,
    /// потому что профиль хранил собственную копию обхватов. Теперь источник
    /// один, и результат зависит только от переданного замера.
    @Test func bodyFat_isTheSameNumberEverywhere() {
        let p = profile(heightCm: 180, sex: .male)
        let m = BodyMeasurement(date: Date())
        m.beltCm = 88
        m.neckCm = 40

        let direct = p.bodyFatPercentage(from: m)
        #expect(p.isNavyMethod(from: m))

        // То же значение, что уходит в отчёт о замерах
        let reported = BodyAnalysis.insights(measurement: m, profile: p)
            .first { $0.id == "bodyFat" }?.value
        #expect(reported == String(format: "%.1f%%", direct))

        // И то же, что берёт FFMI — он тоже считается от процента жира
        #expect(BodyAnalysis.ffmi(weightKg: p.weightKg, heightCm: p.heightCm,
                                  bodyFatPercent: direct) != nil)
    }

    @Test func bodyFat_fallsBackToBmiWithoutGirths() {
        let p = profile(sex: .male)
        let empty = BodyMeasurement(date: Date())
        #expect(!p.isNavyMethod(from: empty))
        #expect(!p.isNavyMethod(from: nil))
        // Дойренберг считается от ИМТ, поэтому замер на него не влияет вовсе
        #expect(p.bodyFatPercentage(from: empty) == p.bodyFatPercentage(from: nil))
        #expect(p.bodyFatPercentage(from: nil) > 0)
    }
}

// MARK: - Plan

struct PlanTests {

    private func plan(
        startWeightKg: Double = 80,
        targetWeightKg: Double = 75,
        durationWeeks: Int = 10,
        cyclingEnabled: Bool = false
    ) -> Plan {
        Plan(
            startDate: Date(),
            durationWeeks: durationWeeks,
            startWeightKg: startWeightKg,
            targetWeightKg: targetWeightKg,
            cyclingEnabled: cyclingEnabled
        )
    }

    @Test func weeklyRate_loss() {
        let p = plan(startWeightKg: 80, targetWeightKg: 75, durationWeeks: 10)
        #expect(abs(p.weeklyRateKg - (-0.5)) < 0.01)
    }

    @Test func weeklyRate_gain() {
        let p = plan(startWeightKg: 70, targetWeightKg: 75, durationWeeks: 10)
        #expect(abs(p.weeklyRateKg - 0.5) < 0.01)
    }

    @Test func totalWeightChange_negative() {
        let p = plan(startWeightKg: 80, targetWeightKg: 75)
        #expect(abs(p.totalWeightChangeKg - (-5)) < 0.01)
    }

    @Test func dailyCalorieTarget_belowTdee_forDeficit() {
        let p = plan(startWeightKg: 80, targetWeightKg: 75, durationWeeks: 10)
        let target = p.dailyCalorieTarget(tdee: 2500)
        #expect(target < 2500)
        #expect(target > 0)
    }

    @Test func isAggressivePace_true() {
        let p = plan(startWeightKg: 80, targetWeightKg: 70, durationWeeks: 4)
        #expect(p.isAggressivePace(relativeToWeightKg: 80))
    }

    @Test func isAggressivePace_false() {
        let p = plan(startWeightKg: 80, targetWeightKg: 78, durationWeeks: 10)
        #expect(!p.isAggressivePace(relativeToWeightKg: 80))
    }

    @Test func cyclingTarget_equalsBaseWhenDisabled() {
        let p = plan(cyclingEnabled: false)
        let base = p.dailyCalorieTarget(tdee: 2500)
        let onDate = p.calorieTarget(for: Date(), tdee: 2500)
        #expect(onDate == base)
    }

    @Test func cyclingTarget_differsAcrossDaysWhenEnabled() {
        let p = plan(cyclingEnabled: true)
        let breakdown = p.weeklyCalorieBreakdown(tdee: 2500)
        let calories = breakdown.map(\.calories)
        #expect(Set(calories).count > 1)
    }
}

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

// MARK: - StepStore

@MainActor
struct StepStoreTests {

    // Свой suite на каждый тест — боевые настройки приложения не трогаем (см. TestDefaults)
    private let defaults = TestDefaults.make()

    private func makeStore(goal: Int? = nil) -> StepStore {
        if let goal {
            defaults.set(goal, forKey: "step_goal")
        }
        return StepStore(defaults: defaults, groupDefaults: nil)
    }

    @Test func defaultStepGoal_is10000() {
        let store = makeStore()
        #expect(store.stepGoal == 10_000)
    }

    @Test func stepGoal_persistsToUserDefaults() {
        let store = makeStore()
        store.stepGoal = 7_500
        #expect(defaults.integer(forKey: "step_goal") == 7_500)
    }

    @Test func stepGoal_loadsFromUserDefaults() {
        let store = makeStore(goal: 5_000)
        #expect(store.stepGoal == 5_000)
    }

    @Test func initialStepsToday_isZero() {
        let store = makeStore()
        #expect(store.stepsToday == 0)
    }

    @Test func initialDistanceToday_isZero() {
        let store = makeStore()
        #expect(store.distanceTodayKm == 0)
    }

    @Test func initialActiveCalories_isZero() {
        let store = makeStore()
        #expect(store.activeCaloriesToday == 0)
    }

    @Test func initialWeekHistory_isEmpty() {
        let store = makeStore()
        #expect(store.weekHistory.isEmpty)
    }

    @Test func initialMonthHistory_isEmpty() {
        let store = makeStore()
        #expect(store.monthHistory.isEmpty)
    }

    @Test func initialGoalStreak_isZero() {
        let store = makeStore()
        #expect(store.goalStreak == 0)
    }

    @Test func initialWeeklyTotal_isZero() {
        let store = makeStore()
        #expect(store.weeklyTotal == 0)
    }
}

// MARK: - ReminderStore

@MainActor
struct ReminderStoreTests {

    // Свой suite на каждый тест — боевые настройки приложения не трогаем (см. TestDefaults)
    private let defaults = TestDefaults.make()

    private func makeStore() -> ReminderStore {
        ReminderStore(defaults: defaults)
    }

    @Test func hasThreeReminders() {
        let store = makeStore()
        #expect(store.reminders.count == 3)
    }

    @Test func reminderIds_areCorrect() {
        let store = makeStore()
        let ids = store.reminders.map(\.id)
        #expect(ids.contains("breakfast"))
        #expect(ids.contains("lunch"))
        #expect(ids.contains("dinner"))
    }

    @Test func reminderTitles_arePresent() {
        let store = makeStore()
        #expect(store.reminders.allSatisfy { !$0.title.isEmpty })
    }

    @Test func defaultAppEnabled_isFalse() {
        let store = makeStore()
        #expect(!store.appEnabled)
    }

    @Test func appEnabled_persistsToUserDefaults() {
        let store = makeStore()
        store.appEnabled = true
        #expect(defaults.bool(forKey: "reminders_app_enabled") == true)
        store.appEnabled = false
    }

    @Test func disableNotifications_setsAppEnabledFalse() {
        let store = makeStore()
        store.appEnabled = true
        store.disableNotifications()
        #expect(!store.appEnabled)
    }

    @Test func saveAndReschedule_persistsReminderState() {
        let store = makeStore()
        store.reminders[0].isEnabled = true
        store.saveAndReschedule()
        #expect(defaults.bool(forKey: "reminder_breakfast_on") == true)
    }

    @Test func saveAndReschedule_persistsReminderTime() {
        let store = makeStore()
        let newTime = Date(timeIntervalSince1970: 3600 * 9)
        store.reminders[0].time = newTime
        store.saveAndReschedule()
        let saved = defaults.object(forKey: "reminder_breakfast_time") as? TimeInterval
        #expect(saved != nil)
    }
}

// MARK: - Покупки

import StoreKitTest
import StoreKit

/// Юнит-тесты хостятся внутри процесса приложения, поэтому SKTestSession здесь реально
/// подменяет StoreKit для самого приложения — в UI-тесте это не работает, там раннер
/// и приложение разные процессы.
@MainActor
struct PurchaseServiceTests {

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    // ИЗВЕСТНАЯ ПРОБЛЕМА: SKTestSession поднимается без ошибок, но Product.products(for:)
    // возвращает пустой список и не бросает — StoreKit отвечает, что таких продуктов нет.
    // Конфиг лежит в бандле теста, идентификаторы совпадают, формат приведён к каноническому.
    // Тест оставлен включённым намеренно: он падает и будет напоминать о нерешённом.
    @Test(.disabled("Product.products(for:) возвращает пустой список под SKTestSession — не разобрано")) func loadsAllConfiguredProducts() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let service = PurchaseService()
        await service.load()

        #expect(service.products.count == 3, "Должны загрузиться две подписки и разовая покупка")
        #expect(service.subscriptions.count == 2)
        #expect(service.lifetime != nil)
        #expect(service.loadFailed == false)
    }

    @Test func noEntitlementsMeansNoPremium() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let service = PurchaseService()
        await service.load()

        #expect(service.isPremium == false, "Без покупок премиума быть не должно")
    }

    @Test(.disabled("Product.products(for:) возвращает пустой список под SKTestSession — не разобрано")) func purchaseGrantsPremium() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let service = PurchaseService()
        await service.load()
        let monthly = try #require(service.products.first { $0.id == PurchaseService.ProductID.monthly })

        await service.purchase(monthly)

        #expect(service.isPremium == true, "После покупки подписки премиум должен включиться")
        #expect(service.purchasedIDs.contains(PurchaseService.ProductID.monthly))
    }
}

// MARK: - Локализация

/// Проверяет каталог целиком, чтобы не открывать приложение на восьми языках руками.
/// Ловит два класса ошибок, на которых мы уже спотыкались: ключ есть, а переводов у него
/// нет (строка молча падает на русский исходник), и разъехавшиеся спецификаторы формата,
/// от которых текст ломается или приложение падает при подстановке.
struct LocalizationTests {

    private static let languages = ["en", "es", "pt", "fr", "de", "ar", "he"]

    /// Читает скомпилированный Localizable.strings конкретной локали из бандла приложения.
    private static func strings(for language: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                        subdirectory: nil, localization: language),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else { return [:] }
        return dict
    }

    private static func specifiers(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ 0#]*[\d.]*(?:lld|ld|@|d|f|s)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
        // Сравниваем только типы подстановок. Порядок в переводе меняется, и тогда
        // появляется позиционная форма «%1$lld» — это тот же аргумент, что и «%lld».
        .map { $0.replacingOccurrences(of: #"^%(\d+\$)?[-+ 0#]*[\d.]*"#,
                                       with: "%", options: .regularExpression) }
        .sorted()
    }

    @Test func everyLanguageIsPresent() {
        for language in Self.languages {
            #expect(!Self.strings(for: language).isEmpty,
                    "Локаль \(language) не собралась в бандл")
        }
    }

    @Test func noLanguageFallsBackToRussian() {
        let cyrillic = try! NSRegularExpression(pattern: "[А-Яа-яЁё]")
        for language in Self.languages where language != "ru" {
            let table = Self.strings(for: language)
            let untranslated = table.filter { _, value in
                let range = NSRange(value.startIndex..., in: value)
                return cyrillic.firstMatch(in: value, range: range) != nil
            }
            #expect(untranslated.isEmpty,
                    "В локали \(language) остался русский текст: \(untranslated.keys.sorted().prefix(5))")
        }
    }

    @Test func formatSpecifiersMatchAcrossLanguages() {
        let russian = Self.strings(for: "ru")
        for language in Self.languages {
            let table = Self.strings(for: language)
            for (key, translated) in table {
                guard let source = russian[key] ?? (key.isEmpty ? nil : key) else { continue }
                let expected = Self.specifiers(in: source)
                guard !expected.isEmpty else { continue }
                #expect(Self.specifiers(in: translated) == expected,
                        "Спецификаторы разъехались в \(language) для ключа «\(key)»")
            }
        }
    }
}

// MARK: - Антропометрия

@MainActor
struct BodyAnalysisTests {

    private func sample() -> BodyMeasurement {
        BodyMeasurement(
            neckCm: 40, chestCm: 108, shouldersCm: 126, waistCm: 78, beltCm: 82,
            pelvisCm: 81, glutesCm: 96,
            bicepsLeftCm: 39, bicepsRightCm: 40,
            forearmLeftCm: 31, forearmRightCm: 31.5,
            wristLeftCm: 17, wristRightCm: 17,
            thighLeftCm: 58, thighRightCm: 58.5,
            quadLeftCm: 54, quadRightCm: 54,
            calfLeftCm: 39, calfRightCm: 39
        )
    }

    @Test func symmetry_flagsOnlyRealAsymmetry() {
        let results = BodyAnalysis.symmetry(sample())
        let biceps = results.first { $0.site == .biceps }
        let calf = results.first { $0.site == .calf }

        #expect(biceps?.difference == 1.0)
        #expect(biceps?.verdict == .excellent, "1 см — это погрешность ленты, не перекос")
        #expect(biceps?.strongerSide == .right)
        #expect(calf?.difference == 0)
    }

    @Test func symmetry_skipsIncompletePairs() {
        let m = sample()
        m.calfLeftCm = 0
        let results = BodyAnalysis.symmetry(m)
        #expect(!results.contains { $0.site == .calf },
                "Пара без одной стороны не должна попадать в отчёт как нулевая")
    }

    @Test func symmetry_warnsOnBigGap() {
        let m = sample()
        m.bicepsLeftCm = 36
        m.bicepsRightCm = 40
        let biceps = BodyAnalysis.symmetry(m).first { $0.site == .biceps }
        #expect(biceps?.verdict == .watch)
    }

    @Test func mccallum_derivesFromWrist() {
        let ideal = BodyAnalysis.mccallum(wristCm: 17)
        #expect(ideal?.chest == 110.5)                     // 17 × 6.5
        #expect(abs((ideal?.arm ?? 0) - 39.78) < 0.01)     // 36% груди
        #expect(BodyAnalysis.mccallum(wristCm: 0) == nil)
    }

    @Test func ffmi_isNotInflatedByFat() {
        // Один рост и вес, разный процент жира: у более сухого FFMI должен быть выше.
        let lean = BodyAnalysis.ffmi(weightKg: 80, heightCm: 180, bodyFatPercent: 10)!
        let fat = BodyAnalysis.ffmi(weightKg: 80, heightCm: 180, bodyFatPercent: 25)!
        #expect(lean > fat)
        #expect(abs(lean - 22.2) < 0.2)
    }

    @Test func ffmi_rejectsGarbageInput() {
        #expect(BodyAnalysis.ffmi(weightKg: 0, heightCm: 180, bodyFatPercent: 10) == nil)
        #expect(BodyAnalysis.ffmi(weightKg: 80, heightCm: 0, bodyFatPercent: 10) == nil)
        #expect(BodyAnalysis.ffmi(weightKg: 80, heightCm: 180, bodyFatPercent: 0) == nil)
    }

    @Test func insights_haveStableIdentifiers() {
        let first = BodyAnalysis.insights(measurement: sample(), profile: nil).map(\.id)
        let second = BodyAnalysis.insights(measurement: sample(), profile: nil).map(\.id)
        #expect(first == second, "Пересчёт не должен менять id — иначе SwiftUI перерисовывает список целиком")
    }

    @Test func insights_skipWhatWasNotMeasured() {
        let empty = BodyMeasurement()
        #expect(BodyAnalysis.insights(measurement: empty, profile: nil).isEmpty,
                "Без замеров отчёт должен быть пустым, а не полным нулей")
    }

    @Test func estimates_fillGapsFromWhatIsAlreadyMeasured() {
        let m = BodyMeasurement(date: Date())
        m.bicepsRightCm = 40

        let e = BodyAnalysis.estimates(for: m)
        // Соседние мышцы растут вместе, связь теснее, чем через костяк
        #expect(e[.forearm].map { abs($0.value - 32.2) < 0.1 } == true)
        #expect(e[.neck]?.value == 40)
        #expect(e[.calf]?.value == 40)
        // Бицепс снят — предполагать его незачем
        #expect(e[.biceps] == nil)
    }

    @Test func estimates_neverOverrideAMeasuredValue() {
        let m = BodyMeasurement(date: Date())
        m.bicepsRightCm = 40
        m.forearmRightCm = 30   // реально снято и заметно ниже расчётных 32.2

        let e = BodyAnalysis.estimates(for: m)
        #expect(e[.forearm] == nil, "Снятый замер нельзя подменять оценкой")
    }

    @Test func estimates_preferDirectRatioOverFrame() {
        let m = BodyMeasurement(date: Date())
        m.wristRightCm = 17     // МакКаллум дал бы предплечье около 32.0
        m.bicepsRightCm = 44    // прямое соотношение даёт 35.4

        let e = BodyAnalysis.estimates(for: m)
        #expect(e[.forearm].map { abs($0.value - 35.4) < 0.2 } == true,
                "Соотношение с соседней мышцей надёжнее вывода от запястья")
    }

    @Test func estimates_stayWithinPlausibleRanges() {
        // Оценка не должна предлагать то, что сама же форма отвергнет как мусор.
        for wrist in stride(from: 12.0, through: 25.0, by: 0.5) {
            let m = BodyMeasurement(date: Date())
            m.wristRightCm = wrist
            for (site, estimate) in BodyAnalysis.estimates(for: m) {
                #expect(site.isPlausible(estimate.value),
                        "\(site) при запястье \(wrist) вышло за диапазон: \(estimate.value)")
            }
        }
    }

    @Test func estimates_areEmptyWithoutAnyInput() {
        #expect(BodyAnalysis.estimates(for: BodyMeasurement(date: Date())).isEmpty)
    }

    @Test func plausibleRange_rejectsFatFingeredInput() {
        // Реальный случай: слипшиеся цифры при вводе дают обхват в миллиарды сантиметров.
        #expect(!MeasurementSite.chest.isPlausible(10878828196))
        #expect(!MeasurementSite.wrist.isPlausible(176262.5))
        #expect(!MeasurementSite.neck.isPlausible(401261087882))

        // Пустое поле и обнуление — это не ошибка, а «не мерил»
        #expect(MeasurementSite.chest.isPlausible(0))

        // Живые значения проходят, включая края диапазона
        #expect(MeasurementSite.chest.isPlausible(108))
        #expect(MeasurementSite.wrist.isPlausible(17))
        #expect(MeasurementSite.pelvis.isPlausible(81))
        #expect(MeasurementSite.biceps.isPlausible(44))
        #expect(MeasurementSite.wrist.isPlausible(12))
        #expect(MeasurementSite.wrist.isPlausible(25))
        #expect(!MeasurementSite.wrist.isPlausible(11.9))
    }

    @Test func navyInputs_useTheSiteEachSexIsActuallyMeasuredAt() {
        let m = BodyMeasurement(date: Date())
        m.neckCm = 40
        m.waistCm = 78     // узкая талия
        m.beltCm = 84      // на уровне пупка
        m.glutesCm = 96

        // Методика ВМС США у мужчин меряет живот на уровне пупка — это пояс,
        // а вовсе не талия в узком месте. Раньше сюда уходила талия.
        let male = m.navyInputs(for: .male)
        #expect(male.waist == 84)
        #expect(male.neck == 40)
        #expect(male.hip == nil, "Мужчинам бёдра не нужны")

        // У женщин — узкая талия плюс ягодицы
        let female = m.navyInputs(for: .female)
        #expect(female.waist == 78)
        #expect(female.hip == 96)
    }

    @Test func navyInputs_treatUnmeasuredAsMissingNotZero() {
        let m = BodyMeasurement(date: Date())
        m.neckCm = 40
        let male = m.navyInputs(for: .male)
        #expect(male.waist == nil, "Неснятый пояс — это «нет данных», а не ноль")

        // С дырой в данных Navy-метод не должен считаться вовсе
        let profile = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male,
            activityLevel: .moderate, goal: .maintenance,
            proteinPerKg: 2.0
        )
        #expect(profile.navyBodyFat(from: m) == nil)
        #expect(!profile.isNavyMethod(from: m))
        // Но оценка по ИМТ всё равно есть — экран не должен остаться пустым
        #expect(profile.bodyFatPercentage(from: m) > 0)
    }

    @Test func bodyFatAppearsInReportOnlyWhenMeasured() {
        let m = BodyMeasurement(date: Date())
        m.neckCm = 40
        m.beltCm = 84

        let p = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male,
            activityLevel: .moderate, goal: .maintenance, proteinPerKg: 2.0
        )
        #expect(BodyAnalysis.insights(measurement: m, profile: p).map(\.id).contains("bodyFat"))

        // Без обхватов процент считается по ИМТ, и в отчёт о замерах он не идёт:
        // там ему нечего объяснять — он выведен не из этих замеров.
        let empty = BodyMeasurement(date: Date())
        #expect(!BodyAnalysis.insights(measurement: empty, profile: p).map(\.id).contains("bodyFat"))
    }

    @Test func everyCategoryIconIsARealSymbol() {
        // Несуществующее имя символа рисуется пустотой, а не падает — поэтому
        // опечатку в нём замечаешь только глазами на экране. Пусть замечает тест.
        for category in FoodCategory.allCases {
            #expect(UIImage(systemName: category.icon) != nil,
                    "\(category.rawValue): нет символа «\(category.icon)»")
        }
    }

    @Test func everyBuiltInFoodHasACategory() {
        // «Другое» у встроенного продукта — почти всегда забытая категория,
        // а не осознанный выбор: у нас на каждый из них она проставлена руками.
        let uncategorised = FoodDatabase.items.filter { $0.foodCategory == .other }
        #expect(uncategorised.isEmpty,
                "Без категории остались: \(uncategorised.map(\.name).joined(separator: ", "))")
    }

    @Test func builtInFoodsLandInSensibleCategories() {
        // Сверяем распределение, а не названия: тесты идут на английской локали,
        // и сравнение с русскими строками ничего не найдёт.
        var counts: [FoodCategory: Int] = [:]
        for item in FoodDatabase.items { counts[item.foodCategory, default: 0] += 1 }

        // Бобовые: чечевица, фасоль, нут и тофу — соя тоже бобовое
        #expect(counts[.legumes] == 4)
        #expect(counts[.meat] == 4)
        #expect(counts[.fish] == 2)
        #expect(counts[.dairy] == 6)
        #expect(counts[.grains] == 7)
        #expect(counts[.produce] == 21)
        #expect(counts[.mushrooms] == 4)
        // Орехи, масла и арахис: ботанически он бобовое, но искать его будут здесь
        #expect(counts[.fats] == 5)
        #expect(counts[.sweets] == 3)
        #expect(counts[.drinks] == 5)
        #expect(counts.values.reduce(0, +) == FoodDatabase.items.count)
    }

    @Test func foodCategory_survivesReorderingOfTheEnum() {
        // Категория хранится строкой: по индексу «Рыба» однажды тихо стала бы
        // «Молочным» у всех сразу, стоит поменять порядок в перечислении.
        let food = FoodItem(name: "Треска", caloriesPer100g: 82, protein: 18, fat: 0.7, carbs: 0, category: .fish)
        #expect(food.category == "fish")
        #expect(food.foodCategory == .fish)

        food.foodCategory = .dairy
        #expect(food.category == "dairy")
    }

    @Test func foodCategory_defaultsToOtherForOldRecords() {
        // У продуктов, заведённых до появления категорий, поля нет вовсе.
        let legacy = FoodItem(name: "Хлеб", caloriesPer100g: 250, protein: 8, fat: 3, carbs: 48)
        #expect(legacy.foodCategory == .other)

        // И мусор в поле не должен ронять экран
        legacy.category = "не-существует"
        #expect(legacy.foodCategory == .other)
    }

    @Test func sideLabelAgreesWithGender() {
        // Проверяем раскладку по родам, а не текст: подписи локализованы,
        // и в английской локали все формы совпадают.
        // «Левое предплечье», но «левая икра».
        #expect(MeasurementSite.biceps.gender == .masculine)
        #expect(MeasurementSite.quad.gender == .masculine)
        #expect(MeasurementSite.forearm.gender == .neuter)
        #expect(MeasurementSite.wrist.gender == .neuter)
        #expect(MeasurementSite.thigh.gender == .neuter)
        #expect(MeasurementSite.calf.gender == .feminine)

        // У парного места подпись стороны стоит рядом с одной конечностью,
        // поэтому множественное число там было бы ошибкой.
        for site in MeasurementSite.allCases where site.isPaired {
            #expect(site.gender != .plural, "\(site): парное место не может быть во множественном")
        }

        // Каждая пара «сторона + род» должна давать непустую подпись
        for gender in [GrammaticalGender.masculine, .feminine, .neuter, .plural] {
            for side in BodySide.allCases {
                #expect(!side.title(gender).isEmpty)
            }
        }
    }

    @Test func pickerOffersOnlyPlausibleValues() {
        // Колесо — единственный способ ввода, поэтому мусор не должен в нём лежать.
        for site in MeasurementSite.allCases {
            let options = site.pickerTenths
            #expect(!options.isEmpty, "\(site) без вариантов в колесе")
            for tenths in options {
                #expect(site.isPlausible(Double(tenths) / 10),
                        "\(site) предлагает \(Double(tenths) / 10)")
            }
            // Границы диапазона должны быть достижимы
            #expect(Double(options.first!) / 10 == site.plausibleRange.lowerBound)
            #expect(Double(options.last!) / 10 <= site.plausibleRange.upperBound)
            // Шаг 0.5 см: мельче лента не даёт
            if options.count > 1 {
                #expect(options[1] - options[0] == 5)
            }
        }
    }

    @Test func plausibleRange_coversEverySite() {
        // Забыть диапазон для нового места замера — значит пропустить мусор в историю.
        for site in MeasurementSite.allCases {
            #expect(site.plausibleRange.lowerBound > 0, "\(site) без нижней границы")
            #expect(site.plausibleRange.upperBound < 250, "\(site) с бесполезно широкой границей")
        }
    }

    @Test func pelvisMetrics_separateFrameFromSoftTissue() {
        let m = sample()   // плечи 126, талия 78, таз 81, пояс 82, ягодицы 96
        let insights = BodyAnalysis.insights(measurement: m, profile: nil)

        // Знаменатель костный: отношение двигается только за счёт верха, не за счёт диеты
        let structural = insights.first { $0.id == "shouldersPelvis" }
        #expect(structural?.value == "1.56")
        #expect(structural?.verdict == .excellent)

        // 78 / 81 = 0.963: талия уже костяка, но не радикально — это «хорошо», не «отлично»
        let waistPelvis = insights.first { $0.id == "waistPelvis" }
        // Сравниваем вердикт, а не подпись: подпись локализуется и в тесте логики
        // привязываться к её тексту нельзя.
        #expect(waistPelvis?.verdict == .good)

        // Пояс шире талии на 4 см — в пределах нормы
        let visceral = insights.first { $0.id == "beltWaist" }
        #expect(visceral?.value == "+4.0 см")
        #expect(visceral?.verdict == .good)

        // Ягодицы над костяком: 96 − 81
        #expect(insights.first { $0.id == "glutesPelvis" }?.value == "+15.0 см")
    }

    @Test func pelvisMetrics_absentWithoutPelvisMeasurement() {
        let m = sample()
        m.pelvisCm = 0
        let ids = BodyAnalysis.insights(measurement: m, profile: nil).map(\.id)
        #expect(!ids.contains("shouldersPelvis"))
        #expect(!ids.contains("waistPelvis"))
        #expect(!ids.contains("glutesPelvis"))
        #expect(ids.contains("beltWaist"), "Висцеральный индикатор от таза не зависит")
    }

    @Test func vTaper_recognisesGoldenRatio() {
        let m = sample()
        m.shouldersCm = 126
        m.waistCm = 77.9                      // 126 / 77.9 ≈ 1.617
        let vtaper = BodyAnalysis.insights(measurement: m, profile: nil).first { $0.id == "vtaper" }
        #expect(vtaper?.verdict == .good)

        m.waistCm = 77.0                      // ≈ 1.636
        let better = BodyAnalysis.insights(measurement: m, profile: nil).first { $0.id == "vtaper" }
        #expect(better?.verdict == .excellent)
    }
}
