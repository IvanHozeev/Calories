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

    /// Из каких приёмов складывается день при заданном их числе.
    ///
    /// Названия те же, что у групп дневника, — иначе «приём 4 из 5» в
    /// расписании и «Полдник» в записях выглядят как разные вещи.
    ///
    /// Порядок продуман, а не выведен из чисел: крупные приёмы ставятся
    /// первыми, промежуточные вставляются между ними. Пять приёмов — это
    /// завтрак, обед и ужин плюс второй завтрак и полдник, а не пять равных
    /// перекусов.
    static func periods(count: Int) -> [MealPeriod] {
        switch min(max(count, allowedCounts.lowerBound), allowedCounts.upperBound) {
        case 2:  return [.breakfast, .dinner]
        case 3:  return [.breakfast, .lunch, .dinner]
        case 4:  return [.breakfast, .lunch, .afternoonSnack, .dinner]
        case 5:  return [.breakfast, .secondBreakfast, .lunch, .afternoonSnack, .dinner]
        default: return [.breakfast, .secondBreakfast, .lunch, .afternoonSnack, .dinner, .secondDinner]
        }
    }

    /// Насколько приём крупный.
    ///
    /// Едят не поровну: завтрак, обед и ужин — основа дня, между ними
    /// перекусы. Раньше норма делилась на равные части, и «полдник на 550
    /// ккал» выглядел как полноценный обед, которого никто не ест.
    ///
    /// Шесть десятых, а не половина: перекус должен остаться едой, а не
    /// символическим яблоком, иначе его просто съедят «сверх» расписания.
    static func weight(of period: MealPeriod) -> Double {
        switch period {
        case .breakfast, .lunch, .dinner: return 1
        default:                          return 0.6
        }
    }

    struct Slot: Identifiable, Equatable {
        let index: Int
        /// Какой это приём: завтрак, обед, полдник…
        let period: MealPeriod
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
    /// Раньше какого часа еда считается не завтраком, а хвостом вчерашнего дня.
    ///
    /// По этой границе расписание решает, вставать ему раньше или нет: поел в
    /// пять утра — значит день начался в пять; поел в полпервого ночи — это
    /// ночной перекус, а не подъём, и двигать по нему весь день нельзя.
    static let earliestWakeHour = 4

    static func slots(_ input: Input) -> [Slot] {
        let calendar = Calendar.current
        // День начинается по факту, а не по настройке: если человек встал в
        // пять и поел, расписание встаёт вместе с ним. Узнать время будильника
        // приложение не может — в iOS такого доступа нет, — но первая еда дня
        // говорит о подъёме не хуже.
        let dayStart = calendar.startOfDay(for: input.wake)
        let earliest = calendar.date(byAdding: .hour, value: earliestWakeHour, to: dayStart) ?? dayStart
        let firstMealToday = input.entries.map(\.date).filter { $0 >= earliest }.min()
        let wake = min(input.wake, firstMealToday ?? input.wake)

        let times = times(wake: wake, sleep: input.sleep, count: input.mealCount)
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

        // Крайние окна дотягиваются до краёв суток: иначе съеденное до первого
        // окна и после последнего не попадало никуда. Калории при этом из
        // остатка вычитались — то есть еда была, а в расписании её не было, и
        // первый приём показывал «съедено 0» после настоящего завтрака.
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        bounds[0].0 = min(bounds[0].0, dayStart)
        bounds[bounds.count - 1].1 = max(bounds[bounds.count - 1].1, dayEnd)

        let consumed = bounds.map { bound in
            input.entries.filter { $0.date >= bound.0 && $0.date < bound.1 }
                .reduce(0) { $0 + $1.calories }
        }

        // Съеденное за день считается целиком — теперь оно всё лежит внутри
        // окон, потому что крайние дотянуты до краёв суток.
        let total = input.entries.reduce(0) { $0 + $1.calories }
        var remaining = max(0, input.dailyGoal - total)

        var result: [Slot] = []
        // Впереди столько окон, на сколько делить остаток.
        let periods = periods(count: input.mealCount)
        let upcoming = bounds.enumerated().filter { $0.element.1 > input.now }.map(\.offset)
        // Остаток делится не поровну, а по весу приёма: на обед отводится
        // больше, чем на полдник.
        let weightAhead = upcoming.reduce(0.0) { $0 + weight(of: periods[$1]) }
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
                let share = weightAhead > 0
                    ? Int((Double(remaining) * weight(of: periods[index]) / weightAhead).rounded())
                    : 0
                calories = isLastUpcoming ? max(0, remaining - handed) : share
                handed += calories
            } else {
                calories = eaten
            }
            result.append(Slot(index: index, period: periods[index], start: bound.0, end: bound.1,
                               calories: calories, consumed: eaten, state: state))
        }
        remaining -= handed
        return result
    }

    /// Ближайшее окно, ради которого стоит будить напоминание.
    static func nextSlot(_ slots: [Slot], now: Date) -> Slot? {
        slots.first { $0.state == .current } ?? slots.first { $0.start > now }
    }
}
