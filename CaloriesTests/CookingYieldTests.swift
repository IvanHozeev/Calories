import Testing
import Foundation
@testable import Calories

/// Пересчёт сухого в готовое.
///
/// Главное здесь — не арифметика, а то, что калории при варке не меняются.
/// Если это правило где-то поедет, блюдо из макарон начнёт врать в полтора
/// раза, и заметить это будет нечем: на весах всё сойдётся.
@Suite struct CookingYieldTests {

    @Test func boilingAddsWeightNotCalories() {
        // Сто грамм сухих макарон — это 350 ккал и 250 г отварных.
        let cookedWeight = CookingYield.cookedGrams(dry: 100, factor: 2.5)
        #expect(cookedWeight == 250)

        // Те же 350 ккал, размазанные по 250 граммам, — это 140 на сто.
        let per100 = CookingYield.cookedPer100g(dryPer100g: 350, factor: 2.5)
        #expect(abs(per100 - 140) < 0.01)

        // И энергия сходится: 250 г готового по 140 — те же 350 ккал.
        #expect(abs(cookedWeight / 100 * per100 - 350) < 0.01)
    }

    @Test func macrosThinOutTheSameWay() {
        let dry = Macros(protein: 12, fat: 1.5, carbs: 72)
        let cooked = CookingYield.cookedMacros(dryPer100g: dry, factor: 2.5)
        #expect(abs(cooked.protein - 4.8) < 0.01)
        #expect(abs(cooked.carbs - 28.8) < 0.01)
        // Белка в тарелке столько же, сколько было в сухом.
        #expect(abs(cooked.protein * 2.5 - dry.protein) < 0.01)
    }

    @Test func theDryWeightCanBeRecovered() {
        let dry = CookingYield.dryGrams(cooked: 250, factor: 2.5)
        #expect(abs(dry - 100) < 0.01)
    }

    // MARK: - Своё измерение

    @Test func weighingTheResultTeachesTheFactor() throws {
        let factor = try #require(CookingYield.learn(dry: 100, cooked: 260))
        #expect(abs(factor - 2.6) < 0.01)
    }

    /// Перепутанные местами веса — не коэффициент: принять такое молча значит
    /// испортить вес блюда вдвое.
    @Test func swappedWeightsAreRejected() {
        #expect(CookingYield.learn(dry: 250, cooked: 100) == nil)
    }

    /// И слишком большой коэффициент — тоже описка: втрое с небольшим
    /// набирает рис, больше не набирает ничто.
    @Test func anImplausibleFactorIsRejected() {
        #expect(CookingYield.learn(dry: 100, cooked: 900) == nil)
        #expect(CookingYield.learn(dry: 0, cooked: 250) == nil)
    }

    /// Крупы и бобовые имеют справочный старт, остальное — нет: у мяса
    /// «уваривание» означает потерю воды, и это другой расчёт.
    @Test func onlyGrainsAndLegumesHaveAStartingPoint() {
        #expect(CookingYield.reference[.grains] != nil)
        #expect(CookingYield.reference[.legumes] != nil)
        #expect(CookingYield.reference[.meat] == nil)
    }

    /// Справочный старт проверен по живому замеру: пятьсот грамм макарон
    /// дают около 1160 готовых. Справочники пишут ×2.6 и ошибаются вверх —
    /// они не различают «аль денте» и разваренное.
    @Test func theStartingPointMatchesARealPot() throws {
        let factor = try #require(CookingYield.reference[.grains])
        let cooked = CookingYield.cookedGrams(dry: 500, factor: factor)
        #expect(abs(cooked - 1160) <= 60, "Вышло \(cooked) вместо примерно 1160")
    }

    /// Без коэффициента ничего не пересчитывается: нулевой множитель не должен
    /// обнулять калории.
    @Test func aZeroFactorChangesNothing() {
        #expect(CookingYield.cookedPer100g(dryPer100g: 350, factor: 0) == 350)
        #expect(CookingYield.dryGrams(cooked: 250, factor: 0) == 250)
    }
}
