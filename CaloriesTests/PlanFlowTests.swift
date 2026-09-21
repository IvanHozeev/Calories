import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Перенос рефида

struct RefeedMoveTests {

    private let calendar = Calendar.current

    /// Дата с нужным днём недели (Пн=0…Вс=6) на неделе 7 сентября 2026 — это понедельник.
    private func day(_ index: Int) -> Date {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        return calendar.date(byAdding: .day, value: index, to: monday)!
    }

    private func plan(_ style: WeekendStyle = .satSun, cycling: Bool = true) -> Plan {
        Plan(startDate: day(0), durationWeeks: 12, startWeightKg: 80, targetWeightKg: 76,
             cyclingEnabled: cycling, weekendStyle: style)
    }

    @Test func movingToWednesday_takesTheBiggestDayAhead() {
        let moved = plan().movingRefeed(to: day(2))
        let offsets = moved.cycleOffsets(forWeekOf: day(2))
        #expect(offsets[2] == 0.30)
        #expect(offsets[6] == WeekendStyle.satSun.cycleOffsets[2])
        #expect(offsets[5] == 0.14)
    }

    @Test func moving_keepsWeeklyAverage() {
        let base = plan()
        let moved = base.movingRefeed(to: day(2))
        let tdee = 2600.0
        let before = (0..<7).map { base.calorieTarget(for: day($0), tdee: tdee) }.reduce(0, +)
        let after = (0..<7).map { moved.calorieTarget(for: day($0), tdee: tdee) }.reduce(0, +)
        #expect(before == after)
    }

    @Test func move_endsWithTheWeek() {
        let moved = plan().movingRefeed(to: day(2))
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: day(2))!
        #expect(moved.cycleOffsets(forWeekOf: nextWeek) == WeekendStyle.satSun.cycleOffsets)
    }

    @Test func noMove_whenRefeedAlreadyPassed() {
        // Пн+Вт: в среду рефид уже съеден, второй сломал бы неделю.
        #expect(plan(.monTue).refeedSwapDay(for: day(2)) == nil)
    }

    @Test func noMove_withoutCycling() {
        #expect(plan(cycling: false).refeedSwapDay(for: day(2)) == nil)
    }

    @Test func noMove_onTheRefeedItself() {
        #expect(plan().refeedSwapDay(for: day(6)) == nil)
    }

    @Test func onlyOneMovePerWeek() {
        let moved = plan().movingRefeed(to: day(2))
        #expect(moved.refeedSwapDay(for: day(3)) == nil)
    }

    @Test func undo_onlyUntilTheMovedDayPasses() {
        let moved = plan().movingRefeed(to: day(2))
        #expect(moved.canUndoRefeedMove(on: day(2)))
        #expect(!moved.canUndoRefeedMove(on: day(3)))
    }

    @Test func move_survivesEncoding() throws {
        let moved = plan().movingRefeed(to: day(2))
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(moved))
        #expect(decoded.refeedMove == moved.refeedMove)
    }
}

// MARK: - Диет-брейки

struct DietBreakTests {

