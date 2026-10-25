import Foundation

/// Что происходит в зале — глазами Calories.
///
/// Вторая половина линии, у которой уже есть первая: `BodyBridge` отдаёт
/// туда процент жира и сухую массу, а сюда приходит то, чего еда про себя не
/// знает. Объём недели вырос, а норма осталась прежней — вот и причина, по
/// которой вес встал; идёт делоад — значит и есть надо иначе; сегодня день
/// ног — углеводы нужнее, чем в день рук.
///
/// Читаем, но не пишем: `gym_state` принадлежит соседу, как `body_snapshot`
/// принадлежит нам. Поля опциональные намеренно — сосед договорился
/// добавлять новые, не трогая старые, и неизвестное поле не должно ронять
/// разбор целиком.
enum GymBridge {
    static let appGroup = CalorieStore.appGroup
    static let key = "gym_state"
    /// Плоские ключи рядом со снимком: сосед кладёт их, чтобы один факт
    /// можно было узнать, не разбирая весь JSON.
    static let snapshotAtKey = "gym_state_at"
    static let deloadKey = "gym_is_deload"
    static let lastWorkoutKey = "gym_last_workout_at"

    // MARK: - Формат обмена

    /// Близнец структуры в GymLogger. Имена полей — контракт: менять их
    /// можно только в обоих приложениях сразу.
    struct State: Codable, Equatable, Sendable {
        var date: Date

        struct Deload: Codable, Equatable, Sendable {
            var isActive: Bool
            /// Доля обычного объёма, 0–1.
            var volumeFraction: Double?
            var intensityFraction: Double?
        }

        struct Block: Codable, Equatable, Sendable {
            var name: String?
            var week: Int?
            var totalWeeks: Int?
            var daysPerWeek: Int?
            var isComplete: Bool?
            var trainsToFailure: Bool?
        }

        struct Today: Codable, Equatable, Sendable {
            /// Имя дня, как его назвал человек: «Пул», «Ноги».
            var name: String?
            /// Слот сплита из словаря соседа: Push, Pull, Legs, Upper…
            /// Сравниваем по строке — порядковые номера у них свои.
            var type: String?
            var isRest: Bool?
            var plannedSets: Int?
            var plannedExercises: Int?
            var isDone: Bool?
        }

        struct Week: Codable, Equatable, Sendable {
            var startsOn: Date?
            /// Взвешенные рабочие сеты: сет на одну сторону — половина,
            /// мышца-ассистент получает половину.
            var totalSets: Double?
            /// Мышцы с нулём в словарь не попадают: отсутствие ключа и есть ноль.
            var setsByMuscle: [String: Double]?
        }

        struct LastWorkout: Codable, Equatable, Sendable {
            var at: Date
            var minutes: Int?
            var name: String?
            /// Рабочие сеты, без разминочных.
            var sets: Int?
        }

        var deload: Deload?
        var block: Block?
        var today: Today?
        var week: Week?
        var lastWorkout: LastWorkout?
        var daysSinceLastWorkout: Int?
    }

    // MARK: - Чтение

    /// Сколько живёт каждая часть снимка.
    ///
    /// Сроки разные, и это не придирка. «Сегодня день ног» верно ровно
    /// сегодня: вчерашний снимок про сегодняшний день не знает ничего, и
    /// принимать его за правду — значит советовать углеводы в день отдыха.
    /// Делоад держится неделю и за сутки не исчезает. Объём недели тем более:
    /// он и считается за неделю.
    ///
    /// Устаревший снимок значит «не знаю», а не «отдых» — об отдыхе сосед
    /// говорит явно, полем `isRest`.
    enum Freshness {
        /// Сегодняшний день: только снимок этих суток.
        static func today(_ state: State, now: Date = Date(),
                          calendar: Calendar = .current) -> Bool {
            calendar.isDate(state.date, inSameDayAs: now)
        }
        /// Делоад и блок: неделя.
        static func week(_ state: State, now: Date = Date(),
                         calendar: Calendar = .current) -> Bool {
            days(between: state.date, and: now, calendar) <= 7
        }
        /// Недельный объём: десять дней — неделя плюс запас на то, что в
        /// GymLogger могли не заходить пару дней после последней тренировки.
        static func volume(_ state: State, now: Date = Date(),
                           calendar: Calendar = .current) -> Bool {
            days(between: state.date, and: now, calendar) <= 10
        }

