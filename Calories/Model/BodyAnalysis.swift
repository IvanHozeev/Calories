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
