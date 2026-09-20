import Foundation

/// Расписание приёмов пищи на день: когда есть и сколько.
///
/// Норму делить по дню приходится в голове каждый день заново, и делится она
/// плохо: к вечеру выясняется, что половина калорий осталась на один приём.
/// Здесь день разложен заранее — от подъёма до отбоя, равными частями, — а
/// пропущенное окно не пропадает: его калории расходятся по тем приёмам,
/// которые ещё впереди.
///
/// Почему именно так расставлены края дня:
///
/// Первый приём — через 45 минут после подъёма. Точный момент ни на что не
/// влияет: синтез белка считает сутки, а не утро. Смысл в другом — дать время
/// проснуться и не привязывать еду к будильнику.
///
/// Последний — за час до отбоя. Белок перед сном работает: казеин за полчаса
/// до сна поднимает ночной синтез, и «после шести не есть» — миф. Час нужен
/// не желудку, а сну: плотная жирная еда впритык к отбою ухудшает его
/// качество, и лучше оставить запас.
///
/// Между краями — равные промежутки. Три-пять приёмов с разрывом в три-четыре
/// часа: столько раз белковая порция успевает отработать, и столько раз
/// человек реально готов есть.
enum MealSchedule {
    /// Через сколько после подъёма первый приём.
    static let firstMealAfterWake: TimeInterval = 45 * 60
    /// За сколько до отбоя последний.
    static let lastMealBeforeSleep: TimeInterval = 60 * 60
    /// Разумные границы числа приёмов.
    static let allowedCounts = 2...6

    struct Slot: Identifiable, Equatable {
        let index: Int
        /// Начало и конец окна, в котором этот приём ждут.
        let start: Date
        let end: Date
        /// Сколько калорий на него отведено сейчас — с учётом уже съеденного
        /// и пропущенных окон.
        let calories: Int
        /// Съедено внутри окна.
        let consumed: Int
        let state: State

        var id: Int { index }

        enum State: String, Equatable {
            /// Окно ещё впереди.
            case upcoming
            /// Идёт прямо сейчас.
            case current
            /// Закрыто и съедено.
            case done
            /// Закрыто и пропущено — калории ушли дальше по дню.
            case missed
        }
    }

    struct Input {
        let wake: Date
        let sleep: Date
        let mealCount: Int
        let dailyGoal: Int
        /// Что уже съедено за день: время и калории.
        let entries: [(date: Date, calories: Int)]
        let now: Date
    }

    /// Времена приёмов: от первого до последнего, равными промежутками.
    static func times(wake: Date, sleep: Date, count: Int) -> [Date] {
        let count = min(max(count, allowedCounts.lowerBound), allowedCounts.upperBound)
        let first = wake.addingTimeInterval(firstMealAfterWake)
        var last = sleep.addingTimeInterval(-lastMealBeforeSleep)
        // Сутки перевёрнуты (ложится за полночь) — переносим отбой на завтра.
        if last <= first { last = last.addingTimeInterval(86_400) }
        guard count > 1 else { return [first] }
        let step = last.timeIntervalSince(first) / Double(count - 1)
        return (0..<count).map { first.addingTimeInterval(step * Double($0)) }
    }

    /// Расписание с учётом съеденного и текущего времени.
    ///
    /// Калории пропущенных окон не сгорают и не копятся молча: они сразу же
    /// раскладываются по оставшимся приёмам, и человек видит новую цифру, а не
    /// узнаёт вечером, что «должен» ещё полторы тысячи.
    static func slots(_ input: Input) -> [Slot] {
        let times = times(wake: input.wake, sleep: input.sleep, count: input.mealCount)
        guard !times.isEmpty, input.dailyGoal > 0 else { return [] }

        // Границы окон — середины между соседними приёмами.
        var bounds: [(Date, Date)] = []
        for (index, time) in times.enumerated() {
            let start = index == 0
                ? time.addingTimeInterval(-firstMealAfterWake)
                : times[index - 1].addingTimeInterval(times[index].timeIntervalSince(times[index - 1]) / 2)
            let end = index == times.count - 1
                ? time.addingTimeInterval(lastMealBeforeSleep)
                : time.addingTimeInterval(times[index + 1].timeIntervalSince(time) / 2)
            bounds.append((start, end))
        }

        let consumed = bounds.map { bound in
            input.entries.filter { $0.date >= bound.0 && $0.date < bound.1 }
                .reduce(0) { $0 + $1.calories }
        }

        // Съеденное вне окон (ночью, до подъёма) всё равно считается за день:
        // иначе сумма по приёмам разойдётся с кольцом на «Сегодня».
        let inside = consumed.reduce(0, +)
        let total = input.entries.reduce(0) { $0 + $1.calories }
        var remaining = max(0, input.dailyGoal - total)
        let outside = total - inside

        var result: [Slot] = []
        // Впереди столько окон, на сколько делить остаток.
        let upcoming = bounds.enumerated().filter { $0.element.1 > input.now }.map(\.offset)
        let share = upcoming.isEmpty ? 0 : remaining / upcoming.count
        var handed = 0

        for (index, bound) in bounds.enumerated() {
            let eaten = consumed[index]
            let state: Slot.State
            if bound.1 <= input.now {
                state = eaten > 0 ? .done : .missed
            } else if bound.0 <= input.now {
                state = .current
            } else {
                state = .upcoming
            }

            let calories: Int
            if upcoming.contains(index) {
                // Последнему окну достаётся остаток от деления, чтобы сумма
                // сходилась с дневной нормой.
                let isLastUpcoming = index == upcoming.last
                calories = isLastUpcoming ? max(0, remaining - handed) : share
                handed += calories
            } else {
                calories = eaten
            }
            result.append(Slot(index: index, start: bound.0, end: bound.1,
                               calories: calories, consumed: eaten, state: state))
        }
        remaining -= handed
        _ = outside
        return result
    }

    /// Ближайшее окно, ради которого стоит будить напоминание.
    static func nextSlot(_ slots: [Slot], now: Date) -> Slot? {
        slots.first { $0.state == .current } ?? slots.first { $0.start > now }
    }
}
