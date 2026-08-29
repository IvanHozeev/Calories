import Foundation
import SwiftData

/// Один сеанс замеров: все обхваты, снятые за один раз. Хранится записью с датой,
/// как взвешивания — смысл замеров для бодибилдинга именно в динамике за месяцы,
/// разовый снимок мало что говорит.
///
/// Ноль означает «не мерил»: пропущенный обхват не должен притворяться нулевым
/// сантиметром в аналитике и в графиках.
@Model
final class BodyMeasurement: Identifiable {
    var id: UUID
    var date: Date

    // Непарные
    var neckCm: Double
    var chestCm: Double
    var shouldersCm: Double
    var waistCm: Double
    var beltCm: Double
    var glutesCm: Double

    // Парные: левая и правая стороны меряются отдельно ради контроля симметрии
    var bicepsLeftCm: Double
    var bicepsRightCm: Double
    var forearmLeftCm: Double
    var forearmRightCm: Double
    var wristLeftCm: Double
    var wristRightCm: Double
    var thighLeftCm: Double
    var thighRightCm: Double
    var quadLeftCm: Double
    var quadRightCm: Double
    var calfLeftCm: Double
    var calfRightCm: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        neckCm: Double = 0, chestCm: Double = 0, shouldersCm: Double = 0,
        waistCm: Double = 0, beltCm: Double = 0, glutesCm: Double = 0,
        bicepsLeftCm: Double = 0, bicepsRightCm: Double = 0,
        forearmLeftCm: Double = 0, forearmRightCm: Double = 0,
        wristLeftCm: Double = 0, wristRightCm: Double = 0,
        thighLeftCm: Double = 0, thighRightCm: Double = 0,
        quadLeftCm: Double = 0, quadRightCm: Double = 0,
        calfLeftCm: Double = 0, calfRightCm: Double = 0
    ) {
        self.id = id
        self.date = date
        self.neckCm = neckCm; self.chestCm = chestCm; self.shouldersCm = shouldersCm
        self.waistCm = waistCm; self.beltCm = beltCm; self.glutesCm = glutesCm
        self.bicepsLeftCm = bicepsLeftCm; self.bicepsRightCm = bicepsRightCm
        self.forearmLeftCm = forearmLeftCm; self.forearmRightCm = forearmRightCm
        self.wristLeftCm = wristLeftCm; self.wristRightCm = wristRightCm
        self.thighLeftCm = thighLeftCm; self.thighRightCm = thighRightCm
        self.quadLeftCm = quadLeftCm; self.quadRightCm = quadRightCm
        self.calfLeftCm = calfLeftCm; self.calfRightCm = calfRightCm
    }

    /// Значение обхвата для места замера. Для парных — заданная сторона.
    func value(_ site: MeasurementSite, _ side: BodySide = .right) -> Double {
        switch site {
        case .neck:      return neckCm
        case .chest:     return chestCm
        case .shoulders: return shouldersCm
        case .waist:     return waistCm
        case .belt:      return beltCm
        case .glutes:    return glutesCm
        case .biceps:    return side == .left ? bicepsLeftCm : bicepsRightCm
        case .forearm:   return side == .left ? forearmLeftCm : forearmRightCm
        case .wrist:     return side == .left ? wristLeftCm : wristRightCm
        case .thigh:     return side == .left ? thighLeftCm : thighRightCm
        case .quad:      return side == .left ? quadLeftCm : quadRightCm
        case .calf:      return side == .left ? calfLeftCm : calfRightCm
        }
    }

    func setValue(_ value: Double, for site: MeasurementSite, side: BodySide = .right) {
        switch site {
        case .neck:      neckCm = value
        case .chest:     chestCm = value
        case .shoulders: shouldersCm = value
        case .waist:     waistCm = value
        case .belt:      beltCm = value
        case .glutes:    glutesCm = value
        case .biceps:    if side == .left { bicepsLeftCm = value } else { bicepsRightCm = value }
        case .forearm:   if side == .left { forearmLeftCm = value } else { forearmRightCm = value }
        case .wrist:     if side == .left { wristLeftCm = value } else { wristRightCm = value }
        case .thigh:     if side == .left { thighLeftCm = value } else { thighRightCm = value }
        case .quad:      if side == .left { quadLeftCm = value } else { quadRightCm = value }
        case .calf:      if side == .left { calfLeftCm = value } else { calfRightCm = value }
        }
    }

    /// Больший из двух — рабочая сторона. Для непарных просто значение.
    func best(_ site: MeasurementSite) -> Double {
        site.isPaired ? max(value(site, .left), value(site, .right)) : value(site)
    }

    /// Есть ли хоть один заполненный обхват.
    var hasAnyValue: Bool {
        MeasurementSite.allCases.contains { site in
            site.isPaired
                ? value(site, .left) > 0 || value(site, .right) > 0
                : value(site) > 0
        }
    }
}

