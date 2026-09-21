import Foundation

// План: фазы, их длительность и темп, циклирование по дням недели и то,
// какая норма получается на конкретный день.

enum WeekendStyle: String, Codable, CaseIterable, Identifiable {
    case monTue   // рефид в начале недели: Пн+Вт
    case satSun   // стандартный мир: Сб+Вс
    case friSat   // Израиль: Пт+Сб
    case sunMon   // Израиль: Вс+Пн
    case wedSat   // рефид в среду и субботу
    case wedFri   // рефид в среду и пятницу
    // Праздники этими парами больше не закрываем: для них есть перенос рефида
    // на конкретный день, см. `RefeedMove`. Пары остаются, пока ими пользуются.

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monTue: return String(localized: "Пн — Вт")
        case .satSun: return String(localized: "Сб — Вс")
        case .friSat: return String(localized: "Пт — Сб")
        case .sunMon: return String(localized: "Вс — Пн")
        case .wedSat: return String(localized: "Ср — Сб")
        case .wedFri: return String(localized: "Ср — Пт")
        }
    }

    var subtitle: String {
        switch self {
        case .monTue: return String(localized: "Рефид в начале недели")
        case .satSun: return String(localized: "Рефид на выходных")
        case .friSat: return String(localized: "Рефид на выходных (Израиль)")
        case .sunMon: return String(localized: "Рефид в начале недели (Израиль)")
        case .wedSat: return String(localized: "Рефид в середине недели и в субботу")
        case .wedFri: return String(localized: "Рефид в середине недели и в пятницу")
        }
    }

    /// Смещения от среднего по дням Пн=0…Вс=6.
    /// Сумма = 0; рефид-дни выше нормы, остальные — ниже.
    var cycleOffsets: [Double] {
        switch self {
        case .monTue: return [0.14, 0.30, -0.08, -0.12, -0.08, -0.08, -0.08]
        case .satSun: return [-0.08, -0.08, -0.12, -0.08, -0.08, 0.14, 0.30]
        case .friSat: return [-0.08, -0.08, -0.12, -0.08, 0.30, 0.14, -0.08]
        case .sunMon: return [0.14, -0.08, -0.12, -0.08, -0.08, -0.08, 0.30]
        case .wedSat: return [-0.08, -0.08, 0.30, -0.08, -0.08, 0.14, -0.12]
        case .wedFri: return [-0.08, -0.08, 0.30, -0.08, 0.14, -0.08, -0.12]
        }
    }
}

/// Зачем идёт фаза плана. Знак темпа задаётся отсюда, а не хранится вместе
/// с числом: «сушка с плюс полпроцента» — противоречие, которое незачем уметь
/// записывать.
enum PlanIntent: String, Codable, CaseIterable, Identifiable {
    case cut
    case maintenance
    case bulk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cut:         return String(localized: "Дефицит")
        case .maintenance: return String(localized: "Поддержание")
        case .bulk:        return String(localized: "Набор")
        }
    }

    var symbol: String {
        switch self {
        case .cut:         return "arrow.down.right"
        case .maintenance: return "equal"
        case .bulk:        return "arrow.up.right"
        }
    }

    /// Куда фаза ведёт вес: −1, 0 или +1.
    var direction: Double {
        switch self {
        case .cut:         return -1
        case .maintenance: return 0
        case .bulk:        return 1
        }
    }

    /// Разумный темп по умолчанию, в процентах массы за неделю.
    ///
    /// У дефицита и набора он разный не для красоты: на сушке 0.7% в неделю —
    /// рабочая середина, а на наборе столько же означает, что большая часть
    /// прибавки будет жиром. Натурал со стажем набирает медленно.
    var defaultWeeklyRatePercent: Double {
        switch self {
        case .cut:         return 0.7
        case .maintenance: return 0
        case .bulk:        return 0.3
        }
    }

    /// Выше этого темпа предупреждаем. Границы разные по той же причине.
    var aggressiveRatePercent: Double {
        switch self {
        case .cut:         return 1.0
        case .maintenance: return 0
        case .bulk:        return 0.5
        }
    }
}

