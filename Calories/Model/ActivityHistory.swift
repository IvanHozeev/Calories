import Foundation

/// Активность за один день: сколько прошёл, сколько потратил, чем занимался.
///
/// Всё, кроме шагов, необязательное: браслет пишет в «Здоровье» не всё и не
/// каждый день, а дни, записанные до того, как поле завели, его не знают
/// вовсе. Старая запись обязана читаться дальше.
struct ActivityDay: Identifiable, Codable, Equatable, Sendable {
    let date: Date
    var steps: Int
    /// Активные калории — то, что «Здоровье» считает сверх покоя.
    var activeCalories: Int?
    /// Сколько минут в этот день шла записанная тренировка.
    var workoutMinutes: Int?
    /// Чем занимался — «Баскетбол», «Силовая». Для объяснения, не для счёта.
    var workoutTitle: String?
    /// Сколько спал ночью перед этим днём.
    var sleepHours: Double?
    /// Когда в этот день встал. Ради этого сон и читается: время будильника
    /// iOS не отдаёт, и расписание приёмов пищи до сих пор угадывало подъём по
    /// первой еде.
    var wakeTime: Date?
    /// Когда лёг накануне.
    var bedTime: Date?
    /// Пульс в покое этой ночью — считается по ночным замерам, потому что
    /// готовой величины браслет не пишет.
    var restingPulse: Int?
    /// Чьи это шаги: идентификатор выбранного источника или nil, если считались
    /// все подряд.
    ///
    /// Нужен, потому что источники считают по-разному: браслет на запястье
    /// видит то, чего телефон в кармане не замечает, и разница доходит до
    /// четверти. Среднее, собранное наполовину из телефонных дней, наполовину
    /// из браслетных, не описывает ни то ни другое.
    var stepSource: String?

    var id: Date { date }

    init(date: Date, steps: Int, activeCalories: Int? = nil,
         workoutMinutes: Int? = nil, workoutTitle: String? = nil,
         sleepHours: Double? = nil, wakeTime: Date? = nil, bedTime: Date? = nil,
         restingPulse: Int? = nil, stepSource: String? = nil) {
        self.date = date
        self.steps = steps
        self.activeCalories = activeCalories
        self.workoutMinutes = workoutMinutes
        self.workoutTitle = workoutTitle
        self.sleepHours = sleepHours
        self.wakeTime = wakeTime
        self.bedTime = bedTime
        self.restingPulse = restingPulse
        self.stepSource = stepSource
    }
}

/// Хранилище истории активности.
///
/// «Здоровье» отдаёт шаги на запрос и ничего не хранит за нас: приложение
/// читало их на лету и нигде не сохраняло. Из-за этого активность не попадала
/// ни в резервную копию, ни в расчёты — а она и есть та косвенная метрика, по
/// которой видно, в какой день нагрузка была выше по факту: смена на ногах и
/// суббота с залом и баскетболом стоят по-разному, и расход нельзя мазать по
/// неделе ровным слоем.
///
/// Отдельным типом, а не полем `StepStore`, потому что читают историю двое:
/// экран шагов — чтобы показать, и `CalorieStore` — чтобы положить в копию.
/// Тащить ради этого «Здоровье» в дневник не стоит.
struct ActivityHistory: Sendable {
    /// Сколько дней держим. Года хватит любому расчёту: окно расхода смотрит на
    /// четыре недели, а сравнивать недели между собой хочется и дальше. Дольше
    /// — уже архив, а настройки не место для архива.
    static let limit = 400
    static let key = "step_history"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Вся сохранённая активность, от давней к свежей. Переживает и перезапуск,
    /// и потерю доступа к «Здоровью».
    var days: [ActivityDay] {
        guard let data = defaults.data(forKey: Self.key),
              let days = try? JSONDecoder().decode([ActivityDay].self, from: data)
        else { return [] }
        return days.sorted { $0.date < $1.date }
    }

