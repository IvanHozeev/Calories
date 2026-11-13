import Testing
import Foundation
import SwiftData
@testable import Calories

/// Приёмка ТЗ-4: даты постов и праздников (пояс Asia/Jerusalem).
///
/// Даты получены от системного календаря и сверены по независимым
/// источникам (Hebcal, Wikipedia): пост Эстер 2028 — чт 9 марта, 9 ава 2029 —
/// вс 22 июля, Йом Кипур 2028 — сб 30 сентября без переноса.
struct JewishCalendarTests {
    private let zone = TimeZone(identifier: "Asia/Jerusalem")!

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        gregorian.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Первое событие с ключом в григорианском году.
    private func event(_ key: String, in year: Int) -> JewishCalendar.Event? {
        JewishCalendar.events(from: date(year, 1, 1), to: date(year, 12, 31), timeZone: zone)
            .first { $0.key == key }
    }

    private func day(_ key: String, in year: Int) -> Date? { event(key, in: year)?.day }

    // 1
    @Test func yomKippur5787() {
        #expect(day("yomKippur", in: 2026) == date(2026, 9, 21))
        #expect(event("yomKippur", in: 2026)?.startsEveningBefore == true)
        #expect(event("yomKippur", in: 2026)?.kind == .majorFast)
    }

