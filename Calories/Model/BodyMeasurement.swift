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
    var pelvisCm: Double
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
        waistCm: Double = 0, beltCm: Double = 0, pelvisCm: Double = 0, glutesCm: Double = 0,
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
        self.waistCm = waistCm; self.beltCm = beltCm; self.pelvisCm = pelvisCm
        self.glutesCm = glutesCm
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
        case .pelvis:    return pelvisCm
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
        case .pelvis:    pelvisCm = value
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

/// Грамматический род места замера. Нужен только там, где подпись стороны
/// согласуется с существительным: «левое предплечье», но «левая икра».
/// Род указан по русскому языку — он же язык разработки. В английском и немецком
/// подписи сторон не изменяются вовсе, а в испанском, португальском, французском,
/// арабском и иврите они переведены неизменяемой формой-существительным
/// («слева»/«справа»), потому что род существительного там свой и с русским
/// не совпадает: предплечье среднего рода, а antebrazo — мужского.
enum GrammaticalGender {
    case masculine, feminine, neuter, plural
}

enum BodySide: String, CaseIterable {
    case left, right

    func title(_ gender: GrammaticalGender) -> String {
        switch (self, gender) {
        case (.left, .masculine):  return String(localized: "Левый")
        case (.left, .feminine):   return String(localized: "Левая")
        case (.left, .neuter):     return String(localized: "Левое")
        case (.left, .plural):     return String(localized: "Левые")
        case (.right, .masculine): return String(localized: "Правый")
        case (.right, .feminine):  return String(localized: "Правая")
        case (.right, .neuter):    return String(localized: "Правое")
        case (.right, .plural):    return String(localized: "Правые")
        }
    }
}

/// Место замера: название, порядок в форме и инструкция, как мерить.
/// Инструкция не украшение — обхват, снятый в другом месте или в другом состоянии мышцы,
/// делает всю динамику бессмысленной.
enum MeasurementSite: String, CaseIterable, Identifiable {
    case neck, shoulders, chest, waist, belt, pelvis, glutes
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
        case .pelvis:    return String(localized: "Таз")
        case .glutes:    return String(localized: "Ягодицы")
        case .biceps:    return String(localized: "Бицепс")
        case .forearm:   return String(localized: "Предплечье")
        case .wrist:     return String(localized: "Запястье")
        case .thigh:     return String(localized: "Бедро")
        case .quad:      return String(localized: "Квадрицепс")
        case .calf:      return String(localized: "Икра")
        }
    }

    /// Границы правдоподобия для обхвата. Нужны не для придирок к пользователю,
    /// а чтобы промах по клавише не попал в историю: один замер с лишней цифрой
    /// ломает и график, и все производные отношения в отчёте.
    /// Диапазоны нарочно широкие — от подростка до тяжёлого атлета.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .neck:      return 25...70
        case .shoulders: return 80...180
        case .chest:     return 60...180
        case .waist:     return 45...200
        case .belt:      return 45...200
        case .pelvis:    return 55...180
        case .glutes:    return 60...200
        case .biceps:    return 15...70
        case .forearm:   return 15...60
        case .wrist:     return 12...25
        case .thigh:     return 30...100
        case .quad:      return 25...90
        case .calf:      return 20...70
        }
    }

    /// Род названия — для согласования подписи стороны. Парные места указаны
    /// точно; у непарных род тоже проставлен, чтобы согласование не сломалось,
    /// если какое-то из них когда-нибудь станет парным.
    var gender: GrammaticalGender {
        switch self {
        case .neck:      return .feminine    // шея
        case .shoulders: return .plural      // плечи
        case .chest:     return .feminine    // грудь
        case .waist:     return .feminine    // талия
        case .belt:      return .masculine   // пояс
        case .pelvis:    return .masculine   // таз
        case .glutes:    return .plural      // ягодицы
        case .biceps:    return .masculine   // бицепс
        case .forearm:   return .neuter      // предплечье
        case .wrist:     return .neuter      // запястье
        case .thigh:     return .neuter      // бедро
        case .quad:      return .masculine   // квадрицепс
        case .calf:      return .feminine    // икра
        }
    }

    /// Значения для колеса, в десятых долях сантиметра. Шаг 0.5 см — мельче лента
    /// всё равно не даёт, а колесо с шагом 0.1 пришлось бы крутить впятеро дольше.
    /// Колесо предлагает только правдоподобное, поэтому мусор не ввести в принципе.
    var pickerTenths: [Int] {
        let lower = Int((plausibleRange.lowerBound * 10).rounded())
        let upper = Int((plausibleRange.upperBound * 10).rounded())
        return Array(stride(from: lower, through: upper, by: 5))
    }

    /// Пустое поле — это «не мерил», а не ошибка. Ноль тоже: так замер очищают.
    func isPlausible(_ value: Double) -> Bool {
        value == 0 || plausibleRange.contains(value)
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
            return String(localized: "В самом узком месте, обычно на ладонь выше пупка. Живот не втягивать, дышать спокойно.")
        case .belt:
            return String(localized: "Строго на уровне пупка, лента горизонтально. Не путать с талией: разница между поясом и талией отражает висцеральный жир.")
        case .pelvis:
            return String(localized: "По костяшкам подвздошных гребней на пояснице — там, где прощупывается верх таза. Это костяк, он почти не меняется от формы.")
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
