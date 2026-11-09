import Testing
import Foundation
@testable import Calories

@Suite struct DailyAdviceTests {

    // MARK: - Калории vs цель

    @Test func onTargetWhenWithinFivePercent() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let advice = DailyAdviceEngine.advice(
            consumedToday: 2000,
            adaptedTodayGoal: 2000,
            macrosToday: Macros(protein: 80, fat: 60, carbs: 200),
            proteinTarget: 80,
            fatTarget: 60,
            carbsTarget: 250,
            weightTrend: nil,
            lastLoggedDay: yesterday
        )
        #expect(advice == .onTarget, "Ожидался .onTarget, но получил \(advice)")
    }

    @Test func overGoalWhenAboveFivePercent() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 2400,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil
        )
        if case .overGoal(let pct) = advice {
            #expect(pct == 20)
        } else {
            Issue.record("Ожидался overGoal, получено \(advice)")
        }
    }

    @Test func underGoalWhenBelowEightyPercent() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 1500,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil
        )
        if case .underGoal(let pct) = advice {
            #expect(pct == 25)
        } else {
            Issue.record("Ожидался underGoal, получено \(advice)")
        }
    }

    // MARK: - Белок

    @Test func lowProteinWhenBelowEightyPercent() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 1800,
            adaptedTodayGoal: 2000,
            macrosToday: Macros(protein: 40, fat: 50, carbs: 200),
            proteinTarget: 100,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil
        )
        if case .lowProtein(let grams) = advice {
            #expect(grams == 60)
        } else {
            Issue.record("Ожидался lowProtein, получено \(advice)")
        }
    }

    // MARK: - Жиры

    @Test func lowFatWhenBelowEightyPercent() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 1800,
            adaptedTodayGoal: 2000,
            macrosToday: Macros(protein: 80, fat: 20, carbs: 200),
            proteinTarget: nil,
            fatTarget: 80,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil
        )
        if case .lowFat(let grams) = advice {
            #expect(grams == 60)
        } else {
            Issue.record("Ожидался lowFat, получено \(advice)")
        }
    }

    // MARK: - Углеводы

    @Test func highCarbsWhenAboveThirtyPercent() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 2000,
            adaptedTodayGoal: 2000,
            macrosToday: Macros(protein: 80, fat: 60, carbs: 400),
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: 250,
            weightTrend: nil,
            lastLoggedDay: nil
        )
        if case .highCarbs(let grams) = advice {
            #expect(grams == 150)
        } else {
            Issue.record("Ожидался highCarbs, получено \(advice)")
        }
    }

    // MARK: - Вес на плато

    @Test func weightPlateauWhenNoChangeFourteenDays() {
        let weights = Array(repeating: 75.0, count: 14)
        let advice = DailyAdviceEngine.advice(
            consumedToday: 2000,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: weights,
            lastLoggedDay: nil
        )
        if case .weightPlateau(let days) = advice {
            #expect(days == 14)
        } else {
            Issue.record("Ожидался weightPlateau, получено \(advice)")
        }
    }

    // MARK: - Не логировали еду

    @Test func notLoggingWhenThreeDaysWithoutEntries() {
        let calendar = Calendar.current
        let now = Date()
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        let advice = DailyAdviceEngine.advice(
            consumedToday: 1800,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: threeDaysAgo,
            now: now
        )
        if case .notLogging(let days) = advice {
            #expect(days >= 2) // может быть 2 или 3 в зависимости от времени суток
        } else {
            Issue.record("Ожидался notLogging, но получил \(advice)")
        }
    }

    // MARK: - Приоритет: перебор важнее белка

    @Test func overGoalWinsOverLowProtein() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 3000,
            adaptedTodayGoal: 2000,
            macrosToday: Macros(protein: 20, fat: 100, carbs: 300),
            proteinTarget: 100,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil
        )
        if case .overGoal = advice {
            // OK - перебор важнее
        } else {
            Issue.record("Ожидался overGoal, получено \(advice)")
        }
    }
}