    // 2
    @Test func yomKippur5788() { #expect(day("yomKippur", in: 2027) == date(2027, 10, 11)) }

    // 3
    @Test func yomKippurOnShabbatIsNotMoved() { #expect(day("yomKippur", in: 2028) == date(2028, 9, 30)) }

    // 4
    @Test func tishaBeAv5786() { #expect(day("tishaBeAv", in: 2026) == date(2026, 7, 23)) }

    // 5
    @Test func tishaBeAv5787() { #expect(day("tishaBeAv", in: 2027) == date(2027, 8, 12)) }

    // 6
    @Test func tishaBeAvOnShabbatMovesToSunday() { #expect(day("tishaBeAv", in: 2029) == date(2029, 7, 22)) }

    // 7
    @Test func tammuz17OnShabbatMovesToSunday() { #expect(day("tammuz17", in: 2029) == date(2029, 7, 1)) }

    // 8
    @Test func gedaliahOnShabbatMovesToSunday() { #expect(day("gedaliah", in: 2028) == date(2028, 9, 24)) }

    // 9
    @Test func estherOnShabbatMovesToThursday() { #expect(day("esther", in: 2028) == date(2028, 3, 9)) }

    // 10
    @Test func estherInALeapYearIsInAdarII() {
        #expect(day("esther", in: 2027) == date(2027, 3, 22))
        #expect(event("esther", in: 2027)?.kind == .minorFast)
        #expect(event("esther", in: 2027)?.startsEveningBefore == false)
    }

    // 11
    @Test func purim5787() { #expect(day("purim", in: 2027) == date(2027, 3, 23)) }

    // 12
    @Test func pesach5787() { #expect(day("pesach", in: 2027) == date(2027, 4, 22)) }

    // 13
    @Test func shavuot5787() { #expect(day("shavuot", in: 2027) == date(2027, 6, 11)) }

    // 14
    @Test func tevet10of5787() { #expect(day("tevet10", in: 2026) == date(2026, 12, 20)) }

    // 15
    @Test func aQuietStretchHasNoEvents() {
        #expect(JewishCalendar.events(from: date(2026, 11, 12), to: date(2026, 11, 30), timeZone: zone).isEmpty)
    }

    /// Рош ха-Шана — оба дня, как и в Израиле (решение владельца).
    @Test func roshHashanaIsTwoDays() {
        let days = JewishCalendar.events(from: date(2026, 9, 1), to: date(2026, 9, 30), timeZone: zone)
            .filter { $0.title == JewishCalendar.Event(key: "roshHashana", kind: .feast, day: Date(),
                                                       startsEveningBefore: true).title }
            .map(\.day)
        #expect(days == [date(2026, 9, 12), date(2026, 9, 13)])
    }
}

/// Подсказки календаря: строки 16–18 ТЗ-4.
struct JewishCalendarHintTests {
    private let zone = TimeZone(identifier: "Asia/Jerusalem")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    /// За три дня до Йом Кипура 2026 (пн 21 сентября).
    private var beforeYomKippur: Date { date(2026, 9, 18) }
    private var events: [JewishCalendar.Event] {
        JewishCalendar.events(from: beforeYomKippur, to: date(2026, 9, 25), timeZone: zone)
    }

    @Test func threeDaysBeforeAFastItIsOffered() {
        let hints = DayHint.calendar(events, now: beforeYomKippur, enabled: true,
                                     hasFast: { _ in false }, canMoveRefeed: { _ in false }, calendar: calendar)
        #expect(hints.contains { if case .markFast(let day) = $0.action { return day == date(2026, 9, 21, 0) } else { return false } })
    }

    /// За три дня до поста к подсказке — совет про кофе: снижать его надо
    /// постепенно, ещё до отметки поста.
    @Test func threeDaysAheadTheHintTalksAboutCoffee() {
        let hint = DayHint.calendar(events, now: beforeYomKippur, enabled: true,
                                    hasFast: { _ in false }, canMoveRefeed: { _ in false }, calendar: calendar).first
        #expect(hint?.detail != nil)
        #expect(hint?.detail == FastingAdvice.advice(for: .dry, daysBefore: 3).first?.text)
    }

    /// Накануне — уже совет про соль, а не про кофе.
    @Test func theDayBeforeTheHintTalksAboutSalt() {
        let eve = date(2026, 9, 20)
        let hint = DayHint.calendar(events, now: eve, enabled: true,
                                    hasFast: { _ in false }, canMoveRefeed: { _ in false }, calendar: calendar).first
        #expect(hint?.detail == FastingAdvice.advice(for: .dry, daysBefore: 1).first?.text)
        #expect(hint?.detail != FastingAdvice.advice(for: .dry, daysBefore: 3).first?.text)
    }

    // 16
    @Test func aDisabledCalendarOffersNothing() {
        let hints = DayHint.calendar(events, now: beforeYomKippur, enabled: false,
                                     hasFast: { _ in false }, canMoveRefeed: { _ in true }, calendar: calendar)
        #expect(hints.isEmpty)
    }

    // 17
    @Test func anAlreadyMarkedFastIsNotOfferedAgain() {
        let hints = DayHint.calendar(events, now: beforeYomKippur, enabled: true,
                                     hasFast: { _ in true }, canMoveRefeed: { _ in false }, calendar: calendar)
        #expect(!hints.contains { if case .markFast = $0.action { return true } else { return false } })
    }

    // 18
    @Test func aRefeedAlreadyMovedIsNotOfferedAgain() {
        let feastWeek = date(2027, 4, 19)         // пн перед Песахом (чт 22 апреля)
        let feasts = JewishCalendar.events(from: feastWeek, to: date(2027, 4, 25), timeZone: zone)
        let moved = DayHint.calendar(feasts, now: feastWeek, enabled: true,
                                     hasFast: { _ in false }, canMoveRefeed: { _ in false }, calendar: calendar)
        #expect(moved.isEmpty)
        let open = DayHint.calendar(feasts, now: feastWeek, enabled: true,
                                    hasFast: { _ in false }, canMoveRefeed: { _ in true }, calendar: calendar)
        #expect(open.contains { if case .moveRefeed(let day) = $0.action { return day == date(2027, 4, 22, 0) } else { return false } })
    }

    /// Пост отмечается раньше перебора: срочность — как у поста через 1–3 дня.
    @Test func aFastOfferOutranksAnOverGoal() {
        let hints = DayHint.calendar(events, now: beforeYomKippur, enabled: true,
                                     hasFast: { _ in false }, canMoveRefeed: { _ in false }, calendar: calendar)
        #expect(hints.first!.urgency > DayHint.Urgency.overGoal)
    }
}

/// Отметка поста из календаря в дневнике.
@MainActor
@Suite(.serialized)
struct CalendarFastMarkingTests {
    private let container: ModelContainer
    private let store: CalorieStore
    private let zone = TimeZone(identifier: "Asia/Jerusalem")!

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Йом Кипур — сухой, с вечера накануне.
    @Test func aMajorFastIsDryAndStartsTheEveningBefore() throws {
        let fast = try #require(store.markCalendarFast(on: day(2026, 9, 21), timeZone: zone))
        #expect(fast.kind == .dry)
        let start = try #require(fast.startedAt)
        #expect(Calendar.current.isDate(start, inSameDayAs: day(2026, 9, 20)))
    }

    /// 10 тевета — «до темноты», без поднятой нормы накануне.
    @Test func aMinorFastIsDaytimeWithoutAnEveBoost() throws {
        let fast = try #require(store.markCalendarFast(on: day(2026, 12, 20), timeZone: zone))
        #expect(fast.kind == .daytime)
        #expect(!store.isFastEve(day(2026, 12, 19)))
    }

    /// Не пост — ничего не отмечается.
    @Test func anOrdinaryDayIsNotMarked() {
        #expect(store.markCalendarFast(on: day(2026, 11, 20), timeZone: zone) == nil)
        #expect(store.fastDays.isEmpty)
    }
}