/// Одна фаза плана.
///
/// Темп задаётся в процентах массы за неделю, а не в килограммах. «0.7% в неделю» —
/// одно и то же утверждение и для 70 кг, и для 95, а «0.5 кг в неделю» — два разных.
/// Внутри фазы процент один раз превращается в килограммы по весу на её старте
/// и дальше держится: так фаза остаётся линейной, а пересчёт «от текущего веса»
/// происходит на границе фаз, где ему и место.
struct PlanPhase: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var intent: PlanIntent
    var durationWeeks: Int
    /// Модуль темпа. Знак берётся у намерения.
    var weeklyRatePercent: Double
    /// Сколько недель калории добираются до нормы этой фазы от нормы прошлой.
    ///
    /// Ноль — прыжком в первый же день. Так делать можно, но выход из дефицита
    /// прыжком на пятьсот калорий возвращает гликоген и воду, и весы за три дня
    /// показывают плюс два килограмма, которые к жиру отношения не имеют.
    var rampWeeks: Int = 0
    /// Неделя поддержания после каждых N недель дефицита. nil — без брейков.
    ///
    /// Брейки не лежат в `phases` отдельными фазами: фаза «12 недель сушки,
    /// брейк раз в 4» — одна мысль, и в редакторе она должна оставаться одной
    /// строкой. На недели их раскладывает `Plan.timeline`.
    var dietBreakEvery: Int?
    /// Сколько недель дефицита до первого брейка. nil — столько же, сколько между ними.
    ///
    /// Отдельно, потому что расписание включают и посреди сушки: у человека
    /// седьмая неделя дефицита, брейк раз в четыре — первый должен встать на
    /// следующей неделе, а не задним числом на пятой.
    var firstDietBreakAfter: Int?
    /// Эта фаза — диет-брейк: поставленный руками или разложенный из расписания.
    var isDietBreak: Bool = false

    /// Название для полосы фаз и строки плана: брейк — не просто «поддержание».
    var title: String {
        isDietBreak ? String(localized: "Диет-брейк") : intent.title
    }

    /// Варианты расписания: сколько недель дефицита на одну неделю поддержания.
    static let dietBreakOptions = [4, 5, 6]

    init(id: UUID = UUID(), intent: PlanIntent, durationWeeks: Int,
         weeklyRatePercent: Double? = nil, rampWeeks: Int = 0,
         dietBreakEvery: Int? = nil, firstDietBreakAfter: Int? = nil, isDietBreak: Bool = false) {
        self.id = id
        self.intent = intent
        self.durationWeeks = max(1, durationWeeks)
        self.weeklyRatePercent = abs(weeklyRatePercent ?? intent.defaultWeeklyRatePercent)
        self.rampWeeks = max(0, min(rampWeeks, self.durationWeeks))
        self.dietBreakEvery = dietBreakEvery
        self.firstDietBreakAfter = firstDietBreakAfter
        self.isDietBreak = isDietBreak
    }

    private enum CodingKeys: String, CodingKey {
        case id, intent, durationWeeks, weeklyRatePercent, rampWeeks
        case dietBreakEvery, firstDietBreakAfter, isDietBreak
    }

    // Явный init(from:): фазы, сохранённые до появления рампы, её не несут.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        intent = try container.decode(PlanIntent.self, forKey: .intent)
        durationWeeks = max(1, try container.decode(Int.self, forKey: .durationWeeks))
        weeklyRatePercent = abs(try container.decode(Double.self, forKey: .weeklyRatePercent))
        rampWeeks = max(0, min(try container.decodeIfPresent(Int.self, forKey: .rampWeeks) ?? 0, durationWeeks))
        dietBreakEvery = try container.decodeIfPresent(Int.self, forKey: .dietBreakEvery)
        firstDietBreakAfter = try container.decodeIfPresent(Int.self, forKey: .firstDietBreakAfter)
        isDietBreak = try container.decodeIfPresent(Bool.self, forKey: .isDietBreak) ?? false
    }

    /// Фаза, разложенная на недели дефицита и брейки между ними.
    ///
    /// Брейка в конце нет: после последнего блока дефицита идёт уже следующая
    /// фаза, и неделя поддержания перед ней — решение той фазы, а не этой.
    func expanded() -> [PlanPhase] {
        guard intent == .cut, !isDietBreak, let every = dietBreakEvery, every > 0 else { return [self] }
        var segments: [PlanPhase] = []
        var remaining = durationWeeks
        var run = min(max(0, firstDietBreakAfter ?? every), remaining)
        var index = 0
        while remaining > 0 {
            if run > 0 {
                var cut = self
                cut.id = Self.segmentID(id, index)
                cut.durationWeeks = run
                cut.rampWeeks = segments.isEmpty ? min(rampWeeks, run) : 0
                cut.dietBreakEvery = nil
                cut.firstDietBreakAfter = nil
                segments.append(cut)
                remaining -= run
                index += 1
            }
            guard remaining > 0 else { break }
            segments.append(PlanPhase(id: Self.segmentID(id, index), intent: .maintenance,
                                      durationWeeks: 1, isDietBreak: true))
            index += 1
            run = min(every, remaining)
        }
        return segments
    }

    /// Недель в развёрнутом виде — вместе с брейками.
    var expandedWeeks: Int { expanded().reduce(0) { $0 + $1.durationWeeks } }

    /// Устойчивый id куска: полоса фаз держит идентичность по нему, и новый
    /// UUID на каждое чтение перерисовывал бы её целиком.
    private static func segmentID(_ base: UUID, _ index: Int) -> UUID {
        guard index > 0 else { return base }
        var bytes = base.uuid
        bytes.15 = bytes.15 &+ UInt8(truncatingIfNeeded: index)
        bytes.14 = bytes.14 ^ 0xB5
        return UUID(uuid: bytes)
    }

    /// Темп со знаком, в долях массы за неделю.
    var signedWeeklyRate: Double { intent.direction * weeklyRatePercent / 100 }

    /// Сколько килограммов в неделю при таком весе на старте фазы.
    func weeklyRateKg(fromWeightKg weightKg: Double) -> Double {
        weightKg * signedWeeklyRate
    }

    var isAggressive: Bool {
        intent != .maintenance && weeklyRatePercent > intent.aggressiveRatePercent
    }
}

