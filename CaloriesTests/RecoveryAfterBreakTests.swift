import Testing
import Foundation
import SwiftData
@testable import Calories

/// Первые дни после диет-брейка: признаки усталости и итог недели меряются
/// только внутри нынешнего дефицита.
///
/// На брейке вес стоит, потому что так задумано. Пока окна захватывали его,
/// в первый же день после брейка приложение писало «вес стоит три недели,
/// сдвинь рефид», а неделю поддержания судило по темпу сушки.
@MainActor
@Suite(.serialized)
struct RecoveryAfterBreakTests {
    private let container: ModelContainer
    private let store: CalorieStore
    private let calendar = Calendar.current

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
        store.isPremium = true
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))!
    }

    /// Сушка четыре недели, неделя брейка, дальше снова сушка; план начат
    /// `started` дней назад. Вес всё это время стоит на месте.
    private func cutBreakCut(started: Int) {
        store.startPlan(Plan(startDate: daysAgo(started), startWeightKg: 80, phases: [
            PlanPhase(intent: .cut, durationWeeks: 4),
            PlanPhase(intent: .maintenance, durationWeeks: 1, isDietBreak: true),
            PlanPhase(intent: .cut, durationWeeks: 6),
        ]))
        for day in stride(from: started + 7, through: 0, by: -1) {
            store.addWeight(80, date: calendar.date(byAdding: .hour, value: 8, to: daysAgo(day))!)
        }
    }

    @Test func theFirstDayAfterABreakSeesNoStall() {
        cutBreakCut(started: 35)
        let input = store.recoveryInput()
        #expect(input.isCutting)
        #expect(input.stallWeeks == 0, "Неделя брейка — не застой")
        #expect(input.weeklyChangeKg == nil, "Неделю назад шёл брейк — сравнивать не с чем")
        #expect(input.tdeeDropPercent == nil)
        #expect(RecoverySignal.verdict(input) == .fine)
    }

    /// Две недели сушки после брейка без движения — это две недели застоя,
    /// а не шесть: недели до брейка и сам брейк в счёт не идут.
    @Test func aStallCountsOnlyWeeksSinceTheBreak() {
        cutBreakCut(started: 49)
        #expect(store.recoveryInput().stallWeeks == 2)
    }

    /// Неделя брейка не судится по темпу сушки, которая началась сегодня.
    @Test func theWeekOfABreakHasNoPlannedLoss() {
        cutBreakCut(started: 35)
        #expect(store.weekReviewInput().plannedWeeklyKg == nil)
    }

    /// Неделя наполовину в брейке получает только свою долю темпа.
    @Test func aWeekPartlyInABreakGetsItsShareOfThePace() throws {
        cutBreakCut(started: 38)
        let planned = try #require(store.weekReviewInput().plannedWeeklyKg)
        let fullWeek = 80 * PlanIntent.cut.defaultWeeklyRatePercent / 100
        #expect(planned > 0)
        #expect(planned < fullWeek * 0.6, "Три дня сушки из семи — меньше половины недельного темпа")
    }

    /// На обычной неделе сушки план недели — её темп.
    @Test func aPlainCutWeekKeepsItsPace() throws {
        store.startPlan(Plan(startDate: daysAgo(14), startWeightKg: 80,
                             phases: [PlanPhase(intent: .cut, durationWeeks: 10)]))
        let planned = try #require(store.weekReviewInput().plannedWeeklyKg)
        let fullWeek = 80 * PlanIntent.cut.defaultWeeklyRatePercent / 100
        #expect(abs(planned - fullWeek) < 0.05)
    }
}