        private static func days(between from: Date, and to: Date, _ calendar: Calendar) -> Int {
            abs(calendar.dateComponents([.day], from: from, to: to).day ?? .max)
        }
    }

    /// Снимок из общей папки. `nil` — соседа нет, он молчит или прислал то,
    /// чего мы не понимаем; во всех трёх случаях ответ один: мы не знаем.
    static func read(defaults: UserDefaults? = UserDefaults(suiteName: GymBridge.appGroup)) -> State? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        // Даты приходят строками ISO — так их кладёт сосед.
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(State.self, from: data)
    }

    // MARK: - Что из этого следует

    /// Идёт ли сейчас разгрузочная неделя. `nil` — неизвестно.
    static func isDeload(_ state: State?, now: Date = Date(),
                         calendar: Calendar = .current) -> Bool? {
        guard let state, Freshness.week(state, now: now, calendar: calendar) else { return nil }
        return state.deload?.isActive ?? false
    }

    /// Тип сегодняшней тренировки — только из сегодняшнего снимка.
    ///
    /// Возвращаем сам слот сплита, а не наше толкование: что с ним делать,
    /// решает экран, а не мост.
    static func todayType(_ state: State, now: Date = Date(),
                          calendar: Calendar = .current) -> String? {
        guard Freshness.today(state, now: now, calendar: calendar) else { return nil }
        guard state.today?.isRest != true else { return nil }
        return state.today?.type
    }

    /// Взвешенные сеты за неделю. `nil` — снимок слишком стар, чтобы о
    /// неделе судить.
    static func weeklySets(_ state: State?, now: Date = Date(),
                           calendar: Calendar = .current) -> Double? {
        guard let state, Freshness.volume(state, now: now, calendar: calendar) else { return nil }
        return state.week?.totalSets
    }

    /// День крупных групп — ног, спины или всего тела.
    ///
    /// Нужно ровно для одного: в такой день углеводы работают, а не просто
    /// вписываются в норму. Квадрицепсы и спина съедают гликогена столько,
    /// сколько руки не съедят за неделю, и день рук в этом смысле — обычный
    /// день. Поэтому список короткий и не претендует на физиологию: он
    /// отвечает на вопрос «стоит ли сегодня сказать про углеводы».
    static let heavyTypes: Set<String> = ["Legs", "Lower", "Full Body", "Back", "Pull", "Upper"]

    /// Стоит ли сегодня говорить про углеводы. nil — день неизвестен.
    static func isHeavyDay(_ state: State?, now: Date = Date(),
                           calendar: Calendar = .current) -> Bool? {
        guard let state, Freshness.today(state, now: now, calendar: calendar) else { return nil }
        if state.today?.isRest == true { return false }
        guard let type = state.today?.type else { return nil }
        return heavyTypes.contains(type)
    }

    /// Имя сегодняшнего дня, как человек назвал его в программе: «Пул»,
    /// «Ноги». Своё имя лучше нашего перевода слота — человек его и выбирал.
    static func todayName(_ state: State?, now: Date = Date(),
                          calendar: Calendar = .current) -> String? {
        guard let state, Freshness.today(state, now: now, calendar: calendar),
              state.today?.isRest != true else { return nil }
        let name = state.today?.name
        return (name?.isEmpty == false) ? name : state.today?.type
    }

    /// Самые нагруженные мышцы недели — чтобы вердикт мог назвать причину
    /// словами человека, а не «объём вырос».
    static func topMuscles(_ state: State?, limit: Int = 3, now: Date = Date(),
                           calendar: Calendar = .current) -> [(muscle: String, sets: Double)] {
        guard let state, Freshness.volume(state, now: now, calendar: calendar),
              let byMuscle = state.week?.setsByMuscle else { return [] }
        return byMuscle
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { (muscle: $0.key, sets: $0.value) }
    }
}
