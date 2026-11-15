import Testing
import Foundation
@testable import Calories

/// «Запас диеты»: пройденное до рекомендованного перерыва.
struct DietReserveTests {
    @Test func halfwayIsHalf() {
        let reserve = DietReserve(weeksIn: 4, limit: 8)
        #expect(reserve.progress == 0.5)
        #expect(reserve.weeksLeft == 4)
        #expect(!reserve.isDue)
    }

    /// Срок вышел — полоса полная, а осталось не «минус два», а ноль.
    @Test func pastTheLimitIsFullAndDue() {
        let reserve = DietReserve(weeksIn: 10, limit: 8)
        #expect(reserve.progress == 1)
        #expect(reserve.weeksLeft == 0)
        #expect(reserve.isDue)
    }

    @Test func exactlyAtTheLimitIsDue() {
        #expect(DietReserve(weeksIn: 8, limit: 8).isDue)
    }

    @Test func aFreshDeficitIsEmpty() {
        #expect(DietReserve(weeksIn: 0, limit: 8).progress == 0)
    }

    /// Пороги — те же, что у самого сигнала: полоса не должна показывать
    /// «осталось три недели», когда подсказка уже говорит «пора».
    @Test func itUsesTheSignalsOwnLimits() {
        var calm = RecoverySignal.Input()
        calm.weeksInDeficit = 3
        calm.weeklyRatePercent = 0.5
        #expect(DietReserve(calm).limit == RecoverySignal.weeksBeforeBreak)

        var steep = calm
        steep.weeklyRatePercent = 1.0
        #expect(DietReserve(steep).limit == RecoverySignal.weeksBeforeBreakWhenSteep)
        #expect(DietReserve(steep).limit < DietReserve(calm).limit)
    }

    /// Нулевой и отрицательный вход не ломают полосу.
    @Test func nonsenseInputIsClamped() {
        let reserve = DietReserve(weeksIn: -2, limit: 0)
        #expect(reserve.weeksIn == 0)
        #expect(reserve.limit == 1)
        #expect(reserve.progress == 0)
    }
}
