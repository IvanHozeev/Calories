import Foundation

/// Одна подсказка «Сегодня»: текст, важность, срок и, возможно, действие.
///
/// Советы считают семь независимых расчётов, и у каждого была своя строка
/// под кольцом — экран спорил сам с собой. Теперь каждый расчёт переводит
/// свой совет в подсказку, а `DayHintPicker` выбирает одну главную.
///
/// Этап 1 (ТЗ-1): в подсказки переведены совет дня и сигнал «пора
/// подъесть». Пост, недельный обзор, кастрюли и копия пока живут своими
/// строками; их срочность уже записана в `Urgency`, чтобы порядок не
/// пришлось придумывать заново.
struct DayHint: Equatable, Identifiable, Sendable {
    /// Откуда подсказка. Порядок случаев решает ничью при равной срочности
    /// и равном сроке.
    enum Source: String, Codable, Sendable {
        case dailyAdvice, recovery, fasting, weeklyReview, batch, backup
        case weightExplainer, calendar
    }

    enum Action: Equatable, Sendable {
        case openAdd, openFasting, openWeeklyReview, openPlan
        case moveRefeedToday, backupNow
        /// Отметить пост из календаря — на этот день.
        case markFast(Date)
        /// Перенести рефид этой недели на праздник.
        case moveRefeed(Date)
    }

    /// `<источник>:<ключ>:<yyyy-MM-dd>` — один и тот же совет в один день
    /// имеет один номер, в другой день — другой.
    let id: String
    let source: Source
    let title: String
    let detail: String?
    /// 0…100, выше — важнее.
    let urgency: Int
    let expiresAt: Date
    let action: Action?

    /// Срочность, утверждённая владельцем 13.11.
    ///
    /// Перебор больше не первый: он бывает сознательным — праздник, ужин в
    /// гостях, — и тогда напоминать о нём бесполезно. Копия дневника выше
    /// всего: без неё год записей теряется вместе с телефоном. Пост, перерыв
    /// в диете и плато — это решения, которые надо принять заранее, а
    /// перебор — уже случившееся.
    enum Urgency {
        static let backup = 100
        static let fastingToday = 99
        static let dietBreak = 98
        static let plateau = 97
        static let fastingSoon = 96
        static let overGoal = 95
        static let notLogging = 94
        static let refeed = 93
        static let noDinnerYet = 92
        static let underGoal = 91
        static let weightExplainer = 80
        /// Справка на завтра, а не совет на сегодня.
        static let weightForecast = 60
        static let weeklyReview = 70
        static let batch = 40
        static let onTarget = 10
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Совет дня держится до конца суток: завтра он считается заново.
    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Совет дня — подсказкой. `.none` подсказки не даёт.
    static func from(_ advice: DailyAdvice, now: Date, calendar: Calendar = .current) -> [DayHint] {
        let key: String
        switch advice {
        case .none: return []
        case .onTarget: key = "onTarget"
        case .overGoal: key = "overGoal"
        case .underGoal: key = "underGoal"
        case .weightPlateau: key = "plateau"
        case .notLogging: key = "notLogging"
        case .noDinnerYet: key = "noDinnerYet"
        case .nothingToday: key = "nothingToday"
        }
        // Советы про еду, которую пора записать, нажимаются и открывают
        // добавление: по строке должно быть видно, что с ней делать.
        let action: Action? = {
            switch advice {
            case .nothingToday, .noDinnerYet, .underGoal: return .openAdd
            default: return nil
            }
        }()
        return [DayHint(id: "dailyAdvice:\(key):\(dayKey(now, calendar: calendar))",
                        source: .dailyAdvice,
                        title: advice.title,
                        detail: advice.body,
                        urgency: advice.priority,
                        expiresAt: endOfDay(now, calendar: calendar),
                        action: action)]
    }

    /// Сигнал «пора подъесть» — подсказкой. «Всё как задумано» подсказки не даёт.
    static func from(recovery: (verdict: RecoverySignal.Verdict, text: String)?,
                     now: Date, calendar: Calendar = .current) -> [DayHint] {
        guard let recovery else { return [] }
        let urgency: Int
        let action: Action
        switch recovery.verdict {
        case .fine: return []
        case .refeed: urgency = Urgency.refeed; action = .moveRefeedToday
        case .dietBreak: urgency = Urgency.dietBreak; action = .openPlan
        }
        return [DayHint(id: "recovery:\(recovery.verdict.rawValue):\(dayKey(now, calendar: calendar))",
                        source: .recovery,
                        title: recovery.text,
                        detail: nil,
                        urgency: urgency,
                        expiresAt: endOfDay(now, calendar: calendar),
                        action: action)]
    }