/// Рефид, перенесённый на другой день одной конкретной недели.
///
/// Праздник не совпадает с днём недели, выбранным под рефид заранее, а заводить
/// под каждый случай новую пару дней — тупик. Перенос меняет местами смещения
/// двух дней той же недели, поэтому среднее за неделю, а с ним и дефицит,
/// остаются ровно прежними. Со следующего понедельника снова обычная раскладка.
struct RefeedMove: Codable, Equatable {
    /// Понедельник недели, к которой относится перенос.
    var weekStart: Date
    /// День, ставший рефидом (Пн=0…Вс=6).
    var day: Int
    /// День, у которого рефид забрали.
    var swappedWith: Int
}

/// Персональный план: срок в неделях и целевой вес, с точным расчётом дневной нормы калорий
/// (в отличие от фиксированного множителя calorieMultiplier у Goal). Одна активная запись —
/// хранится в UserDefaults (JSON), как и профиль.
struct Plan: Codable, Equatable {
    var startDate: Date
    var startWeightKg: Double
    /// Цепочка фаз. Ради неё всё и затевалось: сушка, выход в поддержание,
    /// набор — это не три отдельных плана, а один, и самое интересное в нём
    /// происходит на стыках.
    ///
    /// Пустой она не бывает: инициализаторы подставляют хотя бы одну фазу.
    var phases: [PlanPhase]
    /// Автоматический недельный цикл калорий вокруг среднего плана — типичная практика
    /// бодибилдеров (меньше калорий в будни, рефид на выходных). Среднее за неделю
    /// остаётся точно равно dailyCalorieTarget — меняется только распределение по дням.
    var cyclingEnabled: Bool = false
    var weekendStyle: WeekendStyle = .satSun
    /// Рефид этой недели, перенесённый на другой день. Прошлые недели не держим:
    /// их дни уже зафиксированы снапшотами целей.
    var refeedMove: RefeedMove?

