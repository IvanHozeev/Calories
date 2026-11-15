import Foundation

/// Сколько диеты «в запасе» до рекомендованного перерыва.
///
/// Приложение уже говорит «пора на перерыв» — но только когда срок вышел. Эта
/// полоса показывает его заранее: сколько недель дефицита прошло и сколько
/// осталось до того момента, когда сигнал сработает. Числа те же, что у
/// самого сигнала (`RecoverySignal`), чтобы полоса и подсказка не спорили.
nonisolated struct DietReserve: Equatable, Sendable {
    /// Недель дефицита подряд.
    let weeksIn: Int
    /// Через сколько недель советуем перерыв: восемь, а на крутом темпе пять.
    let limit: Int

    init(weeksIn: Int, limit: Int) {
        self.weeksIn = max(0, weeksIn)
        self.limit = max(1, limit)
    }

    /// Из входа сигнала восстановления: те же пороги.
    init(_ input: RecoverySignal.Input) {
        self.init(weeksIn: input.weeksInDeficit,
                  limit: RecoverySignal.weeksBeforeBreak(rate: input.weeklyRatePercent))
    }

    /// Доля пройденного, 0…1: полоса заполняется к перерыву.
    var progress: Double { min(Double(weeksIn) / Double(limit), 1) }

    /// Сколько недель осталось; ноль — перерыв уже пора.
    var weeksLeft: Int { max(limit - weeksIn, 0) }

    var isDue: Bool { weeksIn >= limit }
}