    private let calendar = Calendar.current

    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))! }

    private func week(_ n: Int, plus days: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: n * 7 + days, to: start)!
    }

    private func plan(cutWeeks: Int = 12, every: Int? = nil, firstAfter: Int? = nil) -> Plan {
        Plan(startDate: start, startWeightKg: 80,
             phases: [PlanPhase(intent: .cut, durationWeeks: cutWeeks, weeklyRatePercent: 0.5,
                                dietBreakEvery: every, firstDietBreakAfter: firstAfter)])
    }

    @Test func schedule_laysBreaksBetweenCutBlocks() {
        // 12 недель дефицита, брейк раз в 4: 4 + 1 + 4 + 1 + 4, в конце брейка нет.
        let segments = plan(every: 4).timeline
        #expect(segments.map(\.durationWeeks) == [4, 1, 4, 1, 4])
        #expect(segments.map(\.isDietBreak) == [false, true, false, true, false])
        #expect(plan(every: 4).durationWeeks == 14)
    }

    @Test func schedule_noTrailingBreak() {
        #expect(plan(cutWeeks: 8, every: 4).timeline.map(\.durationWeeks) == [4, 1, 4])
    }

    @Test func schedule_firstBreakCanComeLater() {
        #expect(plan(cutWeeks: 12, every: 4, firstAfter: 7).timeline.map(\.durationWeeks) == [7, 1, 4, 1, 1])
    }

    @Test func breakWeek_isMaintenance() {
        let p = plan(every: 4)
        #expect(p.isDietBreak(on: week(4, plus: 2)))
        #expect(p.weeklyRateKg(on: week(4, plus: 2)) == 0)
        #expect(p.weeklyRateKg(on: week(5, plus: 2)) < 0)
    }

    @Test func manualBreak_startsAtNextPlanWeek() {
        let base = plan()
        // Середина шестой недели: брейк встанет с седьмой.
        let today = week(5, plus: 3)
        let withBreak = base.startingDietBreak(from: today, weeks: 1)
        #expect(withBreak.phases.map(\.durationWeeks) == [6, 1, 6])
        #expect(withBreak.isDietBreak(on: week(6)))
        #expect(!withBreak.isDietBreak(on: today))
        #expect(withBreak.durationWeeks == base.durationWeeks + 1)
    }

    @Test func manualBreak_keepsThePast() {
        let base = plan()
        let today = week(5, plus: 3)
        let withBreak = base.startingDietBreak(from: today, weeks: 2)
        #expect(abs(withBreak.projectedWeight(on: today) - base.projectedWeight(on: today)) < 0.0001)
        #expect(withBreak.phase(on: today)?.intent == .cut)
    }

    @Test func manualBreak_onPlanWeekBoundaryStartsToday() {
        let withBreak = plan().startingDietBreak(from: week(6), weeks: 1)
        #expect(withBreak.isDietBreak(on: week(6)))
    }

    @Test func manualBreak_notDuringABreak() {
        #expect(!plan(every: 4).canStartDietBreak(from: week(4)))
    }

    @Test func manualBreak_resetsTheScheduleCounter() {
        let withBreak = plan(cutWeeks: 12, every: 4).startingDietBreak(from: week(2, plus: 1), weeks: 1)
        // 3 недели дефицита, ручной брейк, дальше 9 недель с брейком после каждых 4.
        #expect(withBreak.timeline.map(\.durationWeeks) == [3, 1, 4, 1, 4, 1, 1])
    }

    @Test func cancelingPendingBreak_restoresThePlan() {
        let base = plan(every: 4)
        let today = week(2, plus: 1)
        let restored = base.startingDietBreak(from: today, weeks: 1).cancelingPendingDietBreak(on: today)
        #expect(restored.timeline.map(\.durationWeeks) == base.timeline.map(\.durationWeeks))
    }

    @Test func startedBreak_cannotBeCanceled() {
        let withBreak = plan().startingDietBreak(from: week(5, plus: 3), weeks: 1)
        #expect(withBreak.pendingManualDietBreak(on: week(6, plus: 1)) == nil)
    }

    @Test func cutWeeksElapsed_ignoresBreaks() {
        let p = plan(every: 4)
        #expect(p.cutWeeksElapsed(inPhaseWithID: p.phases[0].id, on: week(6, plus: 2)) == 6)
    }

    @Test func schedule_survivesEncoding() throws {
        let p = plan(every: 5, firstAfter: 7).startingDietBreak(from: week(2, plus: 1), weeks: 1)
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p))
        #expect(decoded.timeline.map(\.durationWeeks) == p.timeline.map(\.durationWeeks))
        #expect(decoded.timeline.map(\.isDietBreak) == p.timeline.map(\.isDietBreak))
    }

    @Test func breakWeek_isFlatEvenWithCycling() {
        var p = plan(every: 4)
        p.cyclingEnabled = true
        let tdee = 2800.0
        let breakDays = (0..<7).map { calendar.date(byAdding: .day, value: 28 + $0, to: start)! }
        let targets = Set(breakDays.map { p.calorieTarget(for: $0, tdee: tdee) })
        #expect(targets == [Int(tdee)])
    }

    @Test func refeedIsNotTakenFromABreakDay() {
        // Брейк с 30 июля (чт). Неделя 27 июля — 2 августа: Пн–Ср дефицит, Чт–Вс брейк.
        var p = plan(every: 4)
        p.cyclingEnabled = true
        p.weekendStyle = .satSun
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28))!
        #expect(p.refeedSwapDay(for: tuesday) == nil)
    }

    @Test func breakStartsAtMidnight_evenForAPlanStartedInTheEvening() {
        // План запустили в 20:00. Для нормы на день брейк должен идти с полуночи
        // первого дня пятой недели, а не с 20:00.
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: start)!
        let p = Plan(startDate: evening, startWeightKg: 80,
                     phases: [PlanPhase(intent: .cut, durationWeeks: 12, weeklyRatePercent: 0.5, dietBreakEvery: 4)])
        let breakMidnight = calendar.startOfDay(for: week(4))
        #expect(p.isDietBreak(on: breakMidnight))
        #expect(!p.isDietBreak(on: calendar.date(byAdding: .minute, value: -1, to: breakMidnight)!))
    }

    @Test func storedPlanStartIsNormalisedToMidnight() throws {
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: start)!
        let p = Plan(startDate: evening, startWeightKg: 80, phases: [PlanPhase(intent: .cut, durationWeeks: 8)])
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p))
        #expect(decoded.startDate == calendar.startOfDay(for: evening))
    }

    @Test func title_staysCutWithBreaks() {
        let p = plan().startingDietBreak(from: week(2, plus: 1), weeks: 1)
        #expect(p.title == plan().title)
    }
}

