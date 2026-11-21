import Foundation

/// Ходит ли человек в зал — от этого зависят белок, темп и то, о чём с ним
/// говорить: тому, кто тягает железо, важнее всего не потерять силу.
enum TrainingHabit: String, Codable, CaseIterable, Identifiable {
    case regular, sometimes, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return String(localized: "Регулярно")
        case .sometimes: return String(localized: "Иногда")
        case .none: return String(localized: "Не хожу")
        }
    }

    var subtitle: String {
        switch self {
        case .regular: return String(localized: "Силовые два раза в неделю и чаще")
        case .sometimes: return String(localized: "Бывает, но без системы")
        case .none: return String(localized: "Без зала: работа, шаги, дом")
        }
    }
}

/// Что мешало раньше. Это и есть боль, которую человек пришёл решить, — по
/// ней выбирается предложение на финише онбординга и на экране Premium.
enum PastObstacle: String, Codable, CaseIterable, Identifiable {
    case rebound, binges, noResult, lostStrength, firstTime
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rebound: return String(localized: "Вес возвращался")
        case .binges: return String(localized: "Срывы от голода")
        case .noResult: return String(localized: "Не было видно результата")
        case .lostStrength: return String(localized: "Уходили сила и мышцы")
        case .firstTime: return String(localized: "Худею впервые")
        }
    }

    var subtitle: String {
        switch self {
        case .rebound: return String(localized: "Вес уходил, а через пару месяцев возвращался")
        case .binges: return String(localized: "Неделю-две держишься, потом срыв")
        case .noResult: return String(localized: "Весы стояли или прыгали, и опускались руки")
        case .lostStrength: return String(localized: "Вес уходил вместе с рабочими весами в зале")
        case .firstTime: return String(localized: "Раньше попыток не было")
        }
    }
}

/// Ответы онбординга, которые решают, что человеку предложить.
///
/// Хранятся отдельно от профиля: профилю они не нужны, а экрану Premium —
/// нужны, и спустя недели после онбординга он должен говорить с человеком
/// о той же боли, о которой тот сказал в начале.
struct OfferAnswers: Codable, Equatable {
    var training: TrainingHabit
    /// Только у сушки: на наборе и поддержании про прошлые попытки похудеть
    /// не спрашиваем.
    var obstacle: PastObstacle?

    static let storageKey = "offer_answers"

    static func load(from defaults: UserDefaults = .standard) -> OfferAnswers? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(OfferAnswers.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Что ответы меняют в плане

    /// Белок на килограмм. В зале — больше: на дефиците именно он держит
    /// мышцы. Тому, кто уже терял силу, — верх разумного.
    var proteinPerKg: Double {
        if obstacle == .lostStrength { return 2.2 }
        switch training {
        case .regular: return 2.0
        case .sometimes, .none: return UserProfile.defaultProteinPerKg
        }
    }

    /// Темп сушки по умолчанию. Тренирующимся и терявшим силу — бережный:
    /// чем медленнее, тем больше из ушедшего — жир, а не мышцы.
    var cutRatePercent: Double {
        training == .regular || obstacle == .lostStrength ? 0.5 : PlanIntent.cut.defaultWeeklyRatePercent
    }

    /// Недельный цикл калорий — тому, кто срывался: рефид-дни раз в неделю
    /// снимают голод раньше, чем он копится до срыва.
    var wantsCycling: Bool { obstacle == .binges }

    /// Сколько недель поднимать норму при выходе из сушки. Тому, у кого вес
    /// возвращался, — две: резкий прыжок к расходу и есть начало отката.
    var rampOutWeeks: Int { obstacle == .rebound ? 2 : 1 }

    /// Сушка из онбординга сразу с удержанием после неё.
    ///
    /// Предложение обещает «сбросить и удержать», и план должен содержать
    /// ровно то, что обещано: фаза поддержания нужной длины и плавный выход.
    /// Удалить её можно в редакторе плана, как любую фазу.
    func cutPhases(durationWeeks: Int, ratePercent: Double, dietBreakEvery: Int?) -> [PlanPhase] {
        let cut = PlanPhase(intent: .cut, durationWeeks: durationWeeks,
                            weeklyRatePercent: ratePercent, dietBreakEvery: dietBreakEvery)
        let hold = PlanPhase(intent: .maintenance,
                             durationWeeks: PhaseAdvice.restWeeks(afterCutOf: durationWeeks),
                             rampWeeks: rampOutWeeks)
        return [cut, hold]
    }
}

/// Одна строка предложения: результат и то, за счёт чего он получится.
struct OfferBenefit: Equatable {
    enum Kind: CaseIterable { case finish, keep, works, expenditure, noBinges, muscle, kosher, leanBulk, steadyWeight }
    let kind: Kind

