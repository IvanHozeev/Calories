import Testing
import Foundation
@testable import Calories

/// Чем кончился день: слово для карточки дня в истории.
struct DayStandingTests {
    @Test func noEntriesNothingToJudge() {
        #expect(DayStanding(consumed: 0, goal: 2749, hasEntries: false) == .empty)
    }

    @Test func aNormMissingOrZeroIsNotJudgedEither() {
        #expect(DayStanding(consumed: 500, goal: 0, hasEntries: true) == .empty)
    }

    @Test func overIsByHowManyKilocalories() {
        #expect(DayStanding(consumed: 3159, goal: 2749, hasEntries: true) == .over(410))
    }

    /// Ровно по норме — не перебор: «перебор» начинается с первой лишней калории.
    @Test func exactlyOnTheNormIsOnTarget() {
        #expect(DayStanding(consumed: 2749, goal: 2749, hasEntries: true) == .onGoal)
        #expect(DayStanding(consumed: 2750, goal: 2749, hasEntries: true) == .over(1))
    }

    /// Недобор меньше десятой части нормы — обычная жизнь, не промах.
    @Test func aSmallShortfallIsStillOnTarget() {
        #expect(DayStanding(consumed: 2500, goal: 2749, hasEntries: true) == .onGoal)
    }

    @Test func shortByMoreThanATenthIsUnder() {
        #expect(DayStanding(consumed: 1950, goal: 2749, hasEntries: true) == .under(799))
    }

    /// Граница: девять десятых нормы ещё в норме, на килокалорию меньше — недобор.
    @Test func theTenthIsTheBoundary() {
        #expect(DayStanding(consumed: 2000, goal: 2000, hasEntries: true) == .onGoal)
        #expect(DayStanding(consumed: 1800, goal: 2000, hasEntries: true) == .onGoal)
        #expect(DayStanding(consumed: 1799, goal: 2000, hasEntries: true) == .under(201))
    }
}
