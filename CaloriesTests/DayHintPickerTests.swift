import Testing
import Foundation
@testable import Calories

/// Приёмка ТЗ-1, этап 1: одна подсказка под кольцом.
///
/// Срочность — из таблицы, утверждённой владельцем 13.11: копия, пост,
/// диет-брейк и плато важнее перебора (перебор бывает сознательным).
/// Отсюда строка 9: перебор — 95, а не 100 из предложения ТЗ.
struct DayHintPickerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hint(_ id: String, _ urgency: Int, source: DayHint.Source = .dailyAdvice,
                      expiresIn: TimeInterval = 3600) -> DayHint {
        DayHint(id: id, source: source, title: id, detail: nil, urgency: urgency,
                expiresAt: now.addingTimeInterval(expiresIn), action: nil)
    }

    // 1
    @Test func nothingInNothingOut() {
        let result = DayHintPicker.pick([], now: now, dismissed: [])
        #expect(result.main == nil)
        #expect(result.rest.isEmpty)
    }

    // 2
    @Test func theMostUrgentWins() {
        let a = hint("A", 100), b = hint("B", 60)
        let result = DayHintPicker.pick([a, b], now: now, dismissed: [])
        #expect(result.main == a)
        #expect(result.rest == [b])
    }

    // 3
    @Test func anExpiredHintIsDropped() {
        let a = hint("A", 100, expiresIn: -60), b = hint("B", 60)
        let result = DayHintPicker.pick([a, b], now: now, dismissed: [])
        #expect(result.main == b)
        #expect(result.rest.isEmpty)
    }

    // 4
    @Test func aDismissedHintIsDropped() {
        let a = hint("A", 100), b = hint("B", 60)
        #expect(DayHintPicker.pick([a, b], now: now, dismissed: ["A"]).main == b)
    }

    // 5
    @Test func onATieTheOneExpiringSoonerWins() {
        let a = hint("A", 90, expiresIn: 7200), b = hint("B", 90, expiresIn: 3600)
        let result = DayHintPicker.pick([a, b], now: now, dismissed: [])
        #expect(result.main == b)
        #expect(result.rest == [a])
    }

    // 6
    @Test func thenTheSourceOrderDecides() {
        let a = hint("A", 90, source: .recovery), b = hint("B", 90, source: .dailyAdvice)
        #expect(DayHintPicker.pick([a, b], now: now, dismissed: []).main == b)
    }

    // 7
    @Test func theInputOrderDoesNotMatter() {
        let hints = [hint("A", 90, source: .recovery), hint("B", 90), hint("C", 95), hint("D", 10)]
        let forward = DayHintPicker.pick(hints, now: now, dismissed: [])
        let backward = DayHintPicker.pick(hints.reversed(), now: now, dismissed: [])
        #expect(forward.main == backward.main)
        #expect(forward.rest == backward.rest)
    }

    // 8
    @Test func noAdviceIsNoHint() {
        #expect(DayHint.from(.none, now: now).isEmpty)
    }

    // 9
    @Test func overGoalBecomesOneHint() {
        let hints = DayHint.from(.overGoal(percent: 120), now: now)
        #expect(hints.count == 1)
        #expect(hints.first?.urgency == 95)
        #expect(hints.first?.source == .dailyAdvice)
    }

    // 10
    @Test func noRecoveryAdviceIsNoHint() {
        #expect(DayHint.from(recovery: nil, now: now).isEmpty)
    }

    // 11
    @Test func aRefeedBecomesOneHintThatMovesTheRefeed() {
        let hints = DayHint.from(recovery: (.refeed, "Пора рефид"), now: now)
        #expect(hints.count == 1)
        #expect(hints.first?.urgency == 93)
        #expect(hints.first?.action == .moveRefeedToday)
    }

    // 12
    @Test func theSameAdviceOnTwoDaysHasTwoIds() {
        let tomorrow = now.addingTimeInterval(86_400)
        let today = DayHint.from(.overGoal(percent: 120), now: now).first?.id
        let next = DayHint.from(.overGoal(percent: 120), now: tomorrow).first?.id
        #expect(today != nil)
        #expect(today != next)
    }

    // MARK: Порядок владельца

    /// Плато и диет-брейк важнее перебора: перебор бывает сознательным.
    @Test func aPlateauAndADietBreakOutrankAnOverGoal() {
        let over = DayHint.from(.overGoal(percent: 120), now: now)
        let plateau = DayHint.from(.weightPlateau(days: 14), now: now)
        let dietBreak = DayHint.from(recovery: (.dietBreak, "Пора перерыв"), now: now)
        let result = DayHintPicker.pick(over + plateau + dietBreak, now: now, dismissed: [])
        #expect(result.main?.source == .recovery)
        #expect(result.rest.first?.urgency == DayHint.Urgency.plateau)
    }

    /// И в самом совете дня: из перебора и плато он выбирает плато, иначе
    /// плато не доходило бы до общей очереди вовсе.
    @Test func theDailyAdviceRanksAPlateauAboveAnOverGoal() {
        #expect(DailyAdvice.weightPlateau(days: 14).priority > DailyAdvice.overGoal(percent: 120).priority)
    }

    /// Пост (и сам день, и напоминание за 1–3 дня) и копия — выше перебора.
    @Test func fastingAndBackupOutrankAnOverGoal() {
        #expect(DayHint.Urgency.fastingSoon > DayHint.Urgency.overGoal)
        #expect(DayHint.Urgency.fastingToday > DayHint.Urgency.overGoal)
        #expect(DayHint.Urgency.backup > DayHint.Urgency.fastingToday)
    }

    /// «Пора ужинать» не прячется за «нормой набрана»: обычный совет дня
    /// сохраняет прежний порядок ниже перебора.
    @Test func ordinaryAdviceKeepsItsOrderBelowOverGoal() {
        let p = { (a: DailyAdvice) in a.priority }
        #expect(p(.overGoal(percent: 120)) > p(.notLogging(days: 3)))
        #expect(p(.notLogging(days: 3)) > p(.noDinnerYet))
        #expect(p(.noDinnerYet) > p(.underGoal(percent: 50, remaining: 900)))
        #expect(p(.underGoal(percent: 50, remaining: 900)) > p(.onTarget))
    }

    // MARK: Смахивание и очередь

    /// Смахнутая уходит, на её место встаёт следующая по срочности.
    @Test func aSwipedHintGivesWayToTheNext() {
        let backup = DayHint.backup(now: now)
        let review = DayHint.weeklyReview(proposal: 2400, now: now)
        let all = backup + review
        #expect(DayHintPicker.pick(all, now: now, dismissed: []).main?.source == .backup)
        let after = DayHintPicker.pick(all, now: now, dismissed: [backup[0].id])
        #expect(after.main?.source == .weeklyReview)
    }

    /// Смахнутая до конца дня: назавтра она снова в очереди.
    @Test func aSwipeLastsUntilTomorrow() {
        let defaults = TestDefaults.make()
        let store = DismissedHints(defaults: defaults)
        let id = DayHint.backup(now: now)[0].id
        store.dismiss(id, now: now)
        #expect(store.load(now: now).contains(id))
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(store.load(now: tomorrow).isEmpty)
        #expect(DayHint.backup(now: tomorrow)[0].id != id)
    }

    /// Новое предложение нормы — новая подсказка, даже если прежнюю смахнули.
    @Test func aNewWeeklyProposalIsANewHint() {
        #expect(DayHint.weeklyReview(proposal: 2400, now: now)[0].id
                != DayHint.weeklyReview(proposal: 2300, now: now)[0].id)
    }

    /// Пост в сам день важнее, чем за день до него, и оба важнее перебора.
    @Test func fastingTodayOutranksFastingSoon() {
        let today = DayHint.fasting(daysUntil: 0, kind: "water", now: now)
        let soon = DayHint.fasting(daysUntil: 2, kind: "water", now: now)
        let over = DayHint.from(.overGoal(percent: 120), now: now)
        #expect(today.first!.urgency > soon.first!.urgency)
        #expect(DayHintPicker.pick(soon + over, now: now, dismissed: []).main?.source == .fasting)
        #expect(DayHint.fasting(daysUntil: 5, kind: "water", now: now).isEmpty)
    }
}
