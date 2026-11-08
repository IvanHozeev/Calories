import Testing
import Foundation
@testable import Calories

/// Чем кончилась фаза и что это значит.
///
/// Здесь живут решения, которые ломаются незаметно и всплывают строкой,
/// обвиняющей человека в том, чего не было: «вес не сдвинулся, дефицита
/// нет» после трёх дней, «всё хорошо» на наборе, ушедшем в жир.
struct PlanOutcomeTests {

    /// Замер с заданной давностью: срок решает раньше всего остального.
    private func change(startKg: Double = 80, deltaKg: Double, fatDeltaKg: Double,
                        days: Int = 60) -> CompositionChange {
        let endKg = startKg + deltaKg
        let startFatKg = startKg * 0.20
        let endFatKg = startFatKg + fatDeltaKg
        return CompositionChange(
            fromDate: Date().addingTimeInterval(TimeInterval(-days) * 86_400),
            toDate: Date(),
            startWeightKg: startKg,
            endWeightKg: endKg,
            startFatPercent: startFatKg / startKg * 100,
            endFatPercent: endFatKg / endKg * 100
        )
    }

    // MARK: - Допуск плана

    /// Допуск пропорционален тому, сколько фаза собиралась сдвинуть, но не
    /// меньше трёхсот граммов: шум весов, утренний стул и вчерашняя соль
    /// есть и у того, кто не планировал ничего.
    @Test
    func theToleranceHasAFloorForSmallPlans() {
        #expect(PlanStatus.tolerance(plannedChangeKg: 0, settling: false) == 0.3)
        // Полкило плана — пять процентов от него меньше пола.
        #expect(PlanStatus.tolerance(plannedChangeKg: 0.5, settling: false) == 0.3)
        // Десять килограммов — пять процентов уже больше.
        #expect(PlanStatus.tolerance(plannedChangeKg: 10, settling: false) == 0.5)
        // Знак плана роли не играет: набор и сушка шумят одинаково.
        #expect(PlanStatus.tolerance(plannedChangeKg: -10, settling: false)
                == PlanStatus.tolerance(plannedChangeKg: 10, settling: false))
    }

    /// После подъёма калорий допуск шире: возвращаются гликоген и вода, и
    /// без этого приложение объявило бы провалом то, что само назначило
    /// переходом.
    @Test
    func settlingWidensTheTolerance() {
        let calm = PlanStatus.tolerance(plannedChangeKg: 4, settling: false)
        let settling = PlanStatus.tolerance(plannedChangeKg: 4, settling: true)
        #expect(settling > calm)
        #expect(settling == Plan.settlingToleranceKg)
    }

    /// Внутри допуска план идёт как задумано, за ним — вперёд или позади,
    /// смотря куда фаза вела вес.
    @Test
    func theVerdictKnowsWhichWayThePhaseWasGoing() {
        let tolerance = 0.5
        #expect(PlanStatus.verdict(deviationKg: 0.4, direction: -1, tolerance: tolerance) == .onTrack)
        // Сушка: ушли дальше прогноза — впереди.
        #expect(PlanStatus.verdict(deviationKg: -1.0, direction: -1, tolerance: tolerance) == .ahead)
        // Сушка: вес пошёл выше прогноза — позади.
        #expect(PlanStatus.verdict(deviationKg: 1.0, direction: -1, tolerance: tolerance) == .behind)
        // Набор — зеркально.
        #expect(PlanStatus.verdict(deviationKg: 1.0, direction: 1, tolerance: tolerance) == .ahead)
        #expect(PlanStatus.verdict(deviationKg: -1.0, direction: 1, tolerance: tolerance) == .behind)
    }

    // MARK: - Исход фазы

    /// Срок решает раньше состава: на трёх днях вердикт получался особенно
    /// глупым — вес ушёл ровно в темп плана, а приложение сообщало, что
    /// дефицита нет.
    @Test
    func tooSoonBeatsEverythingElse() {
        let tooSoon = change(deltaKg: -0.3, fatDeltaKg: -0.3,
                             days: CompositionChange.minimumDays - 1)
        for intent in [PlanIntent.cut, .bulk, .maintenance] {
            #expect(tooSoon.verdict(for: intent) == .tooSoon)
        }
        // Ровно на пороге судить уже можно.
        let enough = change(deltaKg: -3, fatDeltaKg: -3,
                            days: CompositionChange.minimumDays)
        #expect(enough.verdict(for: .cut) != .tooSoon)
    }

    /// Жир вниз, мышцы вверх — успех в любой фазе, и по весу его не увидеть.
    /// Раньше такой исход на поддержании объявлялся дорогим просто потому,
    /// что вес сдвинулся: лучший результат называли худшим.
    @Test
    func recompositionIsASuccessWhateverThePhaseWas() {
        let recomp = change(deltaKg: 0.2, fatDeltaKg: -3)
        #expect(recomp.isRecomposition)
        for intent in [PlanIntent.cut, .bulk, .maintenance] {
            #expect(recomp.verdict(for: intent) == .recomposition)
        }
    }

    /// На сушке мышцы на месте — успех, мышцы ушли — дорого, вес стоит —
    /// не сдвинулось ничего.
    @Test
    func aCutIsJudgedByWhatWentAway() {
        #expect(change(deltaKg: -4, fatDeltaKg: -4).verdict(for: .cut) == .worked)
        // Минус шесть килограммов, из них четыре — сухая масса.
        #expect(change(deltaKg: -6, fatDeltaKg: -2).verdict(for: .cut) == .costly)
        #expect(change(deltaKg: -0.2, fatDeltaKg: -0.1).verdict(for: .cut) == .stalled)
    }

    /// Потеря сухой массы внутри погрешности метода потерей не называется.
    ///
    /// У Navy около ±3% жира, что на 76 кг даёт ±2.3 кг сухой. Минус два
    /// килограмма сухой при минус четырёх общего выглядят в таблице как
    /// половина потерянного веса — но различить их метод не способен, и
    /// сказать «ты потерял два кило мышц» значит соврать точностью, которой
    /// нет. Это не недосмотр: так решено, и так должно остаться.
    @Test
    func leanLossInsideTheNoiseIsNotCalledALoss() {
        let inside = change(deltaKg: -4, fatDeltaKg: -2)
        #expect(abs(inside.leanDeltaKg) < inside.noiseKg)
        #expect(inside.verdict(for: .cut) == .worked)
    }

    /// На наборе наоборот: прибавка сухой — успех, прибавка жиром — дорого.
    ///
    /// Прежний вердикт намерения не знал и на наборе, ушедшем в жир, честно
    /// докладывал, что сухая масса держится.
    @Test
    func aBulkIsJudgedByWhatCame() {
        #expect(change(deltaKg: 5, fatDeltaKg: 0.5).verdict(for: .bulk) == .worked)
        #expect(change(deltaKg: 3, fatDeltaKg: 2.9).verdict(for: .bulk) == .costly)
        #expect(change(deltaKg: 0.2, fatDeltaKg: 0.1).verdict(for: .bulk) == .stalled)
    }

    /// На поддержании смотрим не на то, сдвинулся ли вес, а на то, чем он
    /// сдвинулся: жир — это разошедшаяся норма, вода и гликоген — обычная
    /// неделя.
    @Test
    func maintenanceAsksWhatTheWeightWasMadeOf() {
        #expect(change(deltaKg: 0.2, fatDeltaKg: 0.1).verdict(for: .maintenance) == .worked)
        // Прибавка почти целиком жиром — норма разошлась с расходом.
        #expect(change(deltaKg: 2, fatDeltaKg: 1.8).verdict(for: .maintenance) == .costly)
        // Прибавка не жиром: вода и гликоген, обычная неделя.
        #expect(change(deltaKg: 2, fatDeltaKg: 0.2).verdict(for: .maintenance) == .worked)
    }

    /// Совет зависит и от вердикта, и от намерения: «ешь больше» на сушке и
    /// на наборе — противоположные советы, и пустым он быть не должен.
    @Test
    func everyVerdictHasSomethingToSay() {
        let cases: [(CompositionChange, PlanIntent)] = [
            (change(deltaKg: -4, fatDeltaKg: -4), .cut),
            (change(deltaKg: -6, fatDeltaKg: -2), .cut),
            (change(deltaKg: -0.2, fatDeltaKg: -0.1), .cut),
            (change(deltaKg: 5, fatDeltaKg: 0.5), .bulk),
            (change(deltaKg: 3, fatDeltaKg: 2.9), .bulk),
            (change(deltaKg: 0.2, fatDeltaKg: 0.1), .bulk),
            (change(deltaKg: 2, fatDeltaKg: 1.8), .maintenance),
            (change(deltaKg: 0.2, fatDeltaKg: 0.1), .maintenance),
            (change(deltaKg: 0.2, fatDeltaKg: -3), .cut),
            (change(deltaKg: -0.3, fatDeltaKg: -0.3, days: 3), .cut)
        ]
        for (composition, intent) in cases {
            #expect(!composition.advice(for: intent).isEmpty,
                    "Молчит на \(composition.verdict(for: intent)) при \(intent)")
        }
    }
}
