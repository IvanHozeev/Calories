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
            lastLoggedDay: nil,
            now: at(hour: 16)
        )
        if case .underGoal(let pct, let remaining) = advice {
            #expect(pct == 35, "съедено 700 из 2000 — это 35%, а не недобор в 65%")
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
            lastLoggedDay: nil,
            now: at(hour: 22)
        )
        if case .underGoal(let pct, let remaining) = advice {
            #expect(pct == 25, "съедено 500 из 2000 — это 25%, а не недобор в 75%")
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

    // MARK: - Белок отстаёт от темпа дня

    @Test func proteinIsNotBehindInTheMorning() {
        // Прожита четверть дня: «съедено 0 из 136 г» — это утро, а не отставание.
        #expect(!DailyAdviceEngine.isBehindPace(eaten: 0, target: 136, progress: 0.25))
    }

    @Test func proteinOnPaceIsNotBehind() {
        // Прожито 60%, съедено 70 из 136 — идём даже с опережением.
        #expect(!DailyAdviceEngine.isBehindPace(eaten: 70, target: 136, progress: 0.6))
    }

    @Test func proteinFarBehindInTheEvening() {
        // Прожито 90%, пора бы 95 г, съедено 30 — отстаём заметно.
        #expect(DailyAdviceEngine.isBehindPace(eaten: 30, target: 136, progress: 0.9))
    }

    @Test func proteinWithoutTargetIsNeverBehind() {
        #expect(!DailyAdviceEngine.isBehindPace(eaten: 0, target: nil, progress: 1))
    }

    @Test func fatFarBehindInTheEvening() {
        // Прожито 90%, пора бы 72 г жиров, съедено 20 — отстаём заметно.
        #expect(DailyAdviceEngine.isBehindPace(eaten: 20, target: 80, progress: 0.9))
    }

    @Test func fatOnPaceIsNotBehind() {
        #expect(!DailyAdviceEngine.isBehindPace(eaten: 40, target: 80, progress: 0.6))
    }

    // MARK: - Углеводы сверх нормы в плитке

    @Test func carbsOverTargetAfterHalfTheDay() {
        // Прожито 80% дня, цель 250 г, съедено 330 г — больше 130% нормы.
        #expect(DailyAdviceEngine.isOverTarget(eaten: 330, target: 250, progress: 0.8))
    }

    @Test func carbsExactlyOneThirtyIsNotOver() {
        // Ровно 130% цели — порог строгий, это ещё не «сверх нормы».
        #expect(!DailyAdviceEngine.isOverTarget(eaten: 325, target: 250, progress: 0.8))
    }

    @Test func carbsOverTargetInTheMorningIsNotOver() {
        // Цель дня ещё не израсходована: плотный завтрак — не перебор.
        #expect(!DailyAdviceEngine.isOverTarget(eaten: 400, target: 250, progress: 0.25))
    }

    @Test func carbsWithoutTargetIsNeverOver() {
        #expect(!DailyAdviceEngine.isOverTarget(eaten: 500, target: nil, progress: 1))
    }

    // MARK: - Вес на плато

    /// Взвешивание за `daysAgo` дней до сейчас, в полдень.
    private func weighIn(_ kg: Double, daysAgo: Int) -> AdviceWeighIn {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return AdviceWeighIn(date: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!,
                             kg: kg)
    }

    private func plateauAdvice(_ weighIns: [AdviceWeighIn]) -> DailyAdvice {
        DailyAdviceEngine.advice(
            consumedToday: 2000, adaptedTodayGoal: 2000, macrosToday: .zero,
            proteinTarget: nil, fatTarget: nil, carbsTarget: nil,
            weighIns: weighIns, lastLoggedDay: nil, now: at(hour: 12))
    }

    /// Плато видно тому, кто взвешивается раз в неделю.
    ///
    /// Прежнее правило требовало четырнадцать взвешиваний за четырнадцать
    /// дней, то есть по одному в день без единого пропуска. Прежний тест
    /// подавал четырнадцать одинаковых чисел и этого не замечал: он проверял
    /// код, а не то, как люди взвешиваются.
    @Test func weightPlateauIsSeenByAWeeklyWeigher() {
        let advice = plateauAdvice([weighIn(75.0, daysAgo: 14), weighIn(75.2, daysAgo: 7),
                                    weighIn(75.1, daysAgo: 0)])
        #expect(advice == .weightPlateau(days: 14), "получено \(advice)")
    }

    /// Двух недель по трём взвешиваниям за последние три дня нет.
    @Test func recentWeighInsDoNotClaimATwoWeekPlateau() {
        let advice = plateauAdvice([weighIn(75, daysAgo: 2), weighIn(75, daysAgo: 1), weighIn(75, daysAgo: 0)])
        #expect(advice != .weightPlateau(days: 14), "срок в три дня выдан за две недели")
    }

    @Test func twoWeighInsAreNotEnoughForAPlateau() {
        let advice = plateauAdvice([weighIn(75, daysAgo: 14), weighIn(75, daysAgo: 0)])
        #expect(advice != .weightPlateau(days: 14))
    }

    @Test func aMovingWeightIsNotAPlateau() {
        let advice = plateauAdvice([weighIn(76.0, daysAgo: 14), weighIn(75.4, daysAgo: 7),
                                    weighIn(75.0, daysAgo: 0)])
        #expect(advice != .weightPlateau(days: 14), "минус килограмм за две недели — не плато")
    }

    // MARK: - Что съедено

    /// В тексте «съедено N%» — N это съеденное.
    ///
    /// При пустом дне раньше писали «съедено 100% нормы».
    @Test func underGoalReportsWhatWasEatenNotWhatIsMissing() {
        // В 17:00 пора бы съесть 62%, а совет заговаривает при отставании больше
        // 20 пунктов — значит, 42% и меньше. Ноль записей — отдельный совет
        // «ничего не записано» (`NothingLoggedTodayTests`), здесь его нет.
        for (eaten, percent) in [(300, 15), (700, 35)] {
            let advice = DailyAdviceEngine.advice(
                consumedToday: eaten, adaptedTodayGoal: 2000, macrosToday: .zero,
                proteinTarget: nil, fatTarget: nil, carbsTarget: nil,
                lastLoggedDay: nil, now: at(hour: 17))
            guard case .underGoal(let pct, let remaining) = advice else {
                Issue.record("при \(eaten) ккал ждали underGoal, получено \(advice)")
                continue
            }
            #expect(pct == percent, "съедено \(eaten) из 2000 — \(percent)%, а не \(pct)%")
            #expect(remaining == 2000 - eaten)
        }
    }

    // MARK: - Бросившему дневник не советуют есть

    /// «Нет записей» важнее «пора ужинать».
    ///
    /// Документация приоритетов говорила именно это, а движок держал свои числа
    /// и отдавал вечером «пора ужинать» человеку, который три дня не открывал
    /// дневник.
    @Test func anAbandonedDiaryOutranksTheDinnerHint() {
        let lastLogged = Calendar.current.date(byAdding: .day, value: -4, to: Date())!
        for hour in [15, 19] {
            let advice = DailyAdviceEngine.advice(
                consumedToday: 0, adaptedTodayGoal: 2000, macrosToday: .zero,
                proteinTarget: nil, fatTarget: nil, carbsTarget: nil,
                lastLoggedDay: lastLogged, now: at(hour: hour))
            if case .notLogging = advice { continue }
            Issue.record("в \(hour):00 после четырёх дней без записей получено \(advice)")
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
            lastLoggedDay: threeDaysAgo,
            now: now
        )
        if case .notLogging(let days) = advice {
            #expect(days >= 2) // может быть 2 или 3 в зависимости от времени суток
        } else {
            Issue.record("Ожидался notLogging, но получил \(advice)")
        }
    }

    // MARK: - Приоритет: перебор важнее остальных подсказок

    @Test func overGoalWinsOverOtherHints() {
        let advice = DailyAdviceEngine.advice(
            consumedToday: 3000,
            adaptedTodayGoal: 2000,
            macrosToday: Macros(protein: 20, fat: 100, carbs: 300),
            proteinTarget: 100,
            fatTarget: nil,
            carbsTarget: nil,
            lastLoggedDay: nil
        )
        if case .overGoal = advice {
            // OK - перебор важнее
        } else {
            Issue.record("Ожидался overGoal, получено \(advice)")
        }
    }
}