    var icon: String {
        switch kind {
        case .finish: return "flag.checkered"
        case .keep: return "shield.lefthalf.filled"
        case .works: return "checkmark.seal"
        case .expenditure: return "chart.line.uptrend.xyaxis"
        case .noBinges: return "fork.knife"
        case .muscle: return "dumbbell"
        case .kosher: return "calendar"
        case .leanBulk: return "arrow.up.right"
        case .steadyWeight: return "equal.circle"
        }
    }

    var title: String {
        switch kind {
        case .finish: return String(localized: "Финиш с датой")
        case .keep: return String(localized: "Чтобы вес не вернулся")
        case .works: return String(localized: "Видно, что работает")
        case .expenditure: return String(localized: "Норма по твоему расходу")
        case .noBinges: return String(localized: "Сушка без срывов")
        case .muscle: return String(localized: "Уходит жир, а не сила")
        case .kosher: return String(localized: "Кашрут и посты в плане")
        case .leanBulk: return String(localized: "Мышцы, а не жир")
        case .steadyWeight: return String(localized: "Вес не уползёт незаметно")
        }
    }

    var detail: String {
        switch kind {
        case .finish: return String(localized: "Темп, при котором уходит жир, а не мышцы, и день, к которому ты придёшь к цели.")
        case .keep: return String(localized: "После сушки план сам ставит удержание нужной длины и плавно выводит из дефицита. Большинство диет кончается откатом именно здесь.")
        case .works: return String(localized: "Раз в неделю — вердикт по тренду, а не по утренним весам. По трём дням вес не судят, и приложение так и скажет.")
        case .expenditure: return String(localized: "Расход измеряется по дневнику и весам, а не по формуле. Тело привыкает к дефициту — норма это учитывает, но меняется только с твоего согласия.")
        case .noBinges: return String(localized: "Рефиды и диет-брейки по расписанию, а недобор одного дня переходит на остальные дни недели.")
        case .muscle: return String(localized: "Темп не быстрее процента массы в неделю и белок по твоему весу: рабочие веса в зале остаются.")
        case .kosher: return String(localized: "Ожидание между мясным и молочным и посты из календаря — в том же плане, без отдельных приложений.")
        case .leanBulk: return String(localized: "Профицит такой, чтобы росли мышцы. Если темп уйдёт за половину процента в неделю, приложение предупредит.")
        case .steadyWeight: return String(localized: "Норма по твоему настоящему расходу и вердикт раз в неделю: сдвиг видно раньше, чем его покажет зеркало.")
        }
    }
}

/// Итоговое предложение: заголовок, подзаголовок и строки-выгоды по порядку
/// важности для этого человека.
struct Offer: Equatable {
    let headline: String
    let subtitle: String
    let benefits: [OfferBenefit]

