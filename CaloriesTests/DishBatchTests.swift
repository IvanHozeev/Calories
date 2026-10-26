import Testing
import Foundation
@testable import Calories

/// Партия — одна сваренная кастрюля.
///
/// Проверяем не столько арифметику остатка, сколько то, когда приложение
/// открывает рот. Напоминание «доешь сегодня» ценно ровно один раз; если оно
/// приходит за три дня или на пустую кастрюлю, человек перестаёт его читать,
/// и вместе с ним перестаёт читать все остальные.
@Suite struct DishBatchTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    // MARK: - Остаток

    @Test func whatIsLeftAndHowManyServings() {
        let state = DishBatch.state(cookedAt: day(-1), totalGrams: 4000,
                                    eatenGrams: 800, servingGrams: 400)
        #expect(state.remainingGrams == 3200)
        #expect(state.remainingServings == 8)
        #expect(!state.isFinished)
    }

    /// Съели больше, чем сварили, — остаток ноль, а не минус.
    @Test func eatingMoreThanCookedLeavesNothing() {
        let state = DishBatch.state(cookedAt: day(-2), totalGrams: 1000,
                                    eatenGrams: 1200, servingGrams: 300)
        #expect(state.remainingGrams == 0)
        #expect(state.isFinished)
    }

    /// Без порции остаток всё равно виден — просто в граммах.
    @Test func withoutAServingItIsJustGrams() {
        let state = DishBatch.state(cookedAt: day(-1), totalGrams: 2000,
                                    eatenGrams: 500, servingGrams: nil)
        #expect(state.remainingGrams == 1500)
        #expect(state.remainingServings == nil)
    }

    // MARK: - Прогноз

    @Test func thePaceSaysWhenItRunsOut() throws {
        // Сварено три дня назад, съедено 1200 — это 400 в день (день готовки
        // считается). Осталось 800, то есть ещё на два дня.
        let state = DishBatch.state(cookedAt: day(-3), totalGrams: 2000,
                                    eatenGrams: 1200, servingGrams: 400)
        #expect(state.dailyPace == 300)
        let runsOut = try #require(state.runsOutOn)
        let daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                               to: calendar.startOfDay(for: runsOut)).day
        #expect(daysLeft == 3)
    }

    /// Ничего не съедено — судить не по чему, и приложение молчит, а не
    /// выдумывает «хватит навсегда».
    @Test func anUntouchedBatchHasNoPace() {
        let state = DishBatch.state(cookedAt: day(0), totalGrams: 4000,
                                    eatenGrams: 0, servingGrams: 400)
        #expect(state.dailyPace == nil)
        #expect(state.runsOutOn == nil)
        #expect(DishBatch.advice(state) == nil)
    }

    // MARK: - Что говорить

    /// Последний съедобный день — единственный момент, когда стоит сказать
    /// «доешь».
    @Test func theLastGoodDaySaysEatToday() {
        let cooked = day(-DishBatch.shelfLifeDays)
        let state = DishBatch.state(cookedAt: cooked, totalGrams: 2000,
                                    eatenGrams: 1500, servingGrams: 400)
        #expect(DishBatch.advice(state) == .eatToday(servingsLeft: 1.25))
    }

    /// Срок вышел — это уже не про запас.
    @Test func pastTheShelfLifeItIsNotFoodAnyMore() {
        let cooked = day(-(DishBatch.shelfLifeDays + 1))
        let state = DishBatch.state(cookedAt: cooked, totalGrams: 2000,
                                    eatenGrams: 500, servingGrams: 400)
        #expect(DishBatch.advice(state) == .spoiled)
    }

    /// Кончается завтра — вот теперь «пора готовить». Не за три дня: такое
    /// напоминание забудется.
    @Test func runningOutTomorrowSuggestsCookingAgain() throws {
        // Сварено вчера, съедено 1000 за два дня — 500 в день, осталось 500.
        let state = DishBatch.state(cookedAt: day(-1), totalGrams: 1500,
                                    eatenGrams: 1000, servingGrams: 500)
        guard case .cookAgain = try #require(DishBatch.advice(state)) else {
            Issue.record("Ожидали предложение приготовить снова")
            return
        }
    }

    /// Запаса ещё много — молчим.
    @Test func plentyLeftMeansSilence() {
        let state = DishBatch.state(cookedAt: day(0), totalGrams: 4000,
                                    eatenGrams: 400, servingGrams: 400)
        #expect(DishBatch.advice(state) == nil)
    }

    /// Пустая партия не советует ничего: ни доесть, ни выбросить.
    @Test func anEmptyBatchIsSilent() {
        let state = DishBatch.state(cookedAt: day(-5), totalGrams: 1000,
                                    eatenGrams: 1000, servingGrams: 250)
        #expect(DishBatch.advice(state) == nil)
    }

    /// Срок важнее запаса: даже когда еды много, испорченная остаётся
    /// испорченной.
    @Test func spoilageOutranksTheForecast() {
        let state = DishBatch.state(cookedAt: day(-10), totalGrams: 4000,
                                    eatenGrams: 400, servingGrams: 400)
        #expect(DishBatch.advice(state) == .spoiled)
    }
}