// MARK: - Фазы: что делать дальше

struct PhaseAdviceTests {

    private func record(_ intent: PlanIntent, weeks: Int, endedWeeksAgo: Int) -> PhaseRecord {
        let end = Date().addingTimeInterval(-Double(endedWeeksAgo) * 7 * 86_400)
        return PhaseRecord(intent: intent,
                           startDate: end.addingTimeInterval(-Double(weeks) * 7 * 86_400),
                           endDate: end, startWeightKg: 80, endWeightKg: 76)
    }

    /// Сразу после сушки снова сушиться нельзя: телу нужно поддержание.
    @Test func rightAfterACutTheAnswerIsRest() {
        let advice = PhaseAdvice.recommend(history: [record(.cut, weeks: 12, endedWeeksAgo: 1)],
                                           maintenanceSince: Date().addingTimeInterval(-7 * 86_400),
                                           bodyFatPercent: 22)
        #expect(advice.kind == .maintain)
        #expect(advice.weeks == PhaseAdvice.restWeeks(afterCutOf: 12) - 1)
    }

    /// Отдых считается от длины сушки: половина, но не меньше месяца.
    @Test func restIsHalfTheCutButAtLeastAMonth() {
        #expect(PhaseAdvice.restWeeks(afterCutOf: 12) == 6)
        #expect(PhaseAdvice.restWeeks(afterCutOf: 4) == 4)
    }

    /// Отдохнул и жира много — пора сушиться, и темп назван.
    @Test func afterEnoughRestHighFatMeansCut() {
        let advice = PhaseAdvice.recommend(history: [record(.cut, weeks: 8, endedWeeksAgo: 10)],
                                           maintenanceSince: Date().addingTimeInterval(-10 * 7 * 86_400),
                                           bodyFatPercent: 22)
        #expect(advice.kind == .cut)
        #expect(advice.weeklyRatePercent == 0.5)
    }

