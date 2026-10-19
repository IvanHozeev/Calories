import Foundation

/// План приёмов против того, как человек ест на самом деле.
///
/// Расписание до сих пор говорило в одну сторону: вот тебе завтрак в 7:45 на
/// 500 ккал. Выполняется оно или нет — приложение не замечало, хотя обе
/// половины у него под рукой: план считает `MealSchedule`, факт лежит в
/// дневнике. Сопоставление этих двух и есть то, из чего потом вырастают
/// осмысленные предложения — подвинуть приём, перераспределить калории,
/// не ставить тренировку в час, когда человек всё равно ещё не ел.
///
/// Здесь только счёт, без экрана и без хранилища: план за прошлый день
/// восстанавливается из тех же настроек расписания, что и за сегодня, а факт
/// — из записей того дня. Ничего копить отдельно не нужно, пока настройки не
/// меняются; когда появится история настроек, сюда придут готовые снимки, а
/// выводы останутся теми же.
enum MealAdherence {

    /// Один приём одного дня: что обещали и что вышло.
    struct Meal: Equatable {
        let period: MealPeriod
        /// Время приёма по расписанию.
        let plannedTime: Date
        /// Когда человек в это окно поел впервые. nil — окно пустое.
        let actualTime: Date?
        /// Сколько на него отводилось по расписанию.
        let plannedCalories: Int
        /// Сколько в него попало на самом деле.
        let eatenCalories: Int

        /// Насколько приём сдвинулся, в минутах. Плюс — позже плана.
        var shiftMinutes: Int? {
            guard let actualTime else { return nil }
            return Int((actualTime.timeIntervalSince(plannedTime) / 60).rounded())
        }

        /// Во сколько раз съедено больше плана. nil — плана не было.
        var caloriesRatio: Double? {
            guard plannedCalories > 0, actualTime != nil else { return nil }
            return Double(eatenCalories) / Double(plannedCalories)
        }

        /// Окно прошло пустым. Не то же, что «съел мало»: пропуск — про
        /// режим, недобор — про порцию, и мешать их в одну кучу нельзя.
        var skipped: Bool { actualTime == nil }
    }

    /// Один день целиком.
    struct Day: Equatable {
        let date: Date
        let meals: [Meal]
    }

    /// Привычка по одному приёму, собранная за несколько дней.
    struct Habit: Equatable, Identifiable {
        let period: MealPeriod
        /// По скольким дням посчитано — без этого числа вывод читать нельзя.
        let days: Int
        /// Медиана сдвига, минуты. Плюс — человек стабильно ест позже плана.
        let shiftMinutes: Int
        /// Медиана отношения «съедено / план».
        let caloriesRatio: Double
        /// В скольких днях окно осталось пустым.
        let skippedDays: Int

        var id: String { period.rawValue }
    }

    /// Сколько дней нужно, чтобы считать это привычкой, а не случайностью.
    ///
    /// Пять: четыре рабочих дня и выходной. Меньше — и один раз проспанный
    /// завтрак начинает двигать расписание; больше — и приложение молчит
    /// почти месяц, пока человек каждый день видит, что план врёт.
    static let minimumDays = 5

    /// Сдвиг, который уже стоит показывать. Четверть часа человек не заметит,
    /// а переставлять ради неё расписание — суета.
    static let noticeableShiftMinutes = 20

    /// Отклонение порции, после которого план перестаёт быть планом.
    static let noticeableRatio = 0.25

    // MARK: - Сопоставление

    /// Разложить один день: окна расписания против записей дневника.
    ///
    /// - Parameters:
    ///   - slots: окна этого дня, как их посчитал `MealSchedule`.
    ///   - entries: записи того же дня — время и калории.
    static func day(_ date: Date,
                    slots: [MealSchedule.Slot],
                    entries: [(date: Date, calories: Int)]) -> Day {
        let meals = slots.map { slot -> Meal in
            // Окно забирает то, что попало в его границы. Та же граница, по
            // которой расписание считает съеденное, — иначе план и факт
            // разошлись бы в приложении, а не в жизни.
            let inside = entries
                .filter { $0.date >= slot.start && $0.date < slot.end }
                .sorted { $0.date < $1.date }
            return Meal(period: slot.period,
                        plannedTime: slot.time,
                        actualTime: inside.first?.date,
                        plannedCalories: slot.planned,
                        eatenCalories: inside.reduce(0) { $0 + $1.calories })
        }
        return Day(date: date, meals: meals)
    }

