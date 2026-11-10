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

    @Test func underGoalInTheAfternoonWhenBehindPace() {
        // 16:00: прожито 9 из 16 часов дня — пора бы съесть ~56% нормы,
        // а съедено 35%. Отставание на 21% — повод напомнить.
        let advice = DailyAdviceEngine.advice(
            consumedToday: 700,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil,
            now: at(hour: 16)
        )
        if case .underGoal(let pct, let remaining) = advice {
            #expect(pct == 65)
            #expect(remaining == 1300)
        } else {
            Issue.record("Ожидался underGoal, получено \(advice)")
        }
    }

    @Test func noUnderGoalInTheMorning() {
        // Утром недобранная норма — это норма, а не новость.
        let advice = DailyAdviceEngine.advice(
            consumedToday: 0,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil,
            now: at(hour: 10)
        )
        #expect(advice == .none, "Ожидалось молчание, получено \(advice)")
    }

    @Test func noUnderGoalWhenOnPace() {
        // 15:00 — половина дня, съедено 45% при нужных 50%. Это темп, а не
        // отставание: молчим.
        let advice = DailyAdviceEngine.advice(
            consumedToday: 900,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil,
            now: at(hour: 15)
        )
        #expect(advice == .none, "Ожидалось молчание, получено \(advice)")
    }

    @Test func underGoalAtNightReportsRemaining() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 500,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil,
            now: at(hour: 22)
        )
        if case .underGoal(let pct, let remaining) = advice {
            #expect(pct == 75)
            #expect(remaining == 1500)
        } else {
            Issue.record("Ожидался underGoal, получено \(advice)")
        }
    }

    @Test func dinnerHintWinsOverUnderGoalInTheEvening() {
        // Вечером конкретное действие («пора ужинать») важнее сводки.
        let advice = DailyAdviceEngine.advice(
            consumedToday: 400,
            adaptedTodayGoal: 2000,
            macrosToday: .zero,
            proteinTarget: nil,
            fatTarget: nil,
            carbsTarget: nil,
            weightTrend: nil,
            lastLoggedDay: nil,
            now: at(hour: 19)
        )
        #expect(advice == .noDinnerYet, "Ожидался noDinnerYet, получено \(advice)")
    }

    /// Сегодняшний момент с заданным часом — чтобы советы не зависели от
    /// того, когда запустили тесты.
    private func at(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
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
