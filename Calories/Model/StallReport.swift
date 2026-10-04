import Foundation

/// Разбор расхождения: почему вес за последние две недели пошёл не так, как
/// планировалось.
///
/// Это главный вопрос, из-за которого бросают. Счётчики калорий умеют считать и
/// молчат о причинах, а человек остаётся с единственным объяснением, которое
/// приходит в голову само: «значит, я вру себе». Между тем расхождение почти
/// всегда раскладывается на измеренные слагаемые, и каждое из них у приложения
/// уже есть.
///
/// Здесь нет ни одного предсказания: всё, что ниже, — **разложение уже
/// случившегося**. Планировалось минус четыреста граммов, вышло минус пятьдесят,
/// расхождение триста пятьдесят — и вот откуда они взялись. То, что не
/// разложилось, так и называется необъяснённым: вода, ошибка весов и адаптация
/// существуют, и делать вид, что их нет, значит врать точнее, чем позволяют
/// данные.
enum StallReport {

    /// Всё, что нужно для разбора. Чистые числа, без стора: так разбор
    /// проверяется тестами, а не глазами.
    struct Input {
        /// Длина окна в днях.
        var days: Int = 14
        /// Темп по плану, кг в неделю. Ноль — поддержание.
        var plannedWeeklyRateKg: Double = 0
        /// Измеренный темп по тренду веса, кг в неделю.
        var actualWeeklyRateKg: Double?
        /// Среднее съеденное за записанные дни окна и средняя норма тех же дней.
        var meanIntake: Double?
        var meanGoal: Double?
        var loggedDays: Int = 0
        var weighIns: Int = 0
        /// Шаги за окно против обычных.
        var meanSteps: Int?
        var baselineSteps: Int?
        /// Вес — чтобы перевести шаги в килокалории.
        var weightKg: Double?
        /// Расход по формуле и по факту; и считается ли норма от факта.
        var formulaTDEE: Double?
        var measuredTDEE: Double?
        var usesMeasuredTDEE: Bool = true
        /// Ночей, которые были заметно короче обычного.
        var shortSleepNights: Int = 0
    }

    /// Одно слагаемое расхождения.
    ///
    /// Знак положительный — вес оказался выше запланированного: этот вклад
    /// тянул вверх. Отрицательный — тянул вниз.
    struct Cause: Identifiable, Equatable {
        let id: String
        let kg: Double
        let text: String
    }

    struct Result: Equatable {
        /// Сколько веса должно было уйти по плану и сколько ушло на самом деле.
        let plannedKg: Double
        let actualKg: Double
        let causes: [Cause]
        /// То, что не разложилось.
        let unexplainedKg: Double
        /// Оговорки, которые не килограммы, но меняют доверие к числам.
        let remarks: [String]
        /// Данных так мало, что разбирать нечего.
        let tooLittleData: Bool

        /// Расхождение: плюс — вес выше ожидаемого.
        var gapKg: Double { actualKg - plannedKg }
    }

    /// Ниже этого вклад не называем: на двух неделях это шум весов.
    static let notableKg = 0.05
    /// Сколько взвешиваний нужно, чтобы тренду можно было верить.
    static let enoughWeighIns = 4

    static func make(_ input: Input) -> Result {
        let weeks = Double(input.days) / 7
        let plannedKg = input.plannedWeeklyRateKg * weeks
        let actualKg = (input.actualWeeklyRateKg ?? 0) * weeks

        var causes: [Cause] = []

        // 1. Еда. Самое частое и самое простое: среднее съеденное против средней
        // нормы тех же дней. Не против сегодняшней — норма за две недели могла
        // меняться.
        if let intake = input.meanIntake, let goal = input.meanGoal, input.loggedDays > 0 {
            let perDay = intake - goal
            let kg = perDay * Double(input.days) / Plan.kcalPerKg
            if abs(kg) >= notableKg {
                let rounded = Int(abs(perDay).rounded())
                causes.append(Cause(id: "intake", kg: kg,
                                    text: String(format: perDay > 0
                                                 ? String(localized: "Съедено в среднем на %lld ккал в день больше нормы")
                                                 : String(localized: "Съедено в среднем на %lld ккал в день меньше нормы"),
                                                 rounded)))
            }
        }

        // 2. Движение. Считаем отклонение от собственного обычного дня тем же
        // коэффициентом, которым приложение правит дневную норму, — иначе два
        // экрана говорили бы о шагах разными числами.
        if let steps = input.meanSteps, let usual = input.baselineSteps, let weight = input.weightKg, usual > 0 {
            let perDay = Double(usual - steps) * ActivityAdjustment.kcalPerStepPerKg * weight
            let kg = perDay * Double(input.days) / Plan.kcalPerKg
            if abs(kg) >= notableKg {
                causes.append(Cause(id: "activity", kg: kg,
                                    text: String(format: String(localized: "Шагов в среднем %1$lld против обычных %2$lld"),
                                                 steps, usual)))
            }
        }

        // 3. Ошибка расхода. Когда норма всё ещё считается по формуле, а факт
        // говорит другое, человек честно ест свою норму — и всё равно не
        // попадает в план. Это не его промах, а промах формулы.
        if !input.usesMeasuredTDEE, let formula = input.formulaTDEE, let measured = input.measuredTDEE {
            let perDay = formula - measured
            let kg = perDay * Double(input.days) / Plan.kcalPerKg
            if abs(kg) >= notableKg {
                causes.append(Cause(id: "expenditure", kg: kg,
                                    text: String(format: String(localized: "Норма посчитана по формуле (%1$lld ккал), а по факту расход %2$lld"),
                                                 Int(formula.rounded()), Int(measured.rounded()))))
            }
        }

        causes.sort { abs($0.kg) > abs($1.kg) }

        var remarks: [String] = []
        if input.weighIns < enoughWeighIns {
            remarks.append(String(format: String(localized: "Взвешиваний за %1$lld дней: %2$lld — тренду пока верить рано"),
                                  input.days, input.weighIns))
        }
        if input.loggedDays < input.days {
            remarks.append(String(format: String(localized: "Записано дней: %1$lld из %2$lld"),
                                  input.loggedDays, input.days))
        }
        if input.shortSleepNights >= 2 {
            remarks.append(String(format: String(localized: "Ночей короче обычного: %lld — вес утром держит воду"),
                                  input.shortSleepNights))
        }

        // Мало данных — это не «нет причин», а «не из чего считать». Разницу
        // надо называть вслух: иначе пустой разбор читается как «всё в порядке».
        let tooLittle = input.weighIns < 2 || input.loggedDays < max(3, input.days / 3)
        let explained = causes.reduce(0) { $0 + $1.kg }
        let gap = actualKg - plannedKg

        return Result(plannedKg: plannedKg,
                      actualKg: actualKg,
                      causes: tooLittle ? [] : causes,
                      unexplainedKg: tooLittle ? 0 : gap - explained,
                      remarks: remarks,
                      tooLittleData: tooLittle)
    }
}