    /// Сухой — можно набирать, и темп вдвое осторожнее.
    @Test func beingLeanMeansBulk() {
        let advice = PhaseAdvice.recommend(history: [], maintenanceSince: nil, bodyFatPercent: 12)
        #expect(advice.kind == .bulk)
        #expect(advice.weeklyRatePercent == 0.25)
    }

    /// Середина — выбор за человеком, приложение не решает за него.
    @Test func theMiddleIsLeftToTheLifter() {
        #expect(PhaseAdvice.recommend(history: [], maintenanceSince: nil, bodyFatPercent: 18).kind == .maintain)
    }

    /// Без замеров советовать нечего — и так и говорим.
    @Test func withoutMeasurementsThereIsNoAdvice() {
        let advice = PhaseAdvice.recommend(history: [], maintenanceSince: nil, bodyFatPercent: nil)
        #expect(advice.kind == .maintain)
        #expect(advice.weeks == nil)
    }
}

// MARK: - Вердикт по плану

/// Правила «идём по плану / отстаём / опережаем» жили внутри стотридцати
/// строк расчёта и проверялись только целиком, через стор. Здесь они сами по
/// себе: допуск и вердикт — это решения, а не арифметика.
struct PlanVerdictTests {

    @Test func maintenanceIsNeverAhead() {
        // Поддержание никуда не ведёт, поэтому любой уход от нуля — уход
        // в сторону, в какую бы сторону он ни был.
        #expect(PlanStatus.verdict(deviationKg: 1.2, direction: 0, tolerance: 0.3) == .behind)
        #expect(PlanStatus.verdict(deviationKg: -1.2, direction: 0, tolerance: 0.3) == .behind)
    }

    @Test func onACutBeingLighterThanPlannedIsAhead() {
        #expect(PlanStatus.verdict(deviationKg: -1.0, direction: -1, tolerance: 0.3) == .ahead)
        #expect(PlanStatus.verdict(deviationKg: 1.0, direction: -1, tolerance: 0.3) == .behind)
    }

    @Test func onABulkItIsTheOtherWayAround() {
        #expect(PlanStatus.verdict(deviationKg: 1.0, direction: 1, tolerance: 0.3) == .ahead)
        #expect(PlanStatus.verdict(deviationKg: -1.0, direction: 1, tolerance: 0.3) == .behind)
    }

    @Test func insideTheToleranceEverythingIsOnTrack() {
        #expect(PlanStatus.verdict(deviationKg: 0.29, direction: -1, tolerance: 0.3) == .onTrack)
        #expect(PlanStatus.verdict(deviationKg: -0.3, direction: 1, tolerance: 0.3) == .onTrack,
                "Ровно по границе — ещё в допуске")
    }

    @Test func toleranceNeverDropsBelowTheNoiseOfTheScales() {
        // Поддержание не собиралось сдвинуть ничего, и пропорциональный допуск
        // был бы нулевым: тогда каждое утро объявляло бы провал.
        #expect(PlanStatus.tolerance(plannedChangeKg: 0, settling: false) == 0.3)
    }

    @Test func toleranceGrowsWithWhatThePhasePlanned() {
        // Пять процентов от задуманного: у шести килограммов это 300 г,
        // у двадцати — уже килограмм.
        #expect(PlanStatus.tolerance(plannedChangeKg: -20, settling: false) == 1.0)
    }

    @Test func rightAfterRaisingCaloriesTheToleranceIsWider() {
        // Возвращаются гликоген и вода — пара килограммов, которые приложение
        // само же и назначило переходом.
        #expect(PlanStatus.tolerance(plannedChangeKg: 0, settling: true) == Plan.settlingToleranceKg)
        #expect(PlanStatus.verdict(deviationKg: 1.4, direction: 0,
                                   tolerance: PlanStatus.tolerance(plannedChangeKg: 0, settling: true)) == .onTrack)
    }
}