enum BodySide: String, CaseIterable {
    case left, right

    var title: String {
        switch self {
        case .left:  return String(localized: "Левый")
        case .right: return String(localized: "Правый")
        }
    }
}

/// Место замера: название, порядок в форме и инструкция, как мерить.
/// Инструкция не украшение — обхват, снятый в другом месте или в другом состоянии мышцы,
/// делает всю динамику бессмысленной.
enum MeasurementSite: String, CaseIterable, Identifiable {
    case neck, shoulders, chest, waist, belt, glutes
    case biceps, forearm, wrist
    case thigh, quad, calf

    var id: String { rawValue }

    var isPaired: Bool {
        switch self {
        case .biceps, .forearm, .wrist, .thigh, .quad, .calf: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .neck:      return String(localized: "Шея")
        case .shoulders: return String(localized: "Плечи")
        case .chest:     return String(localized: "Грудь")
        case .waist:     return String(localized: "Талия")
        case .belt:      return String(localized: "Пояс")
        case .glutes:    return String(localized: "Ягодицы")
        case .biceps:    return String(localized: "Бицепс")
        case .forearm:   return String(localized: "Предплечье")
        case .wrist:     return String(localized: "Запястье")
        case .thigh:     return String(localized: "Бедро")
        case .quad:      return String(localized: "Квадрицепс")
        case .calf:      return String(localized: "Икра")
        }
    }

    var howTo: String {
        switch self {
        case .neck:
            return String(localized: "Под кадыком, лента горизонтально. Шею не напрягать, голову держать прямо.")
        case .shoulders:
            return String(localized: "По самой широкой точке дельт, руки свободно вдоль тела, на спокойном вдохе.")
        case .chest:
            return String(localized: "По соскам, лента горизонтально сзади. На спокойном выдохе, грудь не раздувать.")
        case .waist:
            return String(localized: "В самом узком месте, обычно на ладонь выше пупка. Живот не втягивать.")
        case .belt:
            return String(localized: "Строго на уровне пупка. Это не то же, что талия: пояс показывает висцеральный жир.")
        case .glutes:
            return String(localized: "По самой выступающей точке ягодиц, стопы вместе, мышцы расслаблены.")
        case .biceps:
            return String(localized: "Рука согнута, напряжена, но без предварительного пампа. По пику бицепса.")
        case .forearm:
            return String(localized: "В самом широком месте ниже локтя, кулак сжат, рука вытянута.")
        case .wrist:
            return String(localized: "Ниже косточки сустава, в самом тонком месте. Задаёт костяк и идеалы МакКаллума.")
        case .thigh:
            return String(localized: "Верхняя треть, под ягодичной складкой. Вес на обеих ногах поровну.")
        case .quad:
            return String(localized: "Середина бедра, на равном расстоянии от паха и колена. Мышца расслаблена.")
        case .calf:
            return String(localized: "По самой широкой точке икры, стоя, вес на обеих ногах.")
        }
    }
}
