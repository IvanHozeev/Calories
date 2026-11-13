import Testing
import Foundation
@testable import Calories

/// Приёмка ТЗ-3: объяснитель веса.
///
/// История — синтетика с фиксированным зерном, как предлагает ТЗ:
/// углеводы равномерно от −150 до +150 г, поздний приём от 0 до 3 ч, шум
/// нормальный с σ = 0,10 кг.
struct WeightExplainerTests {
    /// SplitMix64: один и тот же поток чисел при одном зерне.
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform(_ low: Double, _ high: Double) -> Double {
            low + (high - low) * Double(next() >> 11) / Double(1 << 53)
        }
        mutating func normal(sigma: Double) -> Double {
            let u1 = max(uniform(0, 1), 1e-12), u2 = uniform(0, 1)
            return sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    /// История, где отклонение собрано из причин с известными коэффициентами.
    private func history(days: Int = 60, carbs: Double = 0.004, late: Double = 0.3,
                         sodium: Double? = nil, sodiumMissingShare: Double = 0,
                         noiseOnly: Bool = false, seed: UInt64 = 42) -> [WeightExplainer.Day] {
        var rng = Generator(state: seed)
        return (0..<days).map { index in
            let carbsDelta = rng.uniform(-150, 150)
            let lateHours = rng.uniform(0, 3)
            let sodiumDelta = rng.uniform(-1000, 1000)
            let noise = rng.normal(sigma: 0.10)
            let missing = Double(index) < Double(days) * sodiumMissingShare
            let signal = noiseOnly ? 0 : carbs * carbsDelta + late * lateHours + (sodium ?? 0) * sodiumDelta
            return .init(residualKg: signal + noise,
                         carbsDeltaG: carbsDelta,
                         sodiumDeltaMg: sodium == nil && sodiumMissingShare == 0 ? nil : (missing ? nil : sodiumDelta),
                         lateHours: lateHours,
                         afterFast: false)
        }
    }

    private func today(residual: Double, carbs: Double = 0, late: Double = 0,
                       sodium: Double? = nil) -> WeightExplainer.Day {
        .init(residualKg: residual, carbsDeltaG: carbs, sodiumDeltaMg: sodium, lateHours: late, afterFast: false)
    }

    // 1
    @Test func yesterdaysCarbsExplainTheJump() throws {
        let result = try #require(WeightExplainer.explain(history: history(), today: today(residual: 0.62, carbs: 150)))
        #expect(result.contributions.first?.factor == .carbs)
        #expect(abs((result.contributions.first?.kg ?? 0) - 0.60) <= 0.15)
    }

    // 2
    @Test func aLateMealExplainsTheJump() throws {
        let result = try #require(WeightExplainer.explain(history: history(), today: today(residual: 0.65, late: 2)))
        #expect(result.contributions.first?.factor == .lateMeal)
        #expect(abs((result.contributions.first?.kg ?? 0) - 0.60) <= 0.15)
    }

    // 3
    @Test func twentyPairsAreNotEnough() {
        #expect(WeightExplainer.explain(history: history(days: 20), today: today(residual: 0.62, carbs: 150)) == nil)
    }

    // 4
    @Test func noiseExplainsNothing() {
        #expect(WeightExplainer.explain(history: history(noiseOnly: true), today: today(residual: 0.62, carbs: 150)) == nil)
    }

    // 5
    @Test func aSmallDeviationIsLeftAlone() {
        #expect(WeightExplainer.explain(history: history(), today: today(residual: 0.3, carbs: 150)) == nil)
    }

    // 6
    @Test func causesPullingTheOtherWayAreNotAnExplanation() {
        #expect(WeightExplainer.explain(history: history(), today: today(residual: -0.7, carbs: 150)) == nil)
    }

    // 7
    @Test func sodiumKnownTooRarelyIsLeftOut() throws {
        let past = history(sodium: 0.0002, sodiumMissingShare: 0.4)
        let result = try #require(WeightExplainer.explain(history: past,
                                                          today: today(residual: 0.62, carbs: 150, sodium: 800)))
        #expect(!result.contributions.contains { $0.factor == .sodium })
    }

    // 8
    @Test func onlyTheTwoLargestCausesAreNamed() throws {
        let past = history(carbs: 0.004, late: 0.1, sodium: 0.0002)
        let result = try #require(WeightExplainer.explain(history: past,
                                                          today: today(residual: 0.96, carbs: 150, late: 2, sodium: 800)))
        #expect(result.contributions.map(\.factor) == [.carbs, .lateMeal])
    }

    // 9
    @Test func theSameInputGivesTheSameAnswer() {
        let a = WeightExplainer.explain(history: history(), today: today(residual: 0.62, carbs: 150))
        let b = WeightExplainer.explain(history: history(), today: today(residual: 0.62, carbs: 150))
        #expect(a == b)
    }
}
