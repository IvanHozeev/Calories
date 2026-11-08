import Testing
import Foundation
@testable import Calories

/// Итог недели: какие выводы появляются и каким тоном.
///
/// Проверяем идентификаторы строк и тон, а не сам текст: набор идёт на
/// английской локали, и сравнение с русским литералом провалилось бы на
/// ровном месте. Идентификатор при этом и есть смысл вывода — «средняя
/// норма выдержана» или «расход просел», — а формулировка к нему только
/// подпись.
///
/// До этих тестов файл был покрыт на ноль процентов, хотя считает он то,
/// ради чего человек в приложение и заходит раз в неделю.
struct WeekReviewTests {

    private func ids(_ input: WeekReview.Input) -> [String] {
        WeekReview.lines(input).map(\.id)
    }

    private func tone(_ input: WeekReview.Input, _ id: String) -> WeekReview.Line.Tone? {
        WeekReview.lines(input).first { $0.id == id }?.tone
    }

    /// Неделя без записей разбору не поддаётся, и сказать об этом надо
    /// прямо, а не выдавать семь выводов из пустоты.
    @Test
    func anEmptyWeekSaysSoAndStopsThere() {
        let lines = WeekReview.lines(WeekReview.Input(loggedDays: 0))
        #expect(lines.map(\.id) == ["empty"])
        #expect(lines.first?.tone == .info)
    }

    /// Решает среднее за неделю, а не каждый день по отдельности: три дня
    /// выше нормы и три ниже — это выдержанная неделя.
    @Test
    func theWeekIsJudgedByItsAverage() {
        let input = WeekReview.Input(
            eaten: [2300, 2700, 2300, 2700, 2300, 2700, 2500],
            goals: Array(repeating: 2500, count: 7),
            loggedDays: 7)
        #expect(tone(input, "intake-ok") == .good)
        #expect(!ids(input).contains("intake-over"))
    }

    /// Допуск — два процента, и граница должна считаться попаданием, а не
    /// промахом: иначе неделя, прожитая точнее некуда, объявляется неудачной.
    @Test
    func theEdgeOfTheToleranceStillCounts() {
        let goal = 2500
        let edge = Int((Double(goal) * (1 + WeekReview.tolerance)).rounded(.down))
        let inside = WeekReview.Input(eaten: Array(repeating: edge, count: 7),
                                      goals: Array(repeating: goal, count: 7),
                                      loggedDays: 7)
        #expect(tone(inside, "intake-ok") == .good)

        let outside = WeekReview.Input(eaten: Array(repeating: edge + 20, count: 7),
                                       goals: Array(repeating: goal, count: 7),
                                       loggedDays: 7)
        #expect(tone(outside, "intake-over") == .warning)
    }

    /// Перебор — предупреждение, недобор — нет.
    ///
    /// Недоесть не достижение, но и не беда: это сведение, а не выговор.
    @Test
    func overEatingWarnsAndUnderEatingOnlyInforms() {
        let over = WeekReview.Input(eaten: Array(repeating: 3000, count: 7),
                                    goals: Array(repeating: 2500, count: 7),
                                    loggedDays: 7)
        #expect(tone(over, "intake-over") == .warning)

        let under = WeekReview.Input(eaten: Array(repeating: 2000, count: 7),
                                     goals: Array(repeating: 2500, count: 7),
                                     loggedDays: 7)
        #expect(tone(under, "intake-under") == .info)
    }

    /// Неполный дневник обесценивает остальные выводы, и об этом говорится
    /// отдельной строкой — но только когда дней действительно мало.
    @Test
    func aThinDiaryIsCalledOut() {
        var input = WeekReview.Input(eaten: [2500], goals: [2500], loggedDays: 4)
        #expect(tone(input, "logging") == .warning)

        input.loggedDays = 5
        #expect(!ids(input).contains("logging"))
    }

    /// Вес сверяется с планом: дошли, идём медленнее, идём не туда.
    @Test
    func weightIsReadAgainstThePlan() {
        func week(_ change: Double, planned: Double?) -> WeekReview.Input {
            WeekReview.Input(loggedDays: 7, weightStart: 80,
                             weightEnd: 80 + change, plannedWeeklyKg: planned)
        }
        // План — минус полкило: сбросили столько же.
        #expect(tone(week(-0.5, planned: 0.5), "weight") == .good)
        // Сбросили втрое меньше плана — медленнее, но в ту сторону.
        #expect(tone(week(-0.15, planned: 0.5), "weight") == .info)
        // Вес пошёл вверх при плане вниз.
        #expect(tone(week(0.3, planned: 0.5), "weight") == .warning)
        // Без плана судить не о чем — просто называем число.
        #expect(tone(week(-0.4, planned: nil), "weight") == .info)
    }