    // MARK: - Выводы

    /// Что из накопленного следует по каждому приёму.
    ///
    /// Медиана, а не среднее: один день, когда завтрак случился в четыре
    /// часа дня, сдвинул бы среднее на час и переставил расписание по
    /// единственному странному дню.
    static func habits(_ days: [Day], minimumDays: Int = minimumDays) -> [Habit] {
        var shifts: [MealPeriod: [Int]] = [:]
        var ratios: [MealPeriod: [Double]] = [:]
        var seen: [MealPeriod: Int] = [:]
        var skipped: [MealPeriod: Int] = [:]

        for day in days {
            for meal in day.meals {
                seen[meal.period, default: 0] += 1
                guard !meal.skipped else {
                    skipped[meal.period, default: 0] += 1
                    continue
                }
                if let shift = meal.shiftMinutes {
                    shifts[meal.period, default: []].append(shift)
                }
                if let ratio = meal.caloriesRatio {
                    ratios[meal.period, default: []].append(ratio)
                }
            }
        }

        return MealPeriod.allCases.compactMap { period -> Habit? in
            // Считаем по дням, когда человек в это окно ел: по пропускам
            // нельзя сказать ни во сколько он ест, ни сколько кладёт.
            let shiftSamples = shifts[period] ?? []
            guard shiftSamples.count >= minimumDays else { return nil }
            guard let shift = median(shiftSamples.map(Double.init)),
                  let ratio = median(ratios[period] ?? []) else { return nil }
            return Habit(period: period,
                         days: seen[period] ?? shiftSamples.count,
                         shiftMinutes: Int(shift.rounded()),
                         caloriesRatio: ratio,
                         skippedDays: skipped[period] ?? 0)
        }
    }

    /// Что предложить человеку. Пустой список — значит план и жизнь сходятся.
    enum Suggestion: Equatable, Identifiable {
        /// Приём стабильно случается не тогда, когда стоит в расписании.
        case moveMeal(period: MealPeriod, byMinutes: Int, days: Int)
        /// В приём стабильно кладут больше или меньше плана.
        case resizeMeal(period: MealPeriod, ratio: Double, days: Int)
        /// Окно стабильно остаётся пустым — возможно, приёмов просто меньше.
        case dropMeal(period: MealPeriod, skippedDays: Int, ofDays: Int)

        var id: String {
            switch self {
            case let .moveMeal(period, _, _):  return "move-\(period.rawValue)"
            case let .resizeMeal(period, _, _): return "resize-\(period.rawValue)"
            case let .dropMeal(period, _, _):   return "drop-\(period.rawValue)"
            }
        }
    }

    /// Предложения по накопленным дням.
    ///
    /// Порядок один и тот же — по ходу суток: человек читает их как свой
    /// день, а не как список жалоб приложения.
    static func suggestions(for days: [Day], minimumDays: Int = minimumDays) -> [Suggestion] {
        var result: [Suggestion] = []
        let habits = habits(days, minimumDays: minimumDays)

        // Пропуски считаем отдельно от привычек: окно, в которое человек не
        // ел ни разу, до привычек не доходит — по нему нечего усреднять.
        var seen: [MealPeriod: Int] = [:]
        var skipped: [MealPeriod: Int] = [:]
        for day in days {
            for meal in day.meals {
                seen[meal.period, default: 0] += 1
                if meal.skipped { skipped[meal.period, default: 0] += 1 }
            }
        }

        for period in MealPeriod.allCases {
            let total = seen[period] ?? 0
            let misses = skipped[period] ?? 0
            // Пропущено почти всегда — это не «нарушение режима», а лишний
            // приём в расписании. Предлагаем убрать, а не укорять.
            if total >= minimumDays, Double(misses) / Double(total) >= 0.8 {
                result.append(.dropMeal(period: period, skippedDays: misses, ofDays: total))
                continue
            }
            guard let habit = habits.first(where: { $0.period == period }) else { continue }
            if abs(habit.shiftMinutes) >= noticeableShiftMinutes {
                result.append(.moveMeal(period: period,
                                        byMinutes: habit.shiftMinutes,
                                        days: habit.days))
            }
            if abs(habit.caloriesRatio - 1) >= noticeableRatio {
                result.append(.resizeMeal(period: period,
                                          ratio: habit.caloriesRatio,
                                          days: habit.days))
            }
        }
        return result
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
