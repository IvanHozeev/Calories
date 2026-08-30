import Foundation
import SwiftUI

/// Одна строка отчёта о телосложении.
struct BodyInsight: Identifiable {
    enum Verdict {
        case excellent, good, watch, notEnoughData

        var color: Color {
            switch self {
            case .excellent:     return .green
            case .good:          return .blue
            case .watch:         return .orange
            case .notEnoughData: return .secondary
            }
        }
    }

    /// Стабильный идентификатор: UUID при каждом пересчёте ломает диффинг списка в SwiftUI.
    let id: String
    let title: String
    let value: String
    let verdict: Verdict
    let verdictLabel: String
    let explanation: String
}

/// Расчёты по телосложению. Только читает замеры и профиль — состояние не трогает.
///
/// Процент жира намеренно НЕ считается здесь: он уже есть в UserProfile (Navy по талии
/// и шее, с женской ветвью). Второй расчёт дал бы два разных числа для одного человека.
enum BodyAnalysis {

    /// Расхождение сторон, при котором стоит забеспокоиться. Меньше сантиметра —
    /// это погрешность ленты, а не асимметрия.
    static let symmetryToleranceCm = 1.0
    static let symmetryWarningCm = 2.0

    // MARK: - Симметрия

    struct SymmetryResult: Identifiable {
        let site: MeasurementSite
        let left: Double
        let right: Double

        var id: String { site.rawValue }
        var difference: Double { abs(left - right) }
        var strongerSide: BodySide { left > right ? .left : .right }
        var isComplete: Bool { left > 0 && right > 0 }

        var verdict: BodyInsight.Verdict {
            guard isComplete else { return .notEnoughData }
            if difference <= symmetryToleranceCm { return .excellent }
            if difference <= symmetryWarningCm { return .good }
            return .watch
        }
    }

    static func symmetry(_ m: BodyMeasurement) -> [SymmetryResult] {
        MeasurementSite.allCases
            .filter(\.isPaired)
            .map { SymmetryResult(site: $0, left: m.value($0, .left), right: m.value($0, .right)) }
            .filter(\.isComplete)
    }

    // MARK: - Идеалы МакКаллума

    /// Пропорции от обхвата запястья: костяк задаёт потолок, который имеет смысл держать
    /// как ориентир. Грудь = запястье × 6.5, остальное — доли груди.
    struct McCallumIdeal {
        let chest: Double
        let waist: Double
        let arm: Double
        let forearm: Double
        let neck: Double
        let thigh: Double
        let calf: Double
    }

    static func mccallum(wristCm: Double) -> McCallumIdeal? {
        guard wristCm > 0 else { return nil }
        let chest = wristCm * 6.5
        return McCallumIdeal(
            chest: chest,
            waist: chest * 0.70,
            arm: chest * 0.36,
            forearm: chest * 0.29,
            neck: chest * 0.37,
            thigh: chest * 0.53,
            calf: chest * 0.34
        )
    }

    // MARK: - Оценка недостающих замеров

    /// Оценка обхвата, выведенная из уже снятых замеров.
    /// `source` нужен, чтобы в интерфейсе можно было объяснить, откуда взялось число:
    /// подсказка без объяснения выглядит как выдумка.
    struct Estimate {
        let value: Double
        let source: String
    }

