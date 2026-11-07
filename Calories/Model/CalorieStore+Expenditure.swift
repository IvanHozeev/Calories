import Foundation

/// Расход энергии: измеренный по дневнику и весам, поправка за активность,
/// сон и пульс в покое.
extension CalorieStore {

    /// Расход за день — тот, что действовал в этот день.
    ///
    /// Без истории вчерашний день считался сегодняшним расходом: стоило
    /// оценке поехать вниз, и вчерашняя норма задним числом становилась ниже
    /// съеденного — зелёный день перекрашивался в оранжевый, хотя человек
    /// ничего не менял.
    func expenditure(on date: Date) -> Double? {
        guard let base = baseExpenditure(on: date) else { return nil }
        return base + activityAdjustment(on: date, expenditure: base)
    }

    /// Недельный расход без оглядки на активность этого дня.
    func baseExpenditure(on date: Date) -> Double? {
        let day = Calendar.current.startOfDay(for: date)
        guard day < Calendar.current.startOfDay(for: Date()) else { return smoothedTDEE }
        return tdeeHistory[Self.historyKey(day)] ?? smoothedTDEE
    }

    /// Поправка за активность этого дня: насколько он был подвижнее обычного.
    ///
    /// Ноль, пока не набралось двух недель шагов, — и это не заглушка, а
    /// ответ: не зная обычного дня, сравнивать не с чем.
    func activityAdjustment(on date: Date, expenditure: Double? = nil) -> Double {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let base = expenditure ?? baseExpenditure(on: day) else { return 0 }
        return ActivityAdjustment.adjustment(
            day: activity(on: day),
            baseline: activityBaseline,
            weightKg: latestWeight?.weightKg ?? profile?.weightKg,
            expenditure: base,
            partialDay: day >= calendar.startOfDay(for: Date()))
    }

    /// Сколько человек спал перед этим днём и насколько это меньше обычного.
    ///
    /// Дневнику это нужно не для арифметики, а для объяснений: после короткой
    /// ночи и вес скачет, и голод сильнее, и шагов меньше — без этой строчки
    /// такой день выглядит просто сорванным.
    func sleep(on date: Date) -> (hours: Double, shortfall: Double, fromBedOnly: Bool)? {
        guard let day = activity(on: date), let hours = day.sleepHours else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let nights = stepHistory.filter { $0.date >= from }.compactMap(\.sleepHours)
        let usual = nights.count >= 7 ? nights.reduce(0, +) / Double(nights.count) : hours
        return (hours, SleepAnalysis.shortfall(hours: hours, usual: usual),
                day.sleepFromBedOnly ?? false)
    }

    /// Пульс в покое сейчас и насколько он выше привычного.
    ///
    /// Нужен не для нормы, а для ответа на «почему вес встал, хотя я всё делаю
    /// правильно»: неделя подряд с повышенным пульсом покоя говорит, что пора
    /// отдохнуть, а не резать калории ещё.
    func restingPulse(now: Date = Date()) -> (value: Int, rise: Int?)? {
        let recent = pulses(lastDays: 7, now: now)
        guard let latest = recent.last else { return nil }
        return (latest, RestingPulse.rise(recent: recent, usual: pulses(lastDays: 28, now: now)))
    }

    func pulses(lastDays count: Int, now: Date) -> [Int] {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: now))
        else { return [] }
        return stepHistory.filter { $0.date >= from }.compactMap(\.restingPulse)
    }

    /// Что известно про активность этого дня.
    func activity(on date: Date) -> ActivityDay? {
        let calendar = Calendar.current
        return stepHistory.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// История расхода по дням, как она лежит в настройках.
    var tdeeHistory: [String: Double] {
        defaults.dictionary(forKey: Keys.tdeeHistory) as? [String: Double] ?? [:]
    }

    static func historyKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Запоминает сегодняшний расход и подчищает старое: больше года истории
    /// не нужно никому, а словарь в настройках лучше не растить бесконечно.
    func rememberTodayExpenditure(_ value: Double?, on day: Date) {
        guard let value else { return }
        var history = tdeeHistory
        history[Self.historyKey(day)] = value
        if history.count > 400 {
            for key in history.keys.sorted().prefix(history.count - 400) { history[key] = nil }
        }
        defaults.set(history, forKey: Keys.tdeeHistory)
    }

    /// Пересматривает «обычный день» — раз в неделю, как и сам расход.
    ///
    /// Чаще не нужно: среднее за четыре недели от одного дня почти не меняется,
    /// зато цель ползла бы каждый день. Реже — плохо: человек меняет работу,
    /// покупает велосипед, ложится с травмой, и привычная активность у него
    /// становится другой. Раз в неделю и подстраивается, и не дёргает.
    func refreshActivityBaseline(_ calendar: Calendar, today: Date) {
        let storedDay = defaults.object(forKey: Keys.activityBaselineDay) as? Date
        let stored = defaults.data(forKey: Keys.activityBaseline).flatMap {
            try? JSONDecoder().decode(ActivityAdjustment.Baseline.self, from: $0)
        }
        let daysSince = storedDay.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 }
        // Среднее, посчитанное по другому источнику, — не мерка: браслет
        // считает щедрее телефона, и обычный день по чужой линейке выглядит
        // нагруженным. Пока новое не набралось, честнее не иметь никакого.
        let current = ActivityAdjustment.currentSource(in: stepHistory)
        let usable = stored.flatMap { $0.source == current ? $0 : nil }
        if let usable, let daysSince, daysSince < Self.expenditureUpdateDays {
            activityBaseline = usable
            return
        }
        guard let fresh = ActivityAdjustment.baseline(from: stepHistory, now: today, calendar: calendar) else {
            // Период привыкания ещё идёт. Прошлое значение при этом не стираем:
            // если данные пропали на неделю (браслет на зарядке, отпуск без
            // телефона), лучше держать прежнюю картину, чем выключать поправку.
            activityBaseline = usable
            return
        }
        activityBaseline = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            defaults.set(data, forKey: Keys.activityBaseline)
            defaults.set(today, forKey: Keys.activityBaselineDay)
        }
    }

    /// Ведущий макрос: первый недобранный по порядку «белок → жир → углеводы».
    func rebuildFocusMacro() {
        let targets: [MacroKind: Double?] = [
            .protein: proteinTarget, .fat: fatTarget, .carbs: carbsTarget
        ]
        let eaten: [MacroKind: Double] = [
            .protein: macrosToday.protein, .fat: macrosToday.fat, .carbs: macrosToday.carbs
        ]
        focusMacro = AppAccent.focusOrder.first { kind in
            guard let target = targets[kind] ?? nil, target > 0 else { return false }
            return (eaten[kind] ?? 0) < target
        }
        // Виджет живёт в своём процессе и до дневника не дотягивается —
        // кладём ему готовый ответ.
        defaults.set(focusMacro?.rawValue ?? AppAccent.kcal.rawValue, forKey: "focus_macro")
    }
}
