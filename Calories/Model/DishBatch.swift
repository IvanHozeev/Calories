import Foundation

/// Партия: одна сваренная кастрюля.
///
/// До сих пор «блюдо» было и рецептом, и кастрюлей разом — отсюда и
/// захламлённая галерея: рецепт живёт вечно, а кастрюля кончается в четверг.
/// Партия отделяет одно от другого: рецепт повторяют, партию съедают.
///
/// Из этого разделения само собой выпадает всё, ради чего оно затевалось:
/// остаток без арифметики в уме, прогноз «хватит до четверга», напоминание
/// доесть, пока не испортилось, и напоминание приготовить, когда кончается, —
/// то самое планирование еды, которое ждало своей очереди с сентября.
///
/// Здесь только правила. Хранение — в модели, списание — в сторе.
enum DishBatch {

    /// Сколько дней готовое блюдо считается съедобным.
    ///
    /// Четыре: столько держится варёное мясо и крупы в холодильнике при
    /// обычной температуре. Это не срок годности из учебника, а та граница,
    /// после которой стоит понюхать, прежде чем есть, — и приложение честнее
    /// скажет об этом заранее, чем промолчит.
    static let shelfLifeDays = 4

    /// За сколько дней до конца предупреждать, что пора готовить снова.
    ///
    /// Один: напоминание «приготовь сегодня» за три дня до того, как еда
    /// кончится, человек забудет, а в день, когда кастрюля пуста, оно уже
    /// бесполезно — обед нужен сейчас.
    static let cookAheadDays = 1

    /// Состояние партии — то, что показывают человеку.
    struct State: Equatable {
        /// Сколько осталось, граммов.
        let remainingGrams: Double
        /// Сколько это порций по умолчанию. nil — порция не задана.
        let remainingServings: Double?
        /// Сколько съедают в день, граммов. nil — ещё не по чему судить.
        let dailyPace: Double?
        /// Когда кончится при таком темпе. nil — темп неизвестен.
        let runsOutOn: Date?
        /// Последний день, когда это ещё стоит есть.
        let goodUntil: Date
        /// Пустая партия: доедена или списана.
        var isFinished: Bool { remainingGrams < 1 }
    }

    /// Собрать состояние партии.
    ///
    /// - Parameters:
    ///   - cookedAt: когда готовили.
    ///   - totalGrams: сколько сварено.
    ///   - eatenGrams: сколько уже съедено по дневнику.
    ///   - servingGrams: порция по умолчанию, если задана.
    static func state(cookedAt: Date, totalGrams: Double, eatenGrams: Double,
                      servingGrams: Double?, now: Date = Date(),
                      calendar: Calendar = .current) -> State {
        let remaining = max(0, totalGrams - eatenGrams)
        let servings = servingGrams.flatMap { $0 > 0 ? remaining / $0 : nil }

        // Темп — по календарным суткам, а не по часам от момента готовки.
        //
        // Партия, сваренная час назад и початая на треть, не съедается «по
        // трети в час»: день готовки считается за первый, он уже идёт. А
        // считать от самого часа готовки значит получать разный темп у одной
        // и той же кастрюли в зависимости от того, когда человек открыл
        // приложение — утром или вечером.
        let cookedDay = calendar.startOfDay(for: cookedAt)
        let today = calendar.startOfDay(for: now)
        let days = max(1, (calendar.dateComponents([.day], from: cookedDay, to: today).day ?? 0) + 1)
        let pace = eatenGrams > 0 ? eatenGrams / Double(days) : nil
        let runsOut = pace.flatMap { pace -> Date? in
            guard pace > 0, remaining > 0 else { return nil }
            let daysLeft = Int((remaining / pace).rounded(.up))
            return calendar.date(byAdding: .day, value: daysLeft, to: now)
        }

        let goodUntil = calendar.date(byAdding: .day, value: shelfLifeDays, to: cookedAt) ?? cookedAt
        return State(remainingGrams: remaining,
                     remainingServings: servings,
                     dailyPace: pace,
                     runsOutOn: runsOut,
                     goodUntil: goodUntil)
    }

    /// Что сказать про партию — или ничего, когда говорить не о чем.
    enum Advice: Equatable {
        /// Срок вышел: дальше это уже не еда.
        case spoiled
        /// Последний день — лучше доесть сегодня.
        case eatToday(servingsLeft: Double?)
        /// Кончается: пора готовить снова.
        case cookAgain(runsOutOn: Date)
    }

    static func advice(_ state: State, now: Date = Date(),
                       calendar: Calendar = .current) -> Advice? {
        guard !state.isFinished else { return nil }

        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: state.goodUntil)

        // Срок важнее запаса: еда, которую уже нельзя есть, не нуждается в
        // прогнозе, когда она кончится.
        if today > lastDay { return .spoiled }
        if today == lastDay { return .eatToday(servingsLeft: state.remainingServings) }

        guard let runsOut = state.runsOutOn else { return nil }
        let daysLeft = calendar.dateComponents([.day], from: today,
                                               to: calendar.startOfDay(for: runsOut)).day ?? 0
        return daysLeft <= cookAheadDays ? .cookAgain(runsOutOn: runsOut) : nil
    }
}