    /// Пост — подсказкой: в сам день срочнее, чем за один-три дня до него.
    /// Вид у неё свой (`FastingStrip` с часами до выхода) — здесь только место
    /// в очереди.
    static func fasting(daysUntil: Int, kind: String, now: Date, calendar: Calendar = .current) -> [DayHint] {
        guard (0...3).contains(daysUntil) else { return [] }
        return [DayHint(id: "fasting:\(kind)-\(daysUntil):\(dayKey(now, calendar: calendar))",
                        source: .fasting,
                        title: daysUntil == 0 ? String(localized: "Сегодня голодание")
                                              : String(localized: "Скоро голодание"),
                        detail: nil,
                        urgency: daysUntil == 0 ? Urgency.fastingToday : Urgency.fastingSoon,
                        expiresAt: endOfDay(now, calendar: calendar),
                        action: .openFasting)]
    }

    /// Напоминание о копии — подсказкой. Смахнутое, оно вернётся завтра:
    /// дневник без копии теряется вместе с телефоном.
    static func backup(now: Date, calendar: Calendar = .current) -> [DayHint] {
        [DayHint(id: "backup:missing:\(dayKey(now, calendar: calendar))",
                 source: .backup,
                 title: String(localized: "Копий дневника нет"),
                 detail: nil,
                 urgency: Urgency.backup,
                 expiresAt: endOfDay(now, calendar: calendar),
                 action: .backupNow)]
    }

    /// Недельный обзор — подсказкой, с предложенной нормой в номере: новое
    /// предложение не должно прятаться за смахнутым старым.
    static func weeklyReview(proposal: Int, now: Date, calendar: Calendar = .current) -> [DayHint] {
        [DayHint(id: "weeklyReview:\(proposal):\(dayKey(now, calendar: calendar))",
                 source: .weeklyReview,
                 title: String(localized: "Недельный обзор"),
                 detail: nil,
                 urgency: Urgency.weeklyReview,
                 expiresAt: endOfDay(now, calendar: calendar),
                 action: .openWeeklyReview)]
    }

    /// Объяснение веса — подсказкой. Говорит «похоже на воду» и никогда не
    /// говорит про жир; тренд называет прежним.
    static func weight(_ explanation: WeightExplainer.Explanation, now: Date,
                       calendar: Calendar = .current) -> [DayHint] {
        let up = explanation.residualKg > 0
        let causes = explanation.contributions.map { contribution -> String in
            switch contribution.factor {
            case .carbs: return up ? String(localized: "углеводов больше обычного")
                                   : String(localized: "углеводов меньше обычного")
            case .sodium: return up ? String(localized: "соли больше обычного")
                                    : String(localized: "соли меньше обычного")
            case .lateMeal: return String(localized: "поздний ужин")
            case .afterFast: return String(localized: "день поста")
            }
        }
        let kg = String(format: "%+.1f", explanation.residualKg)
        let title = String(format: String(localized: "%1$@ кг к тренду: вчера %2$@. Похоже на воду, тренд прежний."),
                           kg, ListFormatter.localizedString(byJoining: causes))
        return [DayHint(id: "weightExplainer:\(up ? "up" : "down"):\(dayKey(now, calendar: calendar))",
                        source: .weightExplainer,
                        title: title,
                        detail: nil,
                        urgency: Urgency.weightExplainer,
                        expiresAt: endOfDay(now, calendar: calendar),
                        action: nil)]
    }
}

extension DayHint {
    /// Подсказки еврейского календаря.
    ///
    /// Приложение само ничего не создаёт: за три дня до поста предлагает его
    /// отметить, в неделю праздника — перенести на него рефид. Каждое
    /// действие подтверждает человек.
    ///
    /// - Parameters:
    ///   - enabled: календарь включён (по умолчанию выключен).
    ///   - hasFast: есть ли уже отметка поста на этот день — тогда предлагать нечего.
    ///   - canMoveRefeed: можно ли перенести рефид на этот день — и он в той же
    ///     неделе плана, что сегодня. Неделя плана начинается с понедельника, а
    ///     календарная — по обычаю страны, поэтому решает план.
    static func calendar(_ events: [JewishCalendar.Event], now: Date, enabled: Bool,
                         hasFast: (Date) -> Bool, canMoveRefeed: (Date) -> Bool,
                         calendar: Calendar = .current) -> [DayHint] {
        guard enabled else { return [] }
        let today = calendar.startOfDay(for: now)
        let expires = endOfDay(now, calendar: calendar)
        var hints: [DayHint] = []

        for event in events where event.isFast {
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: event.day)).day ?? -1
            guard (0...3).contains(days), !hasFast(event.day) else { continue }
            let when = event.day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            hints.append(DayHint(id: "calendar:fast-\(event.key):\(dayKey(now, calendar: calendar))",
                                 source: .calendar,
                                 title: String(format: String(localized: "Отметить пост: %1$@, %2$@"), event.title, when),
                                 detail: nil,
                                 urgency: Urgency.fastingSoon,
                                 expiresAt: expires,
                                 action: .markFast(event.day)))
        }