/// Пустой день: «ничего не записано» вместо «пора ужинать».
@Suite struct NothingLoggedTodayTests {
    private func at(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    private func advice(consumed: Int, now: Date) -> DailyAdvice {
        DailyAdviceEngine.advice(consumedToday: consumed, adaptedTodayGoal: 2700,
                                 macrosToday: .zero, proteinTarget: nil, fatTarget: nil, carbsTarget: nil,
                                 lastLoggedDay: Calendar.current.date(byAdding: .day, value: -1, to: now),
                                 wakeHour: 7, sleepHour: 23, now: now)
    }

    @Test func anEmptyEveningSaysNothingIsLogged() {
        #expect(advice(consumed: 0, now: at(20)) == .nothingToday)
    }

    @Test func anEmptyMorningSaysNothing() {
        #expect(advice(consumed: 0, now: at(9)) == .none)
    }

    @Test func aLightEveningStillCallsForDinner() {
        #expect(advice(consumed: 900, now: at(19)) == .noDinnerYet)
    }

    /// По строке видно, что с ней делать: она открывает добавление еды.
    @Test func theNothingLoggedHintOpensTheAddSheet() {
        #expect(DayHint.from(.nothingToday, now: at(20)).first?.action == .openAdd)
        #expect(DayHint.from(.onTarget, now: at(20)).first?.action == nil)
    }
}
