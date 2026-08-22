import Testing
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
        #expect(abs(bmr - 1776) < 5)
    }

    @Test func bmr_female() {
        let bmr = profile(age: 30, heightCm: 165, weightKg: 60, sex: .female).bmr
        #expect(abs(bmr - 1400) < 20)
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
        var p = profile(sex: .male)
        p.waistCm = 85
        p.neckCm = 37
        #expect(p.navyBodyFat != nil)
        #expect(p.navyBodyFat! > 0)
    }

    @Test func navyBodyFat_nil_whenWaistEqualsNeck() {
        var p = profile(sex: .male)
        p.waistCm = 37
        p.neckCm = 37
        #expect(p.navyBodyFat == nil)
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

// MARK: - CalorieStore

@MainActor
struct CalorieStoreTests {

    private let store: CalorieStore

    init() throws {
        let container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext)
        store.dailyGoal = 2000
    }

    // MARK: Initial state

    @Test func initialState_noEntries() {
        #expect(store.todayEntries.isEmpty)
        #expect(store.consumedToday == 0)
    }

    @Test func initialState_sevenDaysHistory() {
        #expect(store.lastSevenDays.count == 7)
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

    // MARK: Recent foods

    @Test func recentFoods_storesNames() {
        store.recordRecentFoods(["Гречка"])
        #expect(store.recentFoodNames.contains("Гречка"))
    }

    @Test func recentFoods_mostRecentIsFirst() {
        store.recordRecentFoods(["Первое"])
        store.recordRecentFoods(["Второе"])
        #expect(store.recentFoodNames.first == "Второе")
    }

    @Test func recentFoods_deduplicates() {
        store.recordRecentFoods(["Творог"])
        store.recordRecentFoods(["Творог"])
        #expect(store.recentFoodNames.filter { $0 == "Творог" }.count == 1)
    }

    @Test func recentFoods_capsAt20() {
        let names = (1...25).map { "Еда\($0)" }
        store.recordRecentFoods(names)
        #expect(store.recentFoodNames.count <= 20)
    }
}