        // Праздник этой недели, на который рефид ещё можно перенести, —
        // только первый: рефид один.
        if let feast = events.first(where: { event in
            event.kind == .feast && calendar.startOfDay(for: event.day) >= today
                && canMoveRefeed(event.day)
        }) {
            let weekday = feast.day.formatted(.dateTime.weekday(.wide))
            hints.append(DayHint(id: "calendar:feast-\(feast.key):\(dayKey(now, calendar: calendar))",
                                 source: .calendar,
                                 title: String(format: String(localized: "Перенести рефид на %1$@ (%2$@)"), feast.title, weekday),
                                 detail: nil,
                                 urgency: Urgency.refeed,
                                 expiresAt: expires,
                                 action: .moveRefeed(feast.day)))
        }
        return hints
    }
}

extension DayHint {
    /// Прогноз завтрашнего утра — подсказкой. Говорит про воду и тренд, не
    /// про жир: это предупреждение, чтобы утренний скачок не пугал.
    static func forecast(_ forecast: WeightExplainer.Forecast, trendKg: Double, now: Date,
                         calendar: Calendar = .current) -> [DayHint] {
        let up = forecast.residualKg > 0
        let causes = forecast.contributions.map { contribution -> String in
            switch contribution.factor {
            case .carbs: return up ? String(localized: "углеводов больше обычного")
                                   : String(localized: "углеводов меньше обычного")
            case .sodium: return up ? String(localized: "соли больше обычного")
                                    : String(localized: "соли меньше обычного")
            case .lateMeal: return String(localized: "поздний ужин")
            case .afterFast: return String(localized: "день поста")
            }
        }
        let expected = String(format: "%.1f", trendKg + forecast.residualKg)
        let delta = String(format: "%+.1f", forecast.residualKg)
        let title = String(format: String(localized: "Завтра утром, скорее всего, около %1$@ кг (%2$@ к тренду): сегодня %3$@. Это вода."),
                           expected, delta, ListFormatter.localizedString(byJoining: causes))
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return [DayHint(id: "weightExplainer:forecast-\(up ? "up" : "down"):\(day)",
                        source: .weightExplainer,
                        title: title,
                        detail: nil,
                        urgency: Urgency.weightForecast,
                        expiresAt: end,
                        action: nil)]
    }
}

/// Смахнутые подсказки — до конца дня.
///
/// В номере подсказки есть дата, поэтому завтрашняя — другая и сама
/// возвращается. Хранить вчерашние незачем: при чтении они отбрасываются,
/// и список не растёт.
struct DismissedHints {
    static let key = "dismissed_day_hints"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Смахнутые сегодня.
    func load(now: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        let today = Self.todaySuffix(now, calendar: calendar)
        return Set((defaults.stringArray(forKey: Self.key) ?? []).filter { $0.hasSuffix(today) })
    }

    /// Запомнить смахнутую и вернуть новый набор.
    @discardableResult
    func dismiss(_ id: String, now: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        var ids = load(now: now, calendar: calendar)
        ids.insert(id)
        defaults.set(Array(ids).sorted(), forKey: Self.key)
        return ids
    }

    private static func todaySuffix(_ now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: ":%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Выбор одной главной подсказки.
///
/// Чистая функция: одинаковый вход даёт одинаковый выход, время только из
/// `now`. Поэтому порядок проверяется таблицей, а не глазами на экране.
enum DayHintPicker {
    /// `main` — что показать строкой, `rest` — остальное по убыванию важности.
    static func pick(_ all: [DayHint], now: Date, dismissed: Set<String>)
        -> (main: DayHint?, rest: [DayHint]) {
        let order = { (source: DayHint.Source) in
            [DayHint.Source.dailyAdvice, .recovery, .fasting, .weeklyReview, .batch, .backup,
             .weightExplainer, .calendar].firstIndex(of: source) ?? .max
        }
        let live = all
            .filter { $0.expiresAt > now && !dismissed.contains($0.id) }
            .sorted { a, b in
                if a.urgency != b.urgency { return a.urgency > b.urgency }
                if a.expiresAt != b.expiresAt { return a.expiresAt < b.expiresAt }
                if a.source != b.source { return order(a.source) < order(b.source) }
                return a.id < b.id
            }
        return (live.first, Array(live.dropFirst()))
    }
}
