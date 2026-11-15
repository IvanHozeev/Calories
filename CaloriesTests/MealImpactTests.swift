import Testing
import Foundation
@testable import Calories

/// «После этого приёма»: сколько останется от дня и закроется ли белок.
struct MealImpactTests {
    private func day(goal: Int = 2749, consumed: Int = 1513, protein: Double = 71) -> MealImpact.Day {
        MealImpact.Day(goal: goal, consumed: consumed,
                       macros: Macros(protein: protein, fat: 30, carbs: 200),
                       proteinTarget: 136, fatTarget: 64, carbsTarget: 407)
    }

    private func impact(day: MealImpact.Day, draft: Int = 0, draftProtein: Double = 0,
                        this: Int, thisProtein: Double) -> MealImpact {
        MealImpact(day: day,
                   draftCalories: draft, draftMacros: Macros(protein: draftProtein, fat: 0, carbs: 0),
                   thisCalories: this, thisMacros: Macros(protein: thisProtein, fat: 0, carbs: 0))
    }

    @Test func whatIsLeftIsTheNormMinusEverythingEaten() {
        let result = impact(day: day(), this: 198, thisProtein: 41)
        #expect(result.eatenAfter == 1711)
        #expect(result.remainingAfter == 1038)
        #expect(!result.isOver)
    }

    /// Набранное в приёме — часть дня: порция считается поверх него.
    @Test func theDraftCountsTowardsTheDay() {
        let result = impact(day: day(), draft: 484, draftProtein: 46, this: 198, thisProtein: 41)
        #expect(result.remainingAfter == 554)
        #expect(abs(result.proteinAfter - (71 + 46 + 41)) < 1e-9)
    }

    @Test func goingPastTheNormIsNegative() {
        let result = impact(day: day(goal: 2000, consumed: 1900), this: 300, thisProtein: 10)
        #expect(result.remainingAfter == -200)
        #expect(result.isOver)
    }

    @Test func aPortionThatReachesTheTargetClosesProtein() {
        let closing = impact(day: day(protein: 100), this: 160, thisProtein: 40)
        #expect(closing.closesProtein)
    }

    /// Уже закрытый до порции белок она не «закрывает»: подсказывать нечего.
    @Test func aTargetAlreadyMetIsNotClosedAgain() {
        let result = impact(day: day(protein: 140), this: 160, thisProtein: 40)
        #expect(!result.closesProtein)
    }

    @Test func noTargetNothingToClose() {
        var noTarget = day()
        noTarget.proteinTarget = nil
        #expect(!impact(day: noTarget, this: 100, thisProtein: 50).closesProtein)
    }

    /// База и порция дают то же, что день, черновик и порция по отдельности.
    @Test func aBaseIsTheSameAsItsParts() {
        let base = MealImpact.Base(day: day(), draftCalories: 484,
                                   draftMacros: Macros(protein: 46, fat: 0, carbs: 0))
        let viaBase = MealImpact(base: base, thisCalories: 198, thisMacros: Macros(protein: 41, fat: 0, carbs: 0))
        let direct = impact(day: day(), draft: 484, draftProtein: 46, this: 198, thisProtein: 41)
        #expect(viaBase == direct)
    }

    // MARK: Быстрые порции

    @Test func theUsualPortionIsFirstThenHundredOneFiftyTwoFifty() {
        #expect(FoodQuantityView.quickOptions(start: 180) == [180, 100, 150, 250])
    }

    /// Совпавшую с обычной порцию второй раз не предлагаем.
    @Test func aDuplicateOfTheUsualPortionIsSkipped() {
        #expect(FoodQuantityView.quickOptions(start: 100) == [100, 150, 250, 200])
        #expect(FoodQuantityView.quickOptions(start: 250) == [250, 100, 150, 200])
    }

    @Test func atMostFourOptions() {
        for start in [20.0, 100, 150, 333, 1200] {
            #expect(FoodQuantityView.quickOptions(start: start).count == 4)
        }
    }
}
