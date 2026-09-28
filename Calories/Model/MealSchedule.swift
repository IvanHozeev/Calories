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
    /// Часы основных приёмов — те же, что у всех.
    ///
    /// Завтрак в восемь, обед в час, ужин в семь. Это середины тех окон,
    /// которые советует Роспотребнадзор: завтрак с семи до девяти, обед с
    /// часа до двух, ужин с шести до восьми и не позже чем за два-три часа до
    /// сна.
    ///
    /// Раньше время считалось от подъёма — сорок пять минут после него и час
    /// до отбоя, — и у вставшего в пять завтрак приходился на без четверти
    /// шесть, а обед на десять утра. Формально стройно, на деле бесполезно:
    /// завтрак у людей в восемь, а не «через сорок пять минут после того, как
    /// открыл глаза».
    static let breakfastHour = 8
    static let lunchHour = 13
    static let dinnerHour = 19
    /// За сколько до отбоя последний приём.
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
        /// Время самого приёма — середина окна по расписанию.
        ///
        /// Раньше на экран шли края окна, и человек видел «завтрак в 7:00» при
        /// подъёме в семь и «ужин в 23:00» при отбое в одиннадцать: то есть еду
        /// ровно когда открыл глаза и ровно перед сном. Сорок пять минут после
        /// подъёма и час до отбоя в расчёте были всегда — просто не доходили до
        /// экрана. Окно и приём — разные вещи: по окну решают, куда засчитать
        /// съеденное, а человеку показывают приём.
        let time: Date
        /// Сколько калорий на него отведено сейчас — с учётом уже съеденного
        /// и пропущенных окон.
        let calories: Int
        /// Сколько отводилось по расписанию — доля дневной нормы по весу
        /// приёма, без оглядки на съеденное.
        ///
        /// Нужно, чтобы закрытое окно могло сказать не только «съедено 900»,
        /// но и «на 200 больше, чем планировалось»: в `calories` у прошедшего
        /// окна лежит факт, и план оттуда уже не достать.
        let planned: Int
        /// Съедено внутри окна.
        let consumed: Int
        let state: State

        var id: Int { index }

        /// Насколько съедено больше, чем отводилось. Ноль — уложился.
        var overeaten: Int { max(0, consumed - planned) }

        enum State: String, Equatable {
            /// Окно ещё впереди.
            case upcoming
            /// Идёт прямо сейчас и ещё не съеден.
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

    /// Времена приёмов на этот день.
    ///
    /// Основные стоят на своих часах и не двигаются. Промежуточные ровно
    /// посередине между соседями: второй завтрак между завтраком и обедом,
    /// полдник между обедом и ужином, второй ужин между ужином и отбоем.
    static func times(wake: Date, sleep: Date, count: Int) -> [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: wake)
        func at(_ hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        }
        let breakfast = at(breakfastHour)
        let lunch = at(lunchHour)
        let dinner = at(dinnerHour)
        // Отбой — единственное, что человек задаёт сам: второй ужин вешается
        // между ужином и сном. Легли за полночь — переносим на завтра.
        var bedtime = calendar.date(bySettingHour: calendar.component(.hour, from: sleep),
                                    minute: calendar.component(.minute, from: sleep),
                                    second: 0, of: day) ?? dinner
        if bedtime <= dinner { bedtime = bedtime.addingTimeInterval(86_400) }
        let lastAllowed = bedtime.addingTimeInterval(-lastMealBeforeSleep)

        return periods(count: count).map { period in
            switch period {
            case .breakfast:       return breakfast
            case .secondBreakfast: return middle(breakfast, lunch)
            case .lunch:           return lunch
            case .afternoonSnack:  return middle(lunch, dinner)
            case .dinner:          return dinner
            default:               return middle(dinner, lastAllowed)
            }
        }
    }

    private static func middle(_ from: Date, _ to: Date) -> Date {
        from.addingTimeInterval(to.timeIntervalSince(from) / 2)
    }

    /// Расписание с учётом съеденного и текущего времени.
    ///
    /// Калории пропущенных окон не сгорают и не копятся молча: они сразу же
    /// раскладываются по оставшимся приёмам, и человек видит новую цифру, а не
    /// узнаёт вечером, что «должен» ещё полторы тысячи.

    /// Можно ли считать день закрытым.
    ///
    /// «День закрыт» при недоеденных пятистах килокалориях — это не итог, а
    /// ошибка: приёмы кончились, а еда нет. Допуск тот же, что у дневной
    /// нормы: два процента, но не меньше полусотни — попасть в норму точнее
    /// невозможно, и требовать этого незачем.
    static func isDayClosed(remaining: Int, goal: Int) -> Bool {
        remaining <= max(50, Int((Double(goal) * 0.02).rounded()))
    }

    /// Сколько нужно съесть, чтобы приём считался закрытым.
    ///
    /// Не ровно столько, сколько отведено: попасть в план до килокалории
    /// невозможно, и приём на 690 из 700 закрыт ничуть не меньше. Допуск тот
    /// же по смыслу, что у дневной нормы, — процент от плана, но не меньше
    /// полусотни, иначе у маленького полдника он вырождался бы в ноль.
    static func closingCalories(_ planned: Int) -> Int {
        max(0, planned - max(50, Int((Double(planned) * 0.05).rounded())))
    }

    static func slots(_ input: Input) -> [Slot] {
        let wake = input.wake
        let times = times(wake: wake, sleep: input.sleep, count: input.mealCount)
        guard !times.isEmpty, input.dailyGoal > 0 else { return [] }

        // Границы окон — середины между соседними приёмами.
        var bounds: [(Date, Date)] = []
        for (index, time) in times.enumerated() {
            // Границы окон — середины между соседними приёмами, а у крайних
            // зеркально: столько же до первого, сколько до его соседа.
            let start = index == 0
                ? time.addingTimeInterval(-(times.count > 1
                                            ? times[1].timeIntervalSince(time) / 2
                                            : 3600))
                : times[index - 1].addingTimeInterval(times[index].timeIntervalSince(times[index - 1]) / 2)
            let end = index == times.count - 1
                ? time.addingTimeInterval(lastMealBeforeSleep)
                : time.addingTimeInterval(times[index + 1].timeIntervalSince(time) / 2)
            bounds.append((start, end))
        }

        // Окна стоят там, где им место: первое — от подъёма, последнее
        // кончается за час до отбоя. Растягивать их до краёв суток нельзя:
        // «завтрак с 00:00» — это не завтрак, а строка, в которую свалили
        // всё подряд.
        let consumed = bounds.map { bound in
            input.entries.filter { $0.date >= bound.0 && $0.date < bound.1 }
                .reduce(0) { $0 + $1.calories }
        }

        let total = input.entries.reduce(0) { $0 + $1.calories }
        // Съеденное мимо окон — до подъёма, после отбоя, между приёмами —
        // никуда не пропадает: оно идёт отдельной строкой «Перекус» и
        // считается за день наравне с остальным.
        let outside = total - consumed.reduce(0, +)
        let remaining = max(0, input.dailyGoal - total)

        var result: [Slot] = []
        // Впереди столько окон, на сколько делить остаток.
        let periods = periods(count: input.mealCount)
        // План на окно — доля дневной нормы по весу приёма. Считается один
        // раз и не зависит от того, сколько уже съедено: иначе «планировалось»
        // менялось бы по ходу дня вслед за фактом.
        let totalWeight = periods.reduce(0.0) { $0 + weight(of: $1) }
        let planned = periods.map { period in
            totalWeight > 0
                ? Int((Double(input.dailyGoal) * weight(of: period) / totalWeight).rounded())
                : 0
        }
        // Делим остаток между теми, до кого ещё не дошли: съеденное окно в
        // дележе не участвует, даже если его время ещё не кончилось. Иначе
        // позавтракавший видел бы, что на завтрак ему «осталось» ещё шестьсот.
        let upcoming = bounds.enumerated()
            .filter { $0.element.1 > input.now && consumed[$0.offset] < closingCalories(planned[$0.offset]) }
            .map(\.offset)
        // Начатый приём доедают, а не начинают заново.
        //
        // Ему отводится его же недоеденный кусок: съел 380 из 558 — осталось
        // 178. Раньше он попадал в общий делёж и получал свежую полную долю
        // от остатка дня, то есть приложение звало съесть всю порцию ещё раз.
        var leftovers: [Int: Int] = [:]
        for index in upcoming where consumed[index] > 0 {
            leftovers[index] = max(0, planned[index] - consumed[index])
        }
        // Остальное делится не поровну, а по весу приёма: на обед отводится
        // больше, чем на полдник.
        let sharing = upcoming.filter { leftovers[$0] == nil }
        let weightAhead = sharing.reduce(0.0) { $0 + weight(of: periods[$1]) }
        var remainingToShare = max(0, remaining - leftovers.values.reduce(0, +))
        var handed = 0

        for (index, bound) in bounds.enumerated() {
            let eaten = consumed[index]
            // Приём закрывается съеденными калориями, а не самим фактом еды.
            //
            // Сначала закрывало любое попадание в окно: положил половину
            // порции — и приложение считало приём законченным, звало к
            // следующему, а недоеденное молча расходилось по остатку дня.
            // Теперь окно остаётся открытым, пока в нём есть что доесть.
            //
            // Кончилось время — закрываем как есть: съеденное остаётся
            // съеденным, недобор уходит следующим приёмам. А несъеденное
            // вовсе всё так же истекает: завтракать в обед никто не станет.
            let state: Slot.State
            if eaten >= closingCalories(planned[index]) {
                state = .done
            } else if bound.1 <= input.now {
                state = eaten > 0 ? .done : .missed
            } else if bound.0 <= input.now {
                state = .current
            } else {
                state = .upcoming
            }

            let calories: Int
            if let leftover = leftovers[index] {
                calories = leftover
            } else if sharing.contains(index) {
                // Последнему окну достаётся остаток от деления, чтобы сумма
                // сходилась с дневной нормой.
                let isLast = index == sharing.last
                let share = weightAhead > 0
                    ? Int((Double(remainingToShare) * weight(of: periods[index]) / weightAhead).rounded())
                    : 0
                calories = isLast ? max(0, remainingToShare - handed) : share
                handed += calories
            } else {
                calories = eaten
            }
            result.append(Slot(index: index, period: periods[index], start: bound.0, end: bound.1,
                               time: times[index], calories: calories, planned: planned[index],
                               consumed: eaten, state: state))
        }

        // Перекус — последней строкой и только если было что перекусить.
        // Своего времени у него нет: это не окно расписания, а всё, что мимо.
        if outside > 0 {
            // Планом перекус не предусмотрен вовсе — потому он и перекус.
            result.append(Slot(index: result.count, period: .nightSnack,
                               start: input.now, end: input.now, time: input.now,
                               calories: outside, planned: 0,
                               consumed: outside, state: .done))
        }
        return result
    }

    /// Ближайший приём: тот, до которого ещё не дошли.
    ///
    /// Съеденное окно пропускается, даже если его время ещё не кончилось, —
    /// приложение должно показывать то, что человек сделал, а не то, что
    /// написано в расписании. Поел в девять — и на экране сразу следующий
    /// приём со своим сроком, а не «время завтрака» до половины одиннадцатого.
    static func nextSlot(_ slots: [Slot], now: Date = Date()) -> Slot? {
        slots.first { $0.state == .current }
            ?? slots.first { $0.state == .upcoming && $0.period != .nightSnack }
    }
}

extension MealSchedule {
    /// Окна дня по настройкам расписания.
    ///
    /// `Input` собирался руками в пяти местах: на «Сегодня», в листе расписания,
    /// дважды в добавлении еды и в разборе дня. Правила за один день менялись
    /// трижды, и каждый раз приходилось вспоминать про все пять. Про подъём,
    /// отбой и число приёмов знают сами настройки — снаружи остаётся сказать,
    /// что съедено и сколько можно.
    static func slots(settings: MealScheduleSettings,
                      entries: [(date: Date, calories: Int)],
                      dailyGoal: Int,
                      now: Date = Date()) -> [Slot] {
        slots(.init(wake: settings.today(settings.wake, now: now),
                    sleep: settings.today(settings.sleep, now: now),
                    mealCount: settings.count,
                    dailyGoal: dailyGoal,
                    entries: entries,
                    now: now))
    }
}
