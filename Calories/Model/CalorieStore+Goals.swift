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

    /// Удержан ли день: попал в норму или был отмечен голоданием.
    ///
    /// Голодание засчитывается, потому что человек сделал именно то, что собирался.
    /// Без этого один Йом Кипур обнулял серию в тридцать дней.
    func isDayKept(_ date: Date) -> Bool {
        if isFastDay(date) { return true }
        let day = Calendar.current.startOfDay(for: date)
        let total = (entriesByDay[day] ?? []).reduce(0) { $0 + $1.calories }
        guard total > 0 else { return false }
        return total <= (goalsByDay[day] ?? effectiveGoal(for: day))
    }

    /// Есть ли за день записи — или он отмечен голоданием, что тоже ведение дневника.
    func isDayLogged(_ date: Date) -> Bool {
        if isFastDay(date) { return true }
        let day = Calendar.current.startOfDay(for: date)
        return (entriesByDay[day] ?? []).reduce(0) { $0 + $1.calories } > 0
    }

    func computeStreak() -> (current: Int, best: Int, logging: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // On-goal streak (логирование + попадание в калории)
        var currentStreak = 0
        if isDayKept(today) { currentStreak += 1 }
        var pastDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while true {
            guard isDayKept(pastDate) else { break }
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: pastDate) else { break }
            pastDate = prev
        }

        var best = 0
        var run = 0
        var prevDate: Date? = nil
        let pastDays = Set(entriesByDay.keys).union(fastDates)
            .filter { !calendar.isDateInToday($0) }
            .sorted()
        for date in pastDays {
            if isDayKept(date) {
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
        if isDayLogged(today) { loggingStreak += 1 }
        var logDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while true {
            guard isDayLogged(logDate) else { break }
            loggingStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: logDate) else { break }
            logDate = prev
        }

        return (currentStreak, max(best, currentStreak), loggingStreak)
    }

    /// Эффективная цель на конкретную дату: если активен план с недельным циклом — берём
    /// цифру из цикла на этот день недели, иначе — обычный dailyGoal.
    /// Норма на дату.
    ///
    /// При включённом цикле считается по формуле плана: она зависит от дня недели,
    /// хранить её числом негде. Без цикла норма зависит только от TDEE, поэтому
    /// берётся из `dailyGoal` — но он теперь пересчитывается на каждое изменение
    /// профиля, так что за падающим весом следуют оба пути одинаково.
    ///
    /// Из `dailyGoal`, а не из формулы, ещё по одной причине: кнопка «замедлить»
    /// в разборе плана пишет туда пересчитанное число, и живая формула молча
    /// затирала бы её на следующем же чтении.
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
        profile?.proteinTargetGrams(from: latestMeasurement)
    }

    /// Сколько калорий забирают белок и жир — то, что съесть обязан.
    var lockedMacroCalories: Double? {
        guard let p = proteinTarget, let f = fatTarget else { return nil }
        return p * MacroTargets.kcalPerProteinGram + f * MacroTargets.kcalPerFatGram
    }

    /// Углеводы — остаток дневной нормы после белка и жира.
    ///
    /// Именно поэтому в высокий день циклирования и при возврате из банка калорий
    /// вырастают только они: белок и жир заданы телом, углеводы — то, чем реально
    /// управляешь. Ноль означает «не помещается», см. `macrosOverflow`.
    var carbsTarget: Double? {
        guard let locked = lockedMacroCalories, adaptedTodayGoal > 0 else { return nil }
        let left = Double(adaptedTodayGoal) - locked
        return left > 0 ? left / MacroTargets.kcalPerCarbGram : 0
    }

    /// Насколько белок с жиром не влезают в норму, в килокалориях. nil — влезают.
    /// На глубоком дефиците это обычное дело, и молчать об этом нельзя: человек
    /// иначе каждый день недобирает вслепую.
    var macrosOverflow: Int? {
        guard let locked = lockedMacroCalories, adaptedTodayGoal > 0 else { return nil }
        let over = locked - Double(adaptedTodayGoal)
        return over > 0 ? Int(over.rounded()) : nil
    }

    /// Текущий вес — трендовый, а не последнее взвешивание.
    ///
    /// Дневной вес почти целиком шум: соль, углеводы, гликоген и вода дают
    /// колебания больше килограмма, а натурал в дефиците теряет граммов
    /// семьдесят в день. Норма плана, цели по макросам и вердикт по составу
    /// тела шли за последним числом на весах — то есть за водой.
    var weightKg: Double? {
        weightTrend(on: Date()) ?? profile?.weightKg
    }

    /// Дневная норма жиров. Из профиля, если он есть: с недавних пор её задают
    /// руками, и на глубоком дефиците её опускают.
    var fatTarget: Double? {
        guard let weight = weightKg else { return nil }
        return weight * (profile?.fatPerKg ?? MacroTargets.fatPerKg)
    }

    /// Последние семь дней в разрезе макросов.
    ///
    /// Цель по белку и жиру одна на все дни — её задаёт тело. По углеводам своя на
    /// каждый день, потому что это остаток нормы, а норма при циклировании ходит
    /// вверх-вниз. Ради этого разбор и нужен: видно, что в высокий день выросли
    /// именно углеводы, а обязательства остались теми же.
    var macroWeek: [MacroDay] {
        guard let protein = proteinTarget, let fat = fatTarget, protein > 0 else { return [] }
        let locked = protein * MacroTargets.kcalPerProteinGram + fat * MacroTargets.kcalPerFatGram
        return lastSevenDays.map { day in
            MacroDay(
                date: day.date,
                macros: day.totalMacros,
                proteinTarget: protein,
                fatTarget: fat,
                carbsTarget: max(0, (Double(day.goal) - locked) / MacroTargets.kcalPerCarbGram),
                hasEntries: !day.entries.isEmpty
            )
        }
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
        let carbsGoal = carbsTarget ?? MacroTargets.carbsMinimum
        if m.carbs < carbsGoal {
            let canEat = Int(min(Double(remaining) / MacroTargets.kcalPerCarbGram, carbsGoal - m.carbs).rounded())
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

    
    func adaptedGoal(for date: Date) -> Int {
        guard isPremium else { return effectiveGoal(for: date) }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Respect locale's first weekday (Sun=1 for IL/US, Mon=2 for Europe)
        let daysFromFirst = (weekday - calendar.firstWeekday + 7) % 7

        guard daysFromFirst > 0,
              let weekStart = calendar.date(byAdding: .day, value: -daysFromFirst, to: date) else {
            return effectiveGoal(for: date)
        }

        let remainingDays = 7 - daysFromFirst
        var weeklyGoalPast = 0
        var weeklyConsumedPast = 0

        for offset in 0..<daysFromFirst {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayEntries = entriesByDay[date] ?? []
            // Пустой день пропускаем: забытый день не должен изображать нулевую
            // еду и раздувать банк. Отмеченное голодание — другое дело, там ноль
            // настоящий, и в недельное среднее он входит на общих основаниях.
            guard !dayEntries.isEmpty || isFastDay(date) else { continue }
            weeklyGoalPast += goal(for: date)
            weeklyConsumedPast += dayEntries.reduce(0) { $0 + $1.calories }
        }

        let bank = weeklyGoalPast - weeklyConsumedPast
        let baseGoal = effectiveGoal(for: date)
        let bankPerDay = bank / remainingDays
        let cappedBonus = min(bankPerDay, 500)
        return max(baseGoal + cappedBonus, 1000)
    }
    
    /// Адаптированная цель на сегодня — частный случай adaptedGoal(for:).
    /// Тело было скопировано дословно, разошлись бы при первой же правке одного из них.
    func computeAdaptedTodayGoal() -> Int { adaptedGoal(for: Date()) }

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

    /// Из чего складывалось изменение веса за время плана.
    ///
    /// Нужны два сеанса замеров с поясом и шеей: без них процент жира считается
    /// по ИМТ, а он не отличает 77 кг мышц от 77 кг с животом — то есть ровно то,
    /// ради чего этот расчёт и делается.
    var planCompositionChange: CompositionChange? {
        guard let plan, let profile else { return nil }
        // Считаем от начала идущей фазы, а не всего плана. У цепочки
        // «сушка — набор» состав за план целиком складывает противоположные
        // куски: потерянный жир гасится набранным, и вердикт выходит про
        // ничто. У плана из одной фазы это ровно то же самое, что было.
        let phaseStart = plan.startDate(ofPhaseAt: plan.phaseIndex(on: Date()) ?? 0)
        let usable = measurements
            .filter { $0.date >= phaseStart && profile.navyBodyFat(from: $0) != nil }
            .sorted { $0.date < $1.date }
        guard let first = usable.first, let last = usable.last, first.id != last.id else { return nil }

        // По тренду, а не по одному взвешиванию: вердикт «ушла сухая масса»
        // на разнице двух случайных дней — это вердикт по воде.
        guard let startWeight = weightTrend(on: first.date),
              let endWeight = weightTrend(on: last.date) else { return nil }

        // Процент жира считаем от веса на ту дату, а не от текущего: профиль
        // хранит один вес, и без подмены оба замера получили бы сегодняшний.
        var atStart = profile
        atStart.weightKg = startWeight
        var atEnd = profile
        atEnd.weightKg = endWeight

        guard let startFat = atStart.navyBodyFat(from: first),
              let endFat = atEnd.navyBodyFat(from: last) else { return nil }

        return CompositionChange(
            fromDate: first.date,
            toDate: last.date,
            startWeightKg: startWeight,
            endWeightKg: endWeight,
            startFatPercent: startFat,
            endFatPercent: endFat
        )
    }

    /// Трендовый вес на дату — среднее взвешиваний в окне вокруг неё.
    ///
    /// Окно по времени, а не по числу взвешиваний: человек встаёт на весы не
    /// каждый день, и «последние семь записей» у него могут растянуться на
    /// месяц, а у соседа уложиться в неделю. Семь дней — привычный для этой
    /// аудитории размер: короче не гасит недельный цикл соли и углеводов,
    /// длиннее начинает запаздывать за настоящим изменением.
    ///
    /// Если в окне пусто, отдаём ближайшее взвешивание — это не хуже того,
    /// что было до тренда, и лучше, чем не показать ничего.
    func weightTrend(on date: Date, days: Int = 7) -> Double? {
        let half = Double(days) / 2 * 86_400
        let window = weightEntries.filter { abs($0.date.timeIntervalSince(date)) <= half }
        guard !window.isEmpty else { return weight(nearest: date) }
        return window.reduce(0) { $0 + $1.weightKg } / Double(window.count)
    }

    /// Взвешивание, ближайшее к дате. Замеры и весы живут по своим расписаниям,
    /// и требовать, чтобы они совпали день в день, значит не показать ничего.
    func weight(nearest date: Date) -> Double? {
        weightEntries.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }?.weightKg
    }

    /// Итог дошедшего до финиша плана. nil, пока план идёт.
    var planOutcome: PlanOutcome? {
        guard let plan, plan.isFinished else { return nil }
        // Тот же тренд, что и везде: раньше здесь было своё сглаживание по
        // семи последним записям, и итог плана считался иначе, чем прогресс.
        return PlanOutcome(plan: plan, finalWeightKg: weightTrend(on: plan.endDate))
    }

    func computePlanAdherence() -> PlanAdherence? {
        guard let plan, let profile else { return nil }

        let today = Date()
        let totalDays = Double(plan.durationWeeks * 7)
        let elapsedDays = min(max(today.timeIntervalSince(plan.startDate) / 86400, 0), totalDays)
        // Прогноз берётся у цепочки, а не тянется прямой от старта к финишу.
        // На прямой поддержание посреди плана выглядит как продолжающийся
        // дефицит, и приложение обвиняло бы человека в том, что само же
        // и запланировало.
        let expectedWeightToday = plan.projectedWeight(on: today)

        // Дальше всё меряется по идущей фазе, а не по плану целиком. Средний
        // темп цепочки «сушка — поддержание — набор» близок к нулю и не
        // отвечает ни на один вопрос, который здесь задают.
        let phaseIndex = plan.phaseIndex(on: today) ?? max(0, plan.phases.count - 1)
        let phase = plan.phases[phaseIndex]
        let phaseStart = plan.startDate(ofPhaseAt: phaseIndex)
        let phaseEnd = Calendar.current.date(byAdding: .day,
                                             value: phase.durationWeeks * 7,
                                             to: phaseStart) ?? plan.endDate
        let phaseTargetWeight = plan.weight(atStartOfPhaseAt: phaseIndex + 1)

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

        // Темп считается от веса на старте идущей фазы, а не всего плана.
        // Вес на её старте берём у тренда — реальный, а не запланированный:
        // сравнивать факт с фактом. До первой фазы тренда нет, тогда сойдёт
        // и стартовый вес плана.
        let phaseStartWeight = weightTrend(on: phaseStart) ?? plan.startWeightKg
        let daysInPhase = max(0, today.timeIntervalSince(phaseStart) / 86400)
        let weeksInPhase = max(daysInPhase / 7, 1.0 / 7)
        let observedWeeklyRate = (actualWeightToday - phaseStartWeight) / weeksInPhase

        var projectedEndDate: Date?
        if observedWeeklyRate != 0 {
            let remainingChange = phaseTargetWeight - actualWeightToday
            let weeksNeeded = remainingChange / observedWeeklyRate
            if weeksNeeded.isFinite, weeksNeeded > 0 {
                projectedEndDate = Calendar.current.date(byAdding: .day, value: Int((weeksNeeded * 7).rounded()), to: today)
            }
        }

        // Пересчёт нормы — до конца фазы, а не до конца плана. Иначе он размажет
        // оставшийся дефицит по месяцам поддержания, которые идут следом.
        let remainingDaysInPhase = max(0, phaseEnd.timeIntervalSince(today) / 86400)
        var recalibratedDailyCalories: Int?
        if remainingDaysInPhase > 0 {
            let remainingChangeNeeded = phaseTargetWeight - actualWeightToday
            let dailyDelta = remainingChangeNeeded * Plan.kcalPerKg / remainingDaysInPhase
            recalibratedDailyCalories = Int((profile.tdee + dailyDelta).rounded())
        }

        let remainingWeeksInPhase = remainingDaysInPhase / 7
        let projectedWeightAtPlanEnd = remainingWeeksInPhase > 0
            ? actualWeightToday + observedWeeklyRate * remainingWeeksInPhase
            : nil as Double?

        let deviation = actualWeightToday - expectedWeightToday
        // Допуск от того, сколько фаза вообще собиралась сдвинуть. У поддержания
        // это ноль, и остаётся нижняя граница в 300 г — то есть шум весов.
        let phasePlannedChange = phaseTargetWeight - plan.weight(atStartOfPhaseAt: phaseIndex)
        let settling = plan.isSettling(on: today)
        // Пока после подъёма калорий возвращаются гликоген и вода, допуск шире
        // на эти самые пару килограммов. Иначе приложение объявит провалом
        // ровно то, что само же и назначило переходом.
        let threshold = settling
            ? max(Plan.settlingToleranceKg, abs(phasePlannedChange) * 0.05)
            : max(0.3, abs(phasePlannedChange) * 0.05)
        let direction = phase.intent.direction
        let status: PlanStatus
        if abs(deviation) <= threshold {
            status = .onTrack
        } else if direction == 0 {
            // Поддержание не бывает «впереди»: любой уход от нуля — уход в сторону.
            status = .behind
        } else if (direction < 0 && deviation > 0) || (direction > 0 && deviation < 0) {
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
            dataGap: nil,
            isSettlingAfterIncrease: settling
        )
    }
}