    /// Собрать предложение по цели и ответам.
    ///
    /// Без ответов (онбординг пройден до опроса) — общее «сбросить и удержать»,
    /// то же, что видели все до этого. Порядок строк — от боли человека: первой
    /// идёт та, ради которой он пришёл.
    static func make(intent: PlanIntent?, answers: OfferAnswers?, observesTradition: Bool) -> Offer {
        let training = answers?.training
        let headline: String
        let subtitle: String
        var kinds: [OfferBenefit.Kind]

        switch intent {
        case .bulk:
            headline = String(localized: "Набрать мышцы, а не жир")
            subtitle = String(localized: "Небольшой профицит и темп, при котором растут мышцы, а не живот. Каждую неделю видно, идёшь ли ты по плану.")
            kinds = [.leanBulk, .finish, .works, .expenditure]
        case .maintenance:
            headline = String(localized: "Держать вес без угадывания")
            subtitle = String(localized: "Норма по твоему расходу, а не по формуле, и сигнал, если вес поползёт.")
            kinds = [.steadyWeight, .expenditure, .works]
        case .cut, nil:
            switch answers?.obstacle {
            case .rebound:
                headline = String(localized: "Сбросить вес и в этот раз удержать")
                subtitle = String(localized: "Сушка с финишем, а после неё — удержание: план не бросает тебя в день, когда цель достигнута.")
                kinds = [.keep, .finish, .works, .noBinges]
            case .binges:
                headline = String(localized: "Сбросить вес без срывов")
                subtitle = String(localized: "Дефицит с передышками: рефиды и диет-брейки по расписанию, чтобы голод не копился неделями.")
                kinds = [.noBinges, .finish, .keep, .works]
            case .noResult:
                headline = String(localized: "Сбросить вес и видеть, что это работает")
                subtitle = String(localized: "Не утренние весы, а тренд и вердикт раз в неделю: скачок на килограмм объяснён, а не пугает.")
                kinds = [.works, .expenditure, .finish, .keep]
            case .lostStrength:
                headline = String(localized: "Сбросить жир, а не силу")
                subtitle = String(localized: "Бережный темп и белок по весу: уходит жир, а рабочие веса в зале остаются.")
                kinds = [.muscle, .finish, .keep, .works]
            case .firstTime, nil:
                if training == .regular {
                    headline = String(localized: "Сбросить жир, а не силу")
                    subtitle = String(localized: "Бережный темп и белок по весу: уходит жир, а рабочие веса в зале остаются.")
                    kinds = [.muscle, .finish, .keep, .works]
                } else {
                    headline = String(localized: "Сбросить вес и удержать его")
                    subtitle = String(localized: "Программа, а не счётчик: сушка с финишем, выход из неё и удержание. Каждую неделю видно, идёшь ли ты по плану.")
                    kinds = [.finish, .keep, .works, .expenditure, .noBinges]
                }
            }
            // Тому, кто в зале, — про силу, даже если болит другое.
            if training == .regular, !kinds.contains(.muscle) {
                kinds.insert(.muscle, at: 1)
            }
        }

        // Кашрут — третьей строкой: этого нет ни у кого, и соблюдающему это
        // важнее общих слов, но не важнее его главной боли.
        if observesTradition {
            kinds.insert(.kosher, at: min(2, kinds.count))
        }

        return Offer(headline: headline, subtitle: subtitle,
                     benefits: kinds.map(OfferBenefit.init(kind:)))
    }
}

extension Plan {
    /// Когда вес приходит к цели — конец последней фазы, которая его двигает.
    ///
    /// Удержание после сушки удлиняет план, но вес на нём уже не меняется: «к
    /// 13 мая» в предложении звучало бы так, будто до цели вдвое дольше.
    var targetReachedDate: Date {
        let segments = timeline
        guard let last = segments.lastIndex(where: { $0.intent != .maintenance && !$0.isDietBreak }) else {
            return endDate
        }
        let weeks = segments[...last].reduce(0) { $0 + $1.durationWeeks }
        return Calendar.current.date(byAdding: .day, value: weeks * 7, to: startDate) ?? endDate
    }

    /// Недели удержания после того, как вес пришёл к цели.
    var holdWeeksAfterTarget: Int {
        let segments = timeline
        guard let last = segments.lastIndex(where: { $0.intent != .maintenance && !$0.isDietBreak }) else {
            return 0
        }
        return segments[(last + 1)...].reduce(0) { $0 + $1.durationWeeks }
    }
}