    /// Идущая неделя плана, считая с первой. Упирается в длительность: после
    /// финиша номер расти не должен, иначе «неделя 14 из 12».
    var currentWeek: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return min(max(days / 7 + 1, 1), durationWeeks)
    }

    /// Сколько полных недель осталось после идущей.
    var weeksRemaining: Int { max(durationWeeks - currentWeek, 0) }

    init(startDate: Date, startWeightKg: Double, phases: [PlanPhase],
         cyclingEnabled: Bool = false, weekendStyle: WeekendStyle = .satSun) {
        // Старт — начало суток, а не момент нажатия. Норму на день считают от
        // полуночи, и план, запущенный вечером, в первый день каждой новой
        // недели для «Сегодня» ещё числился в прошлой: брейк на экране плана
        // уже шёл, а кольцо показывало дефицит.
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.startWeightKg = startWeightKg
        self.phases = phases.isEmpty ? [PlanPhase(intent: .maintenance, durationWeeks: 8)] : phases
        self.cyclingEnabled = cyclingEnabled
        self.weekendStyle = weekendStyle
    }

    /// План из одной фазы, заданной целевым весом.
    ///
    /// Осталась ради экранов, которые пока думают в терминах «из А в Б за N недель»,
    /// и ради старых сохранённых планов. Темп выводится из веса и срока — то есть
    /// ровно обратно тому, как считает цепочка.
    init(startDate: Date, durationWeeks: Int, startWeightKg: Double, targetWeightKg: Double,
         cyclingEnabled: Bool = false, weekendStyle: WeekendStyle = .satSun) {
        let weeks = max(1, durationWeeks)
        let change = targetWeightKg - startWeightKg
        let intent: PlanIntent = change < 0 ? .cut : (change > 0 ? .bulk : .maintenance)
        // Процент от стартового веса: внутри фазы темп в килограммах постоянен,
        // поэтому обратный пересчёт точен и старый план не «поедет».
        let ratePercent = startWeightKg > 0
            ? abs(change) / Double(weeks) / startWeightKg * 100
            : 0
        self.init(startDate: startDate,
                  startWeightKg: startWeightKg,
                  phases: [PlanPhase(intent: intent, durationWeeks: weeks, weeklyRatePercent: ratePercent)],
                  cyclingEnabled: cyclingEnabled,
                  weekendStyle: weekendStyle)
    }

    private enum CodingKeys: String, CodingKey {
        case startDate, durationWeeks, startWeightKg, targetWeightKg, cyclingEnabled, weekendStyle, phases, refeedMove
    }

    // Явный init(from:), чтобы уже сохранённые планы не переставали декодироваться.
    // План до фаз хранил срок и целевой вес — из них собирается фаза из одной
    // штуки, и человек с активной сушкой не обнаружит, что она исчезла.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Сохранённые раньше планы несут время запуска — приводим к началу суток.
        startDate = Calendar.current.startOfDay(for: try container.decode(Date.self, forKey: .startDate))
        startWeightKg = try container.decode(Double.self, forKey: .startWeightKg)
        cyclingEnabled = try container.decodeIfPresent(Bool.self, forKey: .cyclingEnabled) ?? false
        weekendStyle = try container.decodeIfPresent(WeekendStyle.self, forKey: .weekendStyle) ?? .satSun
        refeedMove = try container.decodeIfPresent(RefeedMove.self, forKey: .refeedMove)

        if let stored = try container.decodeIfPresent([PlanPhase].self, forKey: .phases), !stored.isEmpty {
            phases = stored
        } else {
            let weeks = max(1, try container.decodeIfPresent(Int.self, forKey: .durationWeeks) ?? 8)
            let target = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg) ?? startWeightKg
            let change = target - startWeightKg
            let intent: PlanIntent = change < 0 ? .cut : (change > 0 ? .bulk : .maintenance)
            let ratePercent = startWeightKg > 0
                ? abs(change) / Double(weeks) / startWeightKg * 100
                : 0
            phases = [PlanPhase(intent: intent, durationWeeks: weeks, weeklyRatePercent: ratePercent)]
        }
    }

    // Пишем и фазы, и старые поля. Старые — не про совместимость назад, её здесь
    // нет: они нужны, чтобы файл резервной копии и экспорт остались читаемыми
    // глазами, где «цель 75 кг» понятнее, чем «дефицит 0.6% двенадцать недель».
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(startWeightKg, forKey: .startWeightKg)
        try container.encode(phases, forKey: .phases)
        try container.encode(cyclingEnabled, forKey: .cyclingEnabled)
        try container.encode(weekendStyle, forKey: .weekendStyle)
        try container.encodeIfPresent(refeedMove, forKey: .refeedMove)
        try container.encode(durationWeeks, forKey: .durationWeeks)
        try container.encode(targetWeightKg, forKey: .targetWeightKg)
    }

    /// Грубое общепринятое приближение: ~7700 ккал на 1 кг жировой массы.
    static let kcalPerKg: Double = 7700

    static func mondayBasedWeekdayIndex(for date: Date) -> Int {
        // Calendar.weekday: 1=Вс … 7=Сб. Приводим к Пн=0 … Вс=6.
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    var title: String {
        // Название по тому, чем план занят большую часть времени: цепочка
        // «сушка — поддержание — набор» не «снижение» и не «набор», и врать
        // одним из них хуже, чем назвать её планом.
        // Брейки названия не меняют: сушка с неделей поддержания — всё ещё сушка.
        let byIntent = Dictionary(grouping: phases.filter { !$0.isDietBreak }, by: \.intent)
            .mapValues { $0.reduce(0) { $0 + $1.durationWeeks } }
        guard byIntent.count == 1, let only = byIntent.first?.key else {
            return String(localized: "План")
        }
        switch only {
        case .cut:         return String(localized: "Снижение веса")
        case .bulk:        return String(localized: "Набор веса")
        case .maintenance: return String(localized: "Поддержание веса")
        }
    }

    /// Фазы по неделям — с разложенными диет-брейками. Всё, что считает даты,
    /// веса и калории, идёт по ней; `phases` — то, что человек настраивает.
    var timeline: [PlanPhase] { phases.flatMap { $0.expanded() } }

    var durationWeeks: Int { timeline.reduce(0) { $0 + $1.durationWeeks } }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: durationWeeks * 7, to: startDate) ?? startDate
    }

    /// Дата начала фазы по её индексу.
    func startDate(ofPhaseAt index: Int) -> Date {
        let weeksBefore = timeline.prefix(max(0, index)).reduce(0) { $0 + $1.durationWeeks }
        return Calendar.current.date(byAdding: .day, value: weeksBefore * 7, to: startDate) ?? startDate
    }

    /// Вес, с которого фаза стартует. Он же база для её темпа: процент считается
    /// от того, сколько человек весит к началу фазы, а не к началу всего плана.
    func weight(atStartOfPhaseAt index: Int) -> Double {
        var weight = startWeightKg
        for phase in timeline.prefix(max(0, index)) {
            weight += phase.weeklyRateKg(fromWeightKg: weight) * Double(phase.durationWeeks)
        }
        return weight
    }

    /// Какая фаза идёт на эту дату. Ничего — если дата вне плана.
    func phaseIndex(on date: Date) -> Int? {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: date).day ?? 0
        guard days >= 0 else { return nil }
        var weeksPassed = 0
        for (index, phase) in timeline.enumerated() {
            weeksPassed += phase.durationWeeks
            if days < weeksPassed * 7 { return index }
        }
        return nil
    }

    func phase(on date: Date) -> PlanPhase? {
        phaseIndex(on: date).map { timeline[$0] }
    }

    /// Фаза, которая идёт сейчас, — или последняя, если план уже закончился.
    var currentPhase: PlanPhase? {
        phase(on: Date()) ?? timeline.last
    }

    /// Куда план приводит вес: считается по цепочке, а не задаётся числом.
    ///
    /// Спрашивать целевой вес у цепочки нельзя: за тридцать недель вперёд его
    /// никто не знает. Знают темп, который готовы держать, — из него и выходит
    /// прогноз, и он честно называется прогнозом.
    var targetWeightKg: Double { weight(atStartOfPhaseAt: timeline.count) }

    /// Прогноз веса на дату — по фазам, которые до неё успели пройти.
    func projectedWeight(on date: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: date).day ?? 0
        guard days > 0 else { return startWeightKg }
        var weight = startWeightKg
        var daysLeft = Double(days)
        for phase in timeline {
            let phaseDays = Double(phase.durationWeeks * 7)
            let used = min(daysLeft, phaseDays)
            weight += phase.weeklyRateKg(fromWeightKg: weight) * used / 7
            daysLeft -= used
            if daysLeft <= 0 { return weight }
        }
        return weight
    }

    var totalWeightChangeKg: Double {
        targetWeightKg - startWeightKg
    }

    /// Темп идущей фазы в килограммах за неделю. Не средний по плану: средний
    /// у цепочки «сушка — поддержание — набор» близок к нулю и не говорит ничего.
    var weeklyRateKg: Double {
        weeklyRateKg(on: Date())
    }

    func weeklyRateKg(on date: Date) -> Double {
        let segments = timeline
        guard let index = phaseIndex(on: date) ?? (segments.isEmpty ? nil : segments.count - 1) else { return 0 }
        return segments[index].weeklyRateKg(fromWeightKg: weight(atStartOfPhaseAt: index))
    }

    /// Суточная поправка к TDEE (отрицательная — дефицит, положительная — профицит).
    var dailyCalorieDelta: Double { dailyCalorieDelta(on: Date()) }

    func dailyCalorieDelta(on date: Date) -> Double {
        let target = weeklyRateKg(on: date) * Self.kcalPerKg / 7
        guard let index = phaseIndex(on: date), index > 0 else { return target }
        let phase = timeline[index]
        guard phase.rampWeeks > 0 else { return target }

        let phaseStart = startDate(ofPhaseAt: index)
        let daysIn = Calendar.current.dateComponents([.day], from: phaseStart, to: date).day ?? 0
        let rampDays = Double(phase.rampWeeks * 7)
        guard Double(daysIn) < rampDays else { return target }

        // Линейно от нормы прошлой фазы к норме этой. Дельта прошлой берётся
        // на её последнем дне: у неё самой могла быть рампа, и начинать
        // переход от её начальной нормы значило бы переходить не оттуда,
        // где человек на самом деле оказался.
        let previousEnd = Calendar.current.date(byAdding: .day, value: -1, to: phaseStart) ?? phaseStart
        let from = weeklyRateKg(on: previousEnd) * Self.kcalPerKg / 7
        let progress = rampDays > 0 ? Double(daysIn) / rampDays : 1
        return from + (target - from) * progress
    }

    /// Устаканивается ли вес после того, как калории подняли.
    ///
    /// После дефицита возвращаются гликоген и вода — это килограмм-другой за
    /// несколько дней, и к жиру он отношения не имеет. Пока это происходит,
    /// судить о плане по весам нельзя: любой вердикт будет про воду.
    func isSettling(on date: Date) -> Bool {
        guard let index = phaseIndex(on: date), index > 0 else { return false }
        let phaseStart = startDate(ofPhaseAt: index)
        let previousEnd = Calendar.current.date(byAdding: .day, value: -1, to: phaseStart) ?? phaseStart
        // Только вверх: переход в дефицит воду не возвращает.
        guard weeklyRateKg(on: date) > weeklyRateKg(on: previousEnd) else { return false }
        let weeks = max(timeline[index].rampWeeks, Self.settlingWeeks)
        let daysIn = Calendar.current.dateComponents([.day], from: phaseStart, to: date).day ?? 0
        return daysIn < weeks * 7
    }

    /// Сколько недель весам не верят после подъёма калорий, если рампы нет.
    static let settlingWeeks = 2

    /// Насколько шире допуск по весу, пока он устаканивается.
    /// Полтора килограмма — обычный возврат гликогена и воды после дефицита.
    static let settlingToleranceKg = 1.5

    /// Дневная норма на сегодня — без учёта цикла.
    func dailyCalorieTarget(tdee: Double) -> Int {
        dailyCalorieTarget(for: Date(), tdee: tdee)
    }

    func dailyCalorieTarget(for date: Date, tdee: Double) -> Int {
        Int((tdee + dailyCalorieDelta(on: date)).rounded())
    }

    /// Норма на конкретную дату — с учётом фазы и недельного цикла, если он включён.
    func calorieTarget(for date: Date, tdee: Double) -> Int {
        let base = Double(dailyCalorieTarget(for: date, tdee: tdee))
        // Брейк — ровное поддержание каждый день. С циклом будни шли бы ниже
        // поддержания, а весь смысл брейка — неделя без чувства диеты.
        guard cyclingEnabled, !isDietBreak(on: date) else { return Int(base.rounded()) }
        let offset = cycleOffsets(forWeekOf: date)[Self.mondayBasedWeekdayIndex(for: date)]
        return Int((base * (1 + offset)).rounded())
    }

    // MARK: - Перенос рефида

    /// Понедельник недели, в которую попадает дата.
    static func weekStart(for date: Date) -> Date {
        let day = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: -mondayBasedWeekdayIndex(for: day), to: day) ?? day
    }

    /// Смещения Пн…Вс для недели с датой — с переносом, если он на этой неделе.
    func cycleOffsets(forWeekOf date: Date) -> [Double] {
        var offsets = weekendStyle.cycleOffsets
        if let move = refeedMove,
           Calendar.current.isDate(move.weekStart, inSameDayAs: Self.weekStart(for: date)),
           offsets.indices.contains(move.day), offsets.indices.contains(move.swappedWith) {
            offsets.swapAt(move.day, move.swappedWith)
        }
        return offsets
    }

    /// С каким днём поменяться, чтобы рефид пришёлся на эту дату. nil — нельзя.
    ///
    /// Только с днём, который ещё впереди: прошедшие дни уже съедены и
    /// зафиксированы, и забрать рефид у них значит получить второй рефид за
    /// неделю вместо перенесённого. Из будущих — самый высокий: переносят
    /// именно рефид, а не второй по величине день. Один перенос на неделю —
    /// второй начал бы тасовать уже тасованное.
    func refeedSwapDay(for date: Date) -> Int? {
        guard cyclingEnabled, canMoveRefeed(in: date), !isDietBreak(on: date) else { return nil }
        let offsets = weekendStyle.cycleOffsets
        let today = Self.mondayBasedWeekdayIndex(for: date)
        let monday = Self.weekStart(for: date)
        // Дни брейка в этой неделе не в счёт: рефида там нет, и забрать его
        // оттуда значило бы добавить неделе калорий.
        let later = offsets.indices.filter { index in
            guard index > today, let day = Calendar.current.date(byAdding: .day, value: index, to: monday) else { return false }
            return !isDietBreak(on: day)
        }
        guard let peak = later.max(by: { offsets[$0] < offsets[$1] }),
              offsets[peak] > 0, offsets[peak] > offsets[today] else { return nil }
        return peak
    }

    private func canMoveRefeed(in date: Date) -> Bool {
        guard let move = refeedMove else { return true }
        return !Calendar.current.isDate(move.weekStart, inSameDayAs: Self.weekStart(for: date))
    }

    /// План, где рефид этой недели перенесён на дату. Без изменений, если нельзя.
    func movingRefeed(to date: Date) -> Plan {
        guard let peak = refeedSwapDay(for: date) else { return self }
        var plan = self
        plan.refeedMove = RefeedMove(weekStart: Self.weekStart(for: date),
                                     day: Self.mondayBasedWeekdayIndex(for: date),
                                     swappedWith: peak)
        return plan
    }

    /// Можно ли вернуть перенос на дату: только пока новый рефид-день не прошёл.
    /// Иначе рефид уже съеден, и возврат дал бы второй.
    func canUndoRefeedMove(on date: Date) -> Bool {
        guard let move = refeedMove,
              Calendar.current.isDate(move.weekStart, inSameDayAs: Self.weekStart(for: date)) else { return false }
        return move.day >= Self.mondayBasedWeekdayIndex(for: date)
    }

    /// Раскладка нормы по дням недели (Пн…Вс) — для превью в UI.
    func weeklyCalorieBreakdown(tdee: Double) -> [(label: String, calories: Int)] {
        let cal = Calendar.current
        let labels = Array((1...7).map { i in cal.shortWeekdaySymbols[i % 7] })
        let base = Double(dailyCalorieTarget(tdee: tdee))
        return weekendStyle.cycleOffsets.enumerated().map { index, offset in
            (labels[index], Int((base * (1 + offset)).rounded()))
        }
    }

    /// Есть ли в плане фаза со слишком резким темпом.
    ///
    /// Порог берётся у намерения: процент, рабочий на сушке, на наборе означает,
    /// что большая часть прибавки уйдёт в жир. Один порог на оба был бы не
    /// строгостью, а невнимательностью.
    var hasAggressivePhase: Bool { phases.contains { $0.isAggressive } }

    /// Оставлено ради экранов, считающих в килограммах от веса. Аргумент больше
    /// ни на что не влияет: темп фазы и так задан в процентах массы.
    func isAggressivePace(relativeToWeightKg weightKg: Double) -> Bool {
        hasAggressivePhase
    }

    var progress: Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(max(Date().timeIntervalSince(startDate) / total, 0), 1)
    }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    /// План дошёл до даты финиша.
    ///
    /// До появления этого признака план не заканчивался никогда: неделя упиралась
    /// в потолок, дней оставалось ноль, а дефицит продолжал держаться — восьминедельная
    /// сушка молча превращалась в полугодовую.
    var isFinished: Bool { Date() >= endDate }

    /// План с другой датой финиша.
    ///
    /// Двигается последняя фаза: конец плана — это её конец, и растягивать ради
    /// него сушку в середине цепочки было бы не тем, о чём просили.
    func rescheduled(toEnd newEndDate: Date) -> Plan {
        guard !phases.isEmpty else { return self }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: newEndDate).day ?? 0
        let totalWeeks = max(1, Int((Double(days) / 7).rounded(.up)))
        let weeksBefore = phases.dropLast().reduce(0) { $0 + $1.expandedWeeks }
        var updated = self
        // Срок последней фазы задан неделями дефицита, а финиш — неделями вместе
        // с брейками. Подбираем первый срок, при котором фаза дотягивается до даты.
        var last = phases[phases.count - 1]
        last.durationWeeks = 1
        while weeksBefore + last.expandedWeeks < totalWeeks, last.durationWeeks < 520 {
            last.durationWeeks += 1
        }
        updated.phases[phases.count - 1] = last
        return updated
    }

    // MARK: - Диет-брейк вручную

    /// Неделя плана (с нуля), с которой встанет брейк, если попросить его сейчас.
    ///
    /// Не сегодняшний день, а ближайшая граница недели плана: фазы считаются
    /// целыми неделями от старта. Если сегодня и есть первый день недели — сегодня.
    func dietBreakStartWeek(from date: Date) -> Int {
        let days = max(0, Calendar.current.dateComponents([.day], from: startDate,
                                                          to: Calendar.current.startOfDay(for: date)).day ?? 0)
        return (days + 6) / 7
    }

    func startDate(ofWeek week: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: week * 7, to: startDate) ?? startDate
    }

    /// Какая фаза `phases` и сколько недель дефицита в ней пройдено к неделе плана.
    /// nil — неделя приходится не на дефицит (брейк, поддержание, конец плана).
    private func cutPosition(atWeek week: Int) -> (phase: Int, cutWeeks: Int)? {
        var weeksBefore = 0
        for (phaseIndex, phase) in phases.enumerated() {
            var cutWeeks = 0
            var cursor = weeksBefore
            for segment in phase.expanded() {
                if week < cursor + segment.durationWeeks {
                    guard segment.intent == .cut, !segment.isDietBreak else { return nil }
                    return (phaseIndex, cutWeeks + (week - cursor))
                }
                if !segment.isDietBreak { cutWeeks += segment.durationWeeks }
                cursor += segment.durationWeeks
            }
            weeksBefore = cursor
        }
        return nil
    }

    /// Можно ли поставить брейк вручную с ближайшей недели.
    ///
    /// Нужен дефицит на эту неделю и хотя бы неделя дефицита после неё:
    /// брейк в самом конце сушки — это уже не брейк, а выход из неё.
    func canStartDietBreak(from date: Date) -> Bool {
        guard let position = cutPosition(atWeek: dietBreakStartWeek(from: date)) else { return false }
        return position.cutWeeks < phases[position.phase].durationWeeks
    }

    /// План с брейком на `weeks` недель с ближайшей недели.
    ///
    /// Фаза режется на пройденную часть и остаток, между ними — поддержание.
    /// Пройденная часть сохраняет расписание как было, поэтому прошлое не
    /// двигается; остаток начинает счёт до следующего брейка заново.
    func startingDietBreak(from date: Date, weeks: Int) -> Plan {
        guard canStartDietBreak(from: date),
              let position = cutPosition(atWeek: dietBreakStartWeek(from: date)) else { return self }
        let original = phases[position.phase]
        var pieces: [PlanPhase] = []
        if position.cutWeeks > 0 {
            var done = original
            done.durationWeeks = position.cutWeeks
            pieces.append(done)
        }
        pieces.append(PlanPhase(intent: .maintenance, durationWeeks: max(1, weeks), isDietBreak: true))
        var rest = original
        rest.id = UUID()
        rest.durationWeeks = original.durationWeeks - position.cutWeeks
        rest.rampWeeks = 0
        rest.firstDietBreakAfter = nil
        pieces.append(rest)

        var updated = self
        updated.phases.replaceSubrange(position.phase...position.phase, with: pieces)
        return updated
    }

    /// Брейк, поставленный руками и ещё не начавшийся, — его можно убрать.
    func pendingManualDietBreak(on date: Date) -> Int? {
        var weeksBefore = 0
        let today = Calendar.current.startOfDay(for: date)
        for (index, phase) in phases.enumerated() {
            if phase.isDietBreak, startDate(ofWeek: weeksBefore) > today { return index }
            weeksBefore += phase.expandedWeeks
        }
        return nil
    }

    /// План без не начавшегося ручного брейка: куски фазы по краям склеиваются обратно.
    func cancelingPendingDietBreak(on date: Date) -> Plan {
        guard let index = pendingManualDietBreak(on: date) else { return self }
        var updated = self
        updated.phases.remove(at: index)
        if index > 0, index < updated.phases.count {
            let before = updated.phases[index - 1]
            let after = updated.phases[index]
            if before.intent == .cut, after.intent == .cut, !before.isDietBreak, !after.isDietBreak,
               before.weeklyRatePercent == after.weeklyRatePercent,
               before.dietBreakEvery == after.dietBreakEvery {
                var merged = before
                merged.durationWeeks += after.durationWeeks
                updated.phases.replaceSubrange((index - 1)...index, with: [merged])
            }
        }
        return updated
    }

    /// Сколько недель дефицита фаза уже прошла к дате. nil — фаза ещё не началась.
    /// Нужно, чтобы расписание, включённое посреди сушки, не ставило брейк в прошлое.
    func cutWeeksElapsed(inPhaseWithID id: UUID, on date: Date) -> Int? {
        var weeksBefore = 0
        for phase in phases {
            if phase.id == id {
                let days = Calendar.current.dateComponents([.day], from: startDate(ofWeek: weeksBefore),
                                                           to: Calendar.current.startOfDay(for: date)).day ?? 0
                guard days > 0 else { return nil }
                var cutDays = 0
                var cursor = 0
                for segment in phase.expanded() {
                    let length = segment.durationWeeks * 7
                    let used = min(max(days - cursor, 0), length)
                    if !segment.isDietBreak { cutDays += used }
                    cursor += length
                }
                return (cutDays + 6) / 7
            }
            weeksBefore += phase.expandedWeeks
        }
        return nil
    }

    /// Первый ближайший брейк — ручной или по расписанию, — который ещё не начался.
    func nextDietBreakStart(after date: Date) -> Date? {
        let today = Calendar.current.startOfDay(for: date)
        var weeks = 0
        for segment in timeline {
            let start = startDate(ofWeek: weeks)
            if segment.isDietBreak, start >= today { return start }
            weeks += segment.durationWeeks
        }
        return nil
    }

    /// Идёт ли брейк на дату.
    func isDietBreak(on date: Date) -> Bool {
        phase(on: date)?.isDietBreak == true
    }

    /// Ближайший с даты день, который не брейк: когда брейк кончится.
    func firstNonBreakDay(from date: Date) -> Date {
        var day = date
        for _ in 0..<10 where isDietBreak(on: day) {
            day = Calendar.current.date(byAdding: .day, value: 7, to: day) ?? day
        }
        return day
    }

    /// План, приводящий к другому весу к той же дате.
    ///
    /// Меняется темп последней фазы, а не срок: просьба «дойти до 74» — это про
    /// то, как быстро идти, а не про то, когда закончить.
    func retargeted(to weightKg: Double) -> Plan {
        guard let last = phases.last else { return self }
        let base = weight(atStartOfPhaseAt: timeline.count - last.expanded().count)
        guard base > 0, last.durationWeeks > 0 else { return self }
        let change = weightKg - base
        let intent: PlanIntent = change < 0 ? .cut : (change > 0 ? .bulk : .maintenance)
        let ratePercent = abs(change) / Double(last.durationWeeks) / base * 100
        var updated = self
        // Брейки переживают смену темпа: расписание — про то, как идти, а не куда.
        updated.phases[phases.count - 1] = PlanPhase(id: last.id,
                                                     intent: intent,
                                                     durationWeeks: last.durationWeeks,
                                                     weeklyRatePercent: ratePercent,
                                                     dietBreakEvery: intent == .cut ? last.dietBreakEvery : nil,
                                                     firstDietBreakAfter: intent == .cut ? last.firstDietBreakAfter : nil)
        return updated
    }
}

/// Из чего состояло изменение веса между двумя сеансами замеров.
///
/// Смысл всей затеи: «минус 6 кг» ничего не говорит натуралу на сушке. Говорит
/// «минус 6 кг, из них жира 5.4, сухой массы 0.6» — то есть работает диета или
/// ты ешь собственные мышцы.
