import Foundation

// Профиль: рост, вес, возраст и то, что из них считается, — базовый обмен,
// расход, цель по калориям и белку.

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return String(localized: "Мужской")
        case .female: return String(localized: "Женский")
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return String(localized: "Минимальная")
        case .light: return String(localized: "Лёгкая")
        case .moderate: return String(localized: "Средняя")
        case .active: return String(localized: "Высокая")
        case .veryActive: return String(localized: "Очень высокая")
        }
    }

    /// Подпись называет обе оси — работу и зал.
    ///
    /// Раньше три средних уровня говорили только про тренировки, а крайние —
    /// про работу, и человек, который стоит девять часов в пекарне и ходит
    /// в зал шесть раз в неделю, не был описан нигде. Он выбирал наугад,
    /// а от этого выбора зависит норма на весь план: между соседними
    /// уровнями сотни калорий.
    var subtitle: String {
        switch self {
        case .sedentary: return String(localized: "Сидячая работа, зала почти нет")
        case .light: return String(localized: "Сидячая работа + 1–3 тренировки")
        case .moderate: return String(localized: "Сидячая работа + 3–5 тренировок")
        case .active: return String(localized: "На ногах весь день + 3–5 тренировок, или сидячая + 6–7")
        case .veryActive: return String(localized: "Физическая работа + 6–7 тренировок")
        }
    }

    /// Множитель для расчёта TDEE из BMR.
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case fatLoss, maintenance, muscleGain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fatLoss: return String(localized: "Снижение веса")
        case .maintenance: return String(localized: "Поддержание")
        case .muscleGain: return String(localized: "Набор веса")
        }
    }

    /// Множитель к TDEE для расчёта целевых калорий.
    var calorieMultiplier: Double {
        switch self {
        case .fatLoss: return 0.8
        case .maintenance: return 1.0
        case .muscleGain: return 1.1
        }
    }
}

/// Профиль пользователя для расчёта целевых калорий и белка.
/// Хранится как единственный объект в UserDefaults (JSON) — это одна запись, не список, SwiftData здесь избыточен.
/// От чего считать норму белка.
///
/// От общего веса — годится всем и не требует ничего, кроме весов. От сухой
/// массы — точнее: при одном весе на 12% и на 25% жира мышц разное количество,
/// а кормить надо мышцы. Требует снятых замеров.
enum ProteinBasis: String, Codable, CaseIterable, Identifiable {
    case bodyweight, leanMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyweight: return String(localized: "От веса")
        case .leanMass:   return String(localized: "От сухой массы")
        }
    }
}

struct UserProfile: Codable, Equatable {
    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: Sex
    var activityLevel: ActivityLevel
    var goal: Goal
    var proteinPerKg: Double
    /// Своё число для сухой массы.
    ///
    /// Отдельное, а не общее с `proteinPerKg`, потому что смысл у них разный:
    /// 2.0 г на кг веса — обычная норма, 2.0 г на кг сухой массы — уже недобор.
    /// Одно число на две основы означало бы, что переключатель молча меняет
    /// норму на четверть.
    var storedProteinPerLeanKg: Double?
    /// Опциональные намеренно: в уже сохранённых профилях этих ключей нет, а
    /// обязательное поле уронило бы декодирование целиком — то есть стёрло бы
    /// человеку профиль.
    var storedProteinBasis: ProteinBasis?
    /// Норма жира на кг веса. Тоже опциональная: до этой настройки её не было,
    /// и в сохранённых профилях ключа нет.
    var storedFatPerKg: Double?

