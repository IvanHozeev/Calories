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
        }
        return [DayHint(id: "dailyAdvice:\(key):\(dayKey(now, calendar: calendar))",
                        source: .dailyAdvice,
                        title: advice.title,
                        detail: advice.body,
                        urgency: advice.priority,
                        expiresAt: endOfDay(now, calendar: calendar),
                        action: nil)]
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