    /// Дописывает прочитанное к сохранённому — именно дописывает, а не
    /// заменяет: «Здоровье» отдаёт последние тридцать дней, а хранить стоит
    /// дольше.
    func remember(_ incoming: [ActivityDay]) {
        guard !incoming.isEmpty else { return }
        let calendar = Calendar.current
        var byDay: [Date: ActivityDay] = [:]
        for day in days { byDay[calendar.startOfDay(for: day.date)] = day }
        for day in incoming {
            let key = calendar.startOfDay(for: day.date)
            let stored = byDay[key]
            // Сегодняшний день ещё идёт, и шагов в нём будет больше: берём
            // большее из двух, чтобы вечерний замер не затёрся утренним и
            // чтобы пустой ответ «Здоровья» не обнулил уже записанное.
            byDay[key] = ActivityDay(
                date: key,
                steps: max(day.steps, stored?.steps ?? 0),
                activeCalories: max(day.activeCalories ?? 0, stored?.activeCalories ?? 0).nonZero,
                workoutMinutes: max(day.workoutMinutes ?? 0, stored?.workoutMinutes ?? 0).nonZero,
                workoutTitle: day.workoutTitle ?? stored?.workoutTitle,
                // Сон приходит отдельным запросом: запись про шаги о нём не
                // знает и стирать его не должна.
                sleepHours: day.sleepHours ?? stored?.sleepHours,
                wakeTime: day.wakeTime ?? stored?.wakeTime,
                bedTime: day.bedTime ?? stored?.bedTime,
                restingPulse: day.restingPulse ?? stored?.restingPulse,
                stepSource: stored?.stepSource)
        }
        let kept = byDay.values.sorted { $0.date < $1.date }.suffix(Self.limit)
        guard let data = try? JSONEncoder().encode(Array(kept)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Записывает шаги, помня, кто их считал.
    ///
    /// Отдельно от `remember`, потому что правило слияния здесь другое. Внутри
    /// одного источника берётся большее: день ещё идёт, и вечерний замер
    /// больше утреннего. А вот при смене источника большее брать нельзя —
    /// иначе телефонные цифры, которые выше, навсегда перекрыли бы браслетные,
    /// и переключение источника ничего бы не меняло.
    func rememberSteps(_ incoming: [ActivityDay], source: String?) {
        guard !incoming.isEmpty else { return }
        let calendar = Calendar.current
        var byDay: [Date: ActivityDay] = [:]
        for day in days { byDay[calendar.startOfDay(for: day.date)] = day }
        for day in incoming {
            let key = calendar.startOfDay(for: day.date)
            var merged = byDay[key] ?? ActivityDay(date: key, steps: 0)
            merged.steps = byDay[key]?.stepSource == source
                ? max(day.steps, byDay[key]?.steps ?? 0)
                : day.steps
            merged.stepSource = source
            byDay[key] = merged
        }
        let kept = byDay.values.sorted { $0.date < $1.date }.suffix(Self.limit)
        guard let data = try? JSONEncoder().encode(Array(kept)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Заменяет историю целиком — восстановление из копии.
    func replace(with days: [ActivityDay]) {
        let kept = days.sorted { $0.date < $1.date }.suffix(Self.limit)
        guard let data = try? JSONEncoder().encode(Array(kept)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Обычная продолжительность сна — среднее за окно. nil, когда ночей мало.
    ///
    /// По нему судят, была ли ночь короткой: «восемь часов» — чужая цифра, а
    /// недосып у каждого свой относительно собственной привычки.
    func usualSleepHours(window: Int = 28, minimumNights: Int = 7, now: Date = Date()) -> Double? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -window, to: today) else { return nil }
        let hours = days.filter { $0.date >= from }.compactMap(\.sleepHours)
        guard hours.count >= minimumNights else { return nil }
        return hours.reduce(0, +) / Double(hours.count)
    }

    /// Пульс в покое за последние дни — для сравнения недели с месяцем.
    func restingPulses(lastDays count: Int, now: Date = Date()) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -count, to: today) else { return [] }
        return days.filter { $0.date >= from }.compactMap(\.restingPulse)
    }

    /// Шаги за конкретный день, если они записаны.
    func steps(on date: Date) -> Int? {
        let day = Calendar.current.startOfDay(for: date)
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: day) }?.steps
    }
}

private extension Int {
    /// Ноль здесь значит «не знаем», а не «не двигался»: активные калории и
    /// тренировки приходят отдельными запросами, и у старых дней их просто нет.
    var nonZero: Int? { self == 0 ? nil : self }
}
