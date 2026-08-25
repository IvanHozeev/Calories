import Foundation
import SwiftData

/// Производные величины: цели, серии, достижения и соответствие плану.
/// Всё только читает состояние — записи здесь нет.
// Часть методов ниже объявлена без private: их вызывает rebuildCaches() из основного
// файла, а private в Swift ограничен файлом. Это чистые вычисления без побочных эффектов.
extension CalorieStore {

    func goalHistory(days: Int) -> [(date: Date, hasEntries: Bool, onGoal: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayTotal = (entriesByDay[date] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[date] ?? effectiveGoal(for: date)
            return (date, dayTotal > 0, dayTotal > 0 && dayTotal <= dayGoal)
        }
    }

    /// Сколько дней подряд закрыта норма белка. Историческая норма нигде не фиксируется,
    /// поэтому берём текущую из профиля — при смене веса или множителя прошлые дни
    /// пересчитаются под новую планку. Для достижения этого достаточно.
    func computeProteinStreak() -> Int {
        guard let target = proteinTarget, target > 0 else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func hit(_ day: Date) -> Bool {
            let entries = entriesByDay[day] ?? []
            guard !entries.isEmpty else { return false }
            return entries.reduce(0) { $0 + $1.protein } >= target
        }

        var streak = hit(today) ? 1 : 0
        var date = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while hit(date) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    func computeStreak() -> (current: Int, best: Int, logging: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // On-goal streak (логирование + попадание в калории)
        var currentStreak = 0
        let todayTotal = (entriesByDay[today] ?? []).reduce(0) { $0 + $1.calories }
        if todayTotal > 0, todayTotal <= (goalsByDay[today] ?? effectiveGoal(for: today)) {
            currentStreak += 1
        }
        var pastDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while true {
            let dayTotal = (entriesByDay[pastDate] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[pastDate] ?? effectiveGoal(for: pastDate)
            guard dayTotal > 0, dayTotal <= dayGoal else { break }
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: pastDate) else { break }
            pastDate = prev
        }

        var best = 0
        var run = 0
        var prevDate: Date? = nil
        for date in entriesByDay.keys.filter({ !calendar.isDateInToday($0) }).sorted() {
            let dayTotal = (entriesByDay[date] ?? []).reduce(0) { $0 + $1.calories }
            let dayGoal = goalsByDay[date] ?? effectiveGoal(for: date)
            if dayTotal > 0, dayTotal <= dayGoal {
                let consecutive = prevDate.map { calendar.date(byAdding: .day, value: 1, to: $0) == date } ?? false
                run = consecutive ? run + 1 : 1
                prevDate = date
                best = max(best, run)
            } else {
                prevDate = nil
                run = 0
            }
        }

        // Logging streak (просто есть записи за день)
        var loggingStreak = 0
        if todayTotal > 0 { loggingStreak += 1 }
        var logDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while true {
            guard (entriesByDay[logDate] ?? []).reduce(0, { $0 + $1.calories }) > 0 else { break }
            loggingStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: logDate) else { break }
            logDate = prev
        }

        return (currentStreak, max(best, currentStreak), loggingStreak)
    }

    /// Эффективная цель на конкретную дату: если активен план с недельным циклом — берём
    /// цифру из цикла на этот день недели, иначе — обычный dailyGoal.
    func effectiveGoal(for date: Date) -> Int {
        if let plan, plan.cyclingEnabled, let profile {
            return plan.calorieTarget(for: date, tdee: profile.tdee)
        }
        return dailyGoal
    }

    /// Зафиксированная цель на дату (из снапшота) — иначе живой расчёт. O(1) через goalsByDay.
    func goal(for date: Date) -> Int {
        let day = Calendar.current.startOfDay(for: date)
        return goalsByDay[day] ?? effectiveGoal(for: day)
    }

    /// Достижения на текущий момент. Прогресс берётся из лучшего результата:
    /// один раз собранная серия не должна пропадать из-за одного сорванного дня.
    var achievements: [Achievement] {
        [
            Achievement(kind: .firstWeek, current: max(streak, bestStreak), target: 7),
            Achievement(kind: .disciplineMaster, current: max(streak, bestStreak), target: 14),
            Achievement(kind: .proteinMaster, current: proteinStreak, target: 5),
            Achievement(kind: .ironWill, current: loggingStreak, target: 30)
        ]
    }

    /// Целевой белок в граммах — nil, если профиль ещё не заполнен.
    var proteinTarget: Double? {
        profile?.proteinTargetGrams
    }

    /// Текущий вес — из последнего взвешивания, иначе из профиля.
    var weightKg: Double? {
        latestWeight?.weightKg ?? profile?.weightKg
    }

    /// Минимальная дневная норма жиров исходя из веса.
    var fatTarget: Double? {
        weightKg.map { $0 * MacroTargets.fatPerKg }
    }

    /// Подсказка что добрать на оставшиеся калории: белок → жиры → углеводы.
    var macroSuggestion: String? {
        guard remaining > 0, profile != nil else { return nil }
        let m = macrosToday
        if let pt = proteinTarget, pt > 0, m.protein < pt {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerProteinGram, pt - m.protein).rounded())
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г белка"
        }
        if let ft = fatTarget, ft > 0, m.fat < ft {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerFatGram, ft - m.fat).rounded())
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г жиров"
        }
        if m.carbs < MacroTargets.carbsMinimum {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerCarbGram, MacroTargets.carbsMinimum - m.carbs).rounded())
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г углеводов"
        }
        return nil
    }

    /// Базовая цель на сегодня без поправки банка.
    var todayGoal: Int {
        effectiveGoal(for: Date())
    }

    var remaining: Int {
        adaptedTodayGoal - consumedToday
    }

    var progress: Double {
        guard adaptedTodayGoal > 0 else { return 0 }
        return min(Double(consumedToday) / Double(adaptedTodayGoal), 1.0)
    }

    /// Адаптированная цель с учётом недельного банка калорий.
    /// Если сэкономил раньше на неделе — норма растёт. Если перерасход — снижается.
    func computeAdaptedTodayGoal() -> Int {
        guard isPremium else { return effectiveGoal(for: Date()) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Respect locale's first weekday (Sun=1 for IL/US, Mon=2 for Europe)
        let daysFromFirst = (weekday - calendar.firstWeekday + 7) % 7

        guard daysFromFirst > 0,
              let weekStart = calendar.date(byAdding: .day, value: -daysFromFirst, to: today) else {
            return effectiveGoal(for: today)
        }

        let remainingDays = 7 - daysFromFirst
        var weeklyGoalPast = 0
        var weeklyConsumedPast = 0

        for offset in 0..<daysFromFirst {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayEntries = entriesByDay[date] ?? []
            guard !dayEntries.isEmpty else { continue }
            weeklyGoalPast += goal(for: date)
            weeklyConsumedPast += dayEntries.reduce(0) { $0 + $1.calories }
        }

        let bank = weeklyGoalPast - weeklyConsumedPast
        let baseGoal = effectiveGoal(for: today)
        let bankPerDay = bank / remainingDays
        let cappedBonus = min(bankPerDay, 500)
        return max(baseGoal + cappedBonus, 1000)
    }

    /// Сводка за конкретный день — O(1) через entriesByDay.
    func summary(for date: Date) -> DaySummary {
        let day = Calendar.current.startOfDay(for: date)
        return DaySummary(date: day, entries: entriesByDay[day] ?? [], goal: goal(for: day))
    }

    /// Последние N дней (включая сегодня), от старого к новому — для графиков.
    func lastDays(_ count: Int) -> [DaySummary] {
        let calendar = Calendar.current
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return summary(for: date)
        }
    }

    /// Сверяет факт с линейным прогнозом плана. Возвращает кэшированный результат из adherence.
    func planAdherence() -> PlanAdherence? { adherence }

    func computePlanAdherence() -> PlanAdherence? {
        guard let plan, let profile else { return nil }

        let totalDays = Double(plan.durationWeeks * 7)
        let elapsedDays = min(max(Date().timeIntervalSince(plan.startDate) / 86400, 0), totalDays)
        let expectedWeightToday = plan.startWeightKg + plan.totalWeightChangeKg * (totalDays > 0 ? elapsedDays / totalDays : 0)

        let relevantEntries = weightEntries.filter { $0.date >= plan.startDate }
        guard relevantEntries.last != nil else {
            return PlanAdherence(
                expectedWeightToday: expectedWeightToday,
                actualWeightToday: nil,
                observedWeeklyRateKg: nil,
                projectedEndDate: nil,
                projectedWeightAtPlanEnd: nil,
                recalibratedDailyCalories: nil,
                status: .insufficientData,
                dataGap: AdherenceDataGap(
                    weighInsLogged: 0,
                    weighInsRequired: 2,
                    daysUntilTrend: max(0, 7 - Int(elapsedDays))
                )
            )
        }
        let recentWindow = relevantEntries.suffix(7)
        let actualWeightToday = recentWindow.reduce(0) { $0 + $1.weightKg } / Double(recentWindow.count)

        let elapsedWeeks = elapsedDays / 7
        guard elapsedWeeks >= 1, relevantEntries.count >= 2 else {
            return PlanAdherence(
                expectedWeightToday: expectedWeightToday,
                actualWeightToday: actualWeightToday,
                observedWeeklyRateKg: nil,
                projectedEndDate: nil,
                projectedWeightAtPlanEnd: nil,
                recalibratedDailyCalories: nil,
                status: .insufficientData,
                dataGap: AdherenceDataGap(
                    weighInsLogged: relevantEntries.count,
                    weighInsRequired: 2,
                    daysUntilTrend: max(0, 7 - Int(elapsedDays))
                )
            )
        }

        let observedWeeklyRate = (actualWeightToday - plan.startWeightKg) / elapsedWeeks

        var projectedEndDate: Date?
        if observedWeeklyRate != 0 {
            let remainingChange = plan.targetWeightKg - actualWeightToday
            let weeksNeeded = remainingChange / observedWeeklyRate
            if weeksNeeded.isFinite, weeksNeeded > 0 {
                projectedEndDate = Calendar.current.date(byAdding: .day, value: Int((weeksNeeded * 7).rounded()), to: Date())
            }
        }

        let remainingDays = totalDays - elapsedDays
        var recalibratedDailyCalories: Int?
        if remainingDays > 0 {
            let remainingChangeNeeded = plan.targetWeightKg - actualWeightToday
            let dailyDelta = remainingChangeNeeded * Plan.kcalPerKg / remainingDays
            recalibratedDailyCalories = Int((profile.tdee + dailyDelta).rounded())
        }

        let remainingWeeks = remainingDays / 7
        let projectedWeightAtPlanEnd = remainingWeeks > 0
            ? actualWeightToday + observedWeeklyRate * remainingWeeks
            : nil as Double?

        let deviation = actualWeightToday - expectedWeightToday
        let threshold = max(0.3, abs(plan.totalWeightChangeKg) * 0.05)
        let status: PlanStatus
        if abs(deviation) <= threshold {
            status = .onTrack
        } else if (plan.totalWeightChangeKg < 0 && deviation > 0) || (plan.totalWeightChangeKg > 0 && deviation < 0) {
            status = .behind
        } else {
            status = .ahead
        }

        return PlanAdherence(
            expectedWeightToday: expectedWeightToday,
            actualWeightToday: actualWeightToday,
            observedWeeklyRateKg: observedWeeklyRate,
            projectedEndDate: projectedEndDate,
            projectedWeightAtPlanEnd: projectedWeightAtPlanEnd,
            recalibratedDailyCalories: recalibratedDailyCalories,
            status: status,
            dataGap: nil
        )
    }
}