    init(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: Sex,
        activityLevel: ActivityLevel,
        goal: Goal,
        proteinPerKg: Double,
        proteinPerLeanKg: Double? = nil,
        proteinBasis: ProteinBasis = .bodyweight,
        fatPerKg: Double? = nil
    ) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.activityLevel = activityLevel
        self.goal = goal
        self.proteinPerKg = proteinPerKg
        self.storedProteinPerLeanKg = proteinPerLeanKg
        self.storedProteinBasis = proteinBasis
        self.storedFatPerKg = fatPerKg
    }

    var proteinBasis: ProteinBasis {
        get { storedProteinBasis ?? .bodyweight }
        set { storedProteinBasis = newValue }
    }

    var proteinPerLeanKg: Double {
        get { storedProteinPerLeanKg ?? Self.defaultProteinPerLeanKg }
        set { storedProteinPerLeanKg = newValue }
    }

    /// Всегда в пределах жёстких границ. Сохранённое раньше 0.4 — колесо
    /// начиналось с него — читается как нижняя граница, а не как есть.
    var fatPerKg: Double {
        get {
            min(max(storedFatPerKg ?? MacroTargets.fatPerKg, MacroTargets.fatFloorPerKg),
                MacroTargets.fatCeilingPerKg)
        }
        set {
            storedFatPerKg = min(max(newValue, MacroTargets.fatFloorPerKg), MacroTargets.fatCeilingPerKg)
        }
    }

    /// Целевой жир в граммах. Считается только от общего веса: гормонам нужен
    /// абсолютный минимум жира, а не доля от сухой массы.
    var fatTargetGrams: Double { fatPerKg * weightKg }

    static let defaultProteinPerKg: Double = 1.7
    /// Выше, чем от общего веса, и это не опечатка: сухой массы меньше, чем веса,
    /// а кормить надо именно её. Диапазон по Хелмсу для сухих атлетов — 2.3–3.1.
    static let defaultProteinPerLeanKg: Double = 2.4

    /// Базовый метаболизм — формула Миффлина-Сан Жеора.
    var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Суточный расход энергии с учётом активности.
    var tdee: Double {
        bmr * activityLevel.multiplier
    }

    /// Целевые калории с учётом цели (дефицит/поддержание/профицит).
    var calorieTarget: Int {
        Int((tdee * goal.calorieMultiplier).rounded())
    }

    /// Сухая масса. Только по снятым замерам: оценка по ИМТ для этого слишком
    /// груба — она не отличает 77 кг мышц от 77 кг с животом, а вся суть режима
    /// именно в этом различии.
    func leanMassKg(from measurement: BodyMeasurement?) -> Double? {
        guard navyBodyFat(from: measurement) != nil else { return nil }
        let fat = bodyFatPercentage(from: measurement)
        let lean = weightKg * (1 - fat / 100)
        return lean > 0 ? lean : nil
    }

    /// Целевой белок в граммах. Без замеров персональный режим молча падает
    /// обратно на общий вес: лучше считать грубее, чем не считать вовсе.
    func proteinTargetGrams(from measurement: BodyMeasurement?) -> Double {
        switch proteinBasis {
        case .bodyweight:
            return proteinPerKg * weightKg
        case .leanMass:
            guard let lean = leanMassKg(from: measurement) else { return proteinPerKg * weightKg }
            return proteinPerLeanKg * lean
        }
    }

    var bmi: Double {
        let hm = heightCm / 100
        return weightKg / (hm * hm)
    }

    /// Navy-метод (точнее, ±2–3%): требует талию + шею (+ бёдра для женщин).
    ///
    /// Обхваты приходят параметром, а не хранятся в профиле. Раньше хранились — и
    /// разъезжались: экран расчёта строил их из свежих замеров, а отчёт читал
    /// сохранённую копию, из-за чего один и тот же процент жира показывался
    /// двумя разными числами. У величины должен быть один источник.
    func navyBodyFat(from measurement: BodyMeasurement?) -> Double? {
        guard let measurement else { return nil }
        let inputs = measurement.navyInputs(for: sex)
        guard let waist = inputs.waist, let neck = inputs.neck, waist > neck else { return nil }
        let bf: Double
        switch sex {
        case .male:
            bf = 86.010 * log10(waist - neck) - 70.041 * log10(heightCm) + 36.76
        case .female:
            guard let hip = inputs.hip, waist + hip > neck else { return nil }
            bf = 163.205 * log10(waist + hip - neck) - 97.684 * log10(heightCm) - 78.387
        }
        return max(3, min(bf, 60))
    }

    /// % жира: Navy если замеры есть, иначе Дойренберг (BMI-based, ±5%).
    func bodyFatPercentage(from measurement: BodyMeasurement?) -> Double {
        if let navy = navyBodyFat(from: measurement) { return navy }
        let sexFactor: Double = sex == .male ? 1.0 : 0.0
        let bf = 1.20 * bmi + 0.23 * Double(age) - 10.8 * sexFactor - 5.4
        return max(3, min(bf, 60))
    }

    func isNavyMethod(from measurement: BodyMeasurement?) -> Bool {
        navyBodyFat(from: measurement) != nil
    }

    func bodyFatCategory(from measurement: BodyMeasurement?) -> String {
        let bf = bodyFatPercentage(from: measurement)
        switch sex {
        case .male:
            if bf < 6  { return "Незаменимый жир" }
            if bf < 14 { return "Атлетический" }
            if bf < 18 { return "Фитнес" }
            if bf < 25 { return "Норма" }
            return "Выше нормы"
        case .female:
            if bf < 14 { return "Незаменимый жир" }
            if bf < 21 { return "Атлетический" }
            if bf < 25 { return "Фитнес" }
            if bf < 32 { return "Норма" }
            return "Выше нормы"
        }
    }
}

/// Паттерн недельного цикла калорий.
/// Пн=0…Вс=6; смещения в каждом случае суммируются в 0, среднее остаётся неизменным.