    /// Достроить необмеренные места из тех, что уже есть.
    ///
    /// Важно понимать границы метода. Обхваты действительно коррелируют между собой —
    /// на этом стоит и МакКаллум, и правило «предплечье около 80% бицепса». Но это
    /// корреляция, а не закон: разброс между людьми с одинаковым запястьем достигает
    /// нескольких сантиметров. Поэтому результат годится как ориентир «примерно столько
    /// и ожидай», а не как замена ленте, и сохранять его как измеренное значение нельзя.
    ///
    /// Источники перебираются по убыванию надёжности: сначала прямые соотношения между
    /// соседними мышцами, потом вывод от костяка через МакКаллума.
    static func estimates(for m: BodyMeasurement) -> [MeasurementSite: Estimate] {
        var out: [MeasurementSite: Estimate] = [:]

        func known(_ site: MeasurementSite) -> Double? {
            let v = m.best(site)
            return v > 0 ? v : nil
        }
        /// Не затираем ни снятый замер, ни более надёжную оценку, найденную раньше.
        func offer(_ site: MeasurementSite, _ value: Double, _ source: String) {
            guard known(site) == nil, out[site] == nil, site.isPlausible(value) else { return }
            out[site] = Estimate(value: value, source: source)
        }

        // Соседние мышцы: связь теснее, чем через костяк, потому что растут вместе.
        if let biceps = known(.biceps) {
            offer(.forearm, biceps * 0.805, String(localized: "≈ 80% бицепса"))
            offer(.neck, biceps, String(localized: "≈ бицепс"))
            offer(.calf, biceps, String(localized: "≈ бицепс"))
        }
        if let forearm = known(.forearm) {
            offer(.biceps, forearm / 0.805, String(localized: "от предплечья"))
        }
        if let calf = known(.calf) {
            offer(.biceps, calf, String(localized: "≈ икра"))
            offer(.neck, calf, String(localized: "≈ икра"))
        }
        if let thigh = known(.thigh) {
            offer(.quad, thigh * 0.88, String(localized: "≈ 88% бедра"))
        }
        if let quad = known(.quad) {
            offer(.thigh, quad / 0.88, String(localized: "от квадрицепса"))
        }
        if let waist = known(.waist) {
            offer(.belt, waist + 4, String(localized: "талия + 4 см"))
        }
        if let belt = known(.belt) {
            offer(.waist, belt - 4, String(localized: "пояс − 4 см"))
        }

        // Костяк: работает даже когда мышц ещё не мерил, но и промахивается сильнее.
        if let ideal = mccallum(wristCm: m.best(.wrist)) {
            let from = String(localized: "от запястья")
            offer(.chest, ideal.chest, from)
            offer(.waist, ideal.waist, from)
            offer(.biceps, ideal.arm, from)
            offer(.forearm, ideal.forearm, from)
            offer(.neck, ideal.neck, from)
            offer(.thigh, ideal.thigh, from)
            offer(.calf, ideal.calf, from)
        }

        // Обхваты, которых у МакКаллума нет. Плечи считаем от груди — соотношение
        // устойчивее прочих, потому что дельты и грудь тренируются вместе.
        if let chest = known(.chest) {
            offer(.shoulders, chest * 1.17, String(localized: "от груди"))
        }
        if let glutes = known(.glutes) {
            offer(.pelvis, glutes * 0.86, String(localized: "от ягодиц"))
        }
        if let pelvis = known(.pelvis) {
            offer(.glutes, pelvis / 0.86, String(localized: "от таза"))
        }

        return out
    }

    // MARK: - FFMI

    /// Индекс сухой массы: сколько мышц на рост, за вычетом жира. В отличие от веса и ИМТ
    /// не растёт от набора жира, поэтому на массе это единственный честный показатель.
    /// Нормализация к росту 1.8 м — стандартная поправка Kouri.
    static func ffmi(weightKg: Double, heightCm: Double, bodyFatPercent: Double) -> Double? {
        guard weightKg > 0, heightCm > 0, bodyFatPercent > 0, bodyFatPercent < 100 else { return nil }
        let heightM = heightCm / 100
        let leanMass = weightKg * (1 - bodyFatPercent / 100)
        let raw = leanMass / (heightM * heightM)
        return raw + 6.1 * (1.8 - heightM)
    }

    static func ffmiVerdict(_ value: Double) -> (BodyInsight.Verdict, String) {
        switch value {
        case ..<18:    return (.watch, String(localized: "Ниже среднего"))
        case 18..<20:  return (.good, String(localized: "Средний уровень"))
        case 20..<22:  return (.good, String(localized: "Заметно тренированный"))
        case 22..<23.5: return (.excellent, String(localized: "Продвинутый уровень"))
        case 23.5..<25: return (.excellent, String(localized: "Близко к натуральному потолку"))
        default:       return (.excellent, String(localized: "Выше натурального потолка"))
        }
    }

    // MARK: - Сводный отчёт