    /// Расход упоминается, только когда он заметно сдвинулся: шум в
    /// полсотни килокалорий — не новость.
    @Test
    func expenditureIsMentionedOnlyWhenItMoved() {
        func week(from start: Double, to end: Double) -> WeekReview.Input {
            WeekReview.Input(loggedDays: 7, expenditureStart: start, expenditureEnd: end)
        }
        #expect(!ids(week(from: 2500, to: 2540)).contains("expenditure"))
        // Просел — это ответ тела на дефицит, и предупредить о нём надо.
        #expect(tone(week(from: 2500, to: 2400), "expenditure") == .warning)
        // Вырос — хорошая новость, но не повод хвалить: просто сведение.
        #expect(tone(week(from: 2500, to: 2600), "expenditure") == .info)
    }

    /// Сон меньше шести с половиной часов — предупреждение, больше — нет.
    @Test
    func shortSleepIsAWarning() {
        #expect(tone(WeekReview.Input(loggedDays: 7, sleepHours: 6.0), "sleep") == .warning)
        #expect(tone(WeekReview.Input(loggedDays: 7, sleepHours: 7.5), "sleep") == .good)
        // Нуля не бывает: это не «спал ноль», а «данных нет».
        #expect(!ids(WeekReview.Input(loggedDays: 7, sleepHours: 0)).contains("sleep"))
    }

    /// Пульс в покое говорит только тогда, когда вырос заметно.
    @Test
    func theRestingPulseSpeaksOnlyWhenItRose() {
        let quiet = WeekReview.Input(loggedDays: 7, restingPulse: 52,
                                     pulseRise: RestingPulse.notableRise - 1)
        #expect(!ids(quiet).contains("pulse"))

        let risen = WeekReview.Input(loggedDays: 7, restingPulse: 58,
                                     pulseRise: RestingPulse.notableRise)
        #expect(tone(risen, "pulse") == .warning)
    }

    /// Зал — вторая половина расхода, и о ней говорится, даже когда идёт
    /// разгрузка: вес на такой неделе часто стоит, и это не провал.
    @Test
    func theGymIsReportedIncludingADeload() {
        #expect(!ids(WeekReview.Input(loggedDays: 7, gymSets: 0)).contains("gym"))
        #expect(tone(WeekReview.Input(loggedDays: 7, gymSets: 42), "gym") == .info)
        #expect(tone(WeekReview.Input(loggedDays: 7, gymSets: 18, gymDeload: true), "gym") == .info)
    }

    /// Порядок строк — не случайность: сначала то, что решает, работает ли
    /// план, и только потом объяснения.
    @Test
    func intakeComesFirst() {
        let input = WeekReview.Input(
            eaten: Array(repeating: 3000, count: 7),
            goals: Array(repeating: 2500, count: 7),
            loggedDays: 3,
            weightStart: 80, weightEnd: 80.2, plannedWeeklyKg: 0.5,
            expenditureStart: 2500, expenditureEnd: 2300,
            sleepHours: 5.5, steps: 9000,
            restingPulse: 60, pulseRise: 5)
        #expect(ids(input).first == "intake-over")
        #expect(ids(input).contains("steps"))
    }

    /// Короткая форма отвечает теми же выводами, а не меньшим их числом:
    /// короче только формулировки.
    @Test
    func theBriefFormKeepsEveryConclusion() {
        let input = WeekReview.Input(
            eaten: Array(repeating: 2800, count: 7),
            goals: Array(repeating: 2500, count: 7),
            loggedDays: 7,
            weightStart: 80, weightEnd: 79.6, plannedWeeklyKg: 0.5,
            expenditureStart: 2500, expenditureEnd: 2380,
            sleepHours: 6.0, steps: 11000)
        let full = WeekReview.lines(input, brief: false)
        let brief = WeekReview.lines(input, brief: true)
        #expect(full.map(\.id) == brief.map(\.id))
        #expect(full.map(\.tone) == brief.map(\.tone))
        // И короче хотя бы в одной строке, иначе короткая форма ни к чему.
        #expect(zip(full, brief).contains { $0.text.count > $1.text.count })
    }
}