    static func insights(measurement m: BodyMeasurement, profile: UserProfile?) -> [BodyInsight] {
        var out: [BodyInsight] = []

        let shoulders = m.shouldersCm
        let waist = m.waistCm
        let neck = m.neckCm
        let arm = m.best(.biceps)
        let forearm = m.best(.forearm)
        let calf = m.best(.calf)
        let wrist = m.best(.wrist)

        // V-taper — главный силуэтный показатель
        if shoulders > 0, waist > 0 {
            let ratio = shoulders / waist
            let verdict: BodyInsight.Verdict
            let label: String
            if ratio >= 1.618 {
                verdict = .excellent; label = String(localized: "Золотое сечение")
            } else if ratio >= 1.50 {
                verdict = .good; label = String(localized: "Выраженный V-силуэт")
            } else {
                verdict = .watch; label = String(localized: "Силуэт сглажен")
            }
            out.append(BodyInsight(
                id: "vtaper",
                title: String(localized: "V-силуэт (плечи / талия)"),
                value: String(format: "%.2f", ratio),
                verdict: verdict,
                verdictLabel: label,
                explanation: String(localized: "Эталон 1.618. Растёт и от плеч, и от сужения талии — на массе второе обычно даёт больше.")
            ))
        }

        // Классическая триада: рука = икра = шея
        if arm > 0, calf > 0, neck > 0 {
            let spread = max(arm, calf, neck) - min(arm, calf, neck)
            let verdict: BodyInsight.Verdict = spread <= 1.5 ? .excellent : (spread <= 3 ? .good : .watch)
            out.append(BodyInsight(
                id: "triad",
                title: String(localized: "Триада: бицепс / икра / шея"),
                value: String(format: "%.1f / %.1f / %.1f", arm, calf, neck),
                verdict: verdict,
                verdictLabel: spread <= 1.5
                    ? String(localized: "Сходится")
                    : String(format: String(localized: "Разброс %.1f см"), spread),
                explanation: String(localized: "В классическом бодибилдинге эти три обхвата держат равными. Отстающее звено обычно икра.")
            ))
        }

        // Предплечье к бицепсу
        if arm > 0, forearm > 0 {
            let percent = forearm / arm * 100
            let verdict: BodyInsight.Verdict = (79...82).contains(percent)
                ? .excellent : (percent >= 76 ? .good : .watch)
            out.append(BodyInsight(
                id: "forearm",
                title: String(localized: "Предплечье / бицепс"),
                value: String(format: "%.0f%%", percent),
                verdict: verdict,
                verdictLabel: verdict == .excellent
                    ? String(localized: "В диапазоне")
                    : String(localized: "Вне диапазона"),
                explanation: String(localized: "Ориентир 79–82%. Предплечье даёт руке плотность — без него бицепс выглядит приклеенным.")
            ))
        }

        // Талия к росту — сухость важнее веса
        if let height = profile?.heightCm, height > 0, waist > 0 {
            let ratio = waist / height
            let verdict: BodyInsight.Verdict = ratio < 0.45 ? .excellent : (ratio < 0.50 ? .good : .watch)
            out.append(BodyInsight(
                id: "waistHeight",
                title: String(localized: "Талия / рост"),
                value: String(format: "%.3f", ratio),
                verdict: verdict,
                verdictLabel: ratio < 0.45
                    ? String(localized: "Сухая форма")
                    : String(localized: "Есть запас"),
                explanation: String(localized: "Ниже 0.45 — атлетичный диапазон. Показатель надёжнее веса: не зависит от набранных мышц.")
            ))
        }

        // Процент жира. Стоит здесь, а не только в расчёте профиля: обхваты,
        // из которых он выведен, снимаются на этом же экране, и увидеть результат
        // логично рядом с ними.
        if let profile, profile.isNavyMethod {
            let bf = profile.bodyFatPercentage
            out.append(BodyInsight(
                id: "bodyFat",
                title: String(localized: "Жир % (по обхватам)"),
                value: String(format: "%.1f%%", bf),
                verdict: .good,
                // Категория приходит строкой из модели, а не литералом,
                // поэтому ключ локализации строим явно.
                verdictLabel: String(localized: String.LocalizationValue(profile.bodyFatCategory)),
                explanation: String(localized: "Метод ВМС США: считается по шее и поясу, точность ±2–3%. Он опирается на обхваты, а не на вес, поэтому не путает набранные мышцы с жиром — в отличие от расчёта по ИМТ.")
            ))
        }

        // FFMI
        if let profile,
           let bf = Optional(profile.bodyFatPercentage),
           let value = ffmi(weightKg: profile.weightKg, heightCm: profile.heightCm, bodyFatPercent: bf) {
            let (verdict, label) = ffmiVerdict(value)
            out.append(BodyInsight(
                id: "ffmi",
                title: String(localized: "FFMI (индекс сухой массы)"),
                value: String(format: "%.1f", value),
                verdict: verdict,
                verdictLabel: label,
                explanation: String(localized: "Сухая масса на рост². Не растёт от жира, поэтому на массе показывает реальный прогресс. Натуральный потолок около 25.")
            ))
        }

        // Обхват плеч — мягкая величина (дельты, широчайшие, грудь), костная ширина плеч
        // мерится циркулем, а не лентой. Ценность здесь в знаменателе: таз не меняется,
        // поэтому рост отношения означает именно набранный верх. Плечи/талия так не умеют —
        // они растут и просто от сушки. Канонической нормы для таза нет, порог мой.
        if shoulders > 0, m.pelvisCm > 0 {
            let ratio = shoulders / m.pelvisCm
            let verdict: BodyInsight.Verdict = ratio >= 1.55 ? .excellent : (ratio >= 1.40 ? .good : .watch)
            out.append(BodyInsight(
                id: "shouldersPelvis",
                title: String(localized: "Плечи / таз"),
                value: String(format: "%.2f", ratio),
                verdict: verdict,
                verdictLabel: ratio >= 1.55
                    ? String(localized: "Массивный верх")
                    : String(localized: "Ориентир от 1.55"),
                explanation: String(localized: "Знаменатель костный и не меняется, поэтому рост отношения — это именно набранные дельты и широчайшие. Плечи/талия растут и от одной сушки, здесь так не схитрить.")
            ))
        }

        // Сколько мягкого сидит над костяком. Падает по мере сушки и упирается в предел:
        // когда упёрлось, V растёт уже только через плечи, а не через диету.
        if waist > 0, m.pelvisCm > 0 {
            let ratio = waist / m.pelvisCm
            let verdict: BodyInsight.Verdict = ratio < 0.95 ? .excellent : (ratio <= 1.05 ? .good : .watch)
            out.append(BodyInsight(
                id: "waistPelvis",
                title: String(localized: "Талия / таз"),
                value: String(format: "%.2f", ratio),
                verdict: verdict,
                verdictLabel: {
                    if ratio < 0.95 { return String(localized: "Заметно уже костяка") }
                    if ratio < 1.0 { return String(localized: "Уже костяка") }
                    if ratio <= 1.05 { return String(localized: "Вровень с костяком") }
                    return String(localized: "Шире костяка")
                }(),
                explanation: String(localized: "Показывает, сколько мягких тканей над тазом. Когда талия близка к костяку, дальше резать нечего — силуэт растёт через дельты и широчайшие.")
            ))
        }

        // Разница пояса и талии — бытовой индикатор висцерального жира.
        if waist > 0, m.beltCm > 0 {
            let delta = m.beltCm - waist
            let verdict: BodyInsight.Verdict = delta <= 0 ? .excellent : (delta <= 5 ? .good : .watch)
            out.append(BodyInsight(
                id: "beltWaist",
                title: String(localized: "Пояс − талия"),
                value: String(format: "%+.1f см", delta),
                verdict: verdict,
                verdictLabel: delta <= 0
                    ? String(localized: "Живот плоский")
                    : (delta <= 5 ? String(localized: "В пределах нормы") : String(localized: "Заметный выступ")),
                explanation: String(localized: "Пупок сильно шире узкой талии — типичный признак висцерального жира. Индикатор, а не диагноз.")
            ))
        }

        // Ягодицы сами по себе ничего не говорят: обхват может быть большим и от широкого
        // таза. Разница с костяком показывает именно наросшие мышцы.
        if m.glutesCm > 0, m.pelvisCm > 0 {
            let delta = m.glutesCm - m.pelvisCm
            out.append(BodyInsight(
                id: "glutesPelvis",
                title: String(localized: "Ягодицы над костяком"),
                value: String(format: "%+.1f см", delta),
                verdict: .good,
                verdictLabel: String(localized: "Мышцы на тазе"),
                explanation: String(localized: "Обхват ягодиц сам по себе неинформативен — он растёт и от ширины таза. Разница с костяком отделяет мышцы от скелета.")
            ))
        }

        // Костяк
        if wrist > 0 {
            out.append(BodyInsight(
                id: "frame",
                title: String(localized: "Костяк (запястье)"),
                value: String(format: "%.1f см", wrist),
                verdict: .good,
                verdictLabel: wrist <= 17.5
                    ? String(localized: "Тонкий сустав")
                    : String(localized: "Средний костяк"),
                explanation: String(localized: "Тонкий сустав визуально усиливает пик мышцы за счёт контраста, но и потолок обхватов ставит ниже.")
            ))
        }

        return out
    }
}
