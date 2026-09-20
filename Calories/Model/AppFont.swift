import SwiftUI

/// Начертание шрифта приложения.
///
/// Все варианты — системные начертания, а не подключённые файлы шрифтов. Это
/// сознательный выбор: приложение переведено на семь языков, включая арабский
/// и иврит, а почти любой красивый сторонний шрифт не содержит ни арабской вязи,
/// ни кириллицы. Подключи такой — и часть пользователей увидит вместо текста
/// подстановку из системного запасного шрифта, то есть ту же кашу, только хуже.
/// Системные начертания покрывают все письменности и цифры одинаково.
enum AppFont: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced, nunito

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:     return String(localized: "Системный")
        case .rounded:    return String(localized: "Скруглённый")
        case .serif:      return String(localized: "С засечками")
        case .monospaced: return String(localized: "Моноширинный")
        case .nunito:     return "Nunito"
        }
    }



    /// Системное начертание, которым красится всё дерево. У Nunito его нет:
    /// это свой файл шрифта, и `.fontDesign` ему только мешает — он подменяет
    /// любой подключённый шрифт системным того же дизайна.
    var design: Font.Design? {
        switch self {
        case .system:     return .default
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        case .nunito:     return nil
        }
    }

    /// Выбранное начертание. Читается там, где нет окружения SwiftUI.
    static var current: AppFont {
        UserDefaults.standard.string(forKey: "app_font").flatMap(AppFont.init(rawValue:)) ?? .system
    }

    /// Имя начертания подключённого шрифта под нужный вес.
    /// Файл переменный, одним куском на все веса; именованные экземпляры
    /// подхватываются по имени.
    static func customName(for weight: Font.Weight) -> String? {
        guard current == .nunito else { return nil }
        switch weight {
        case .ultraLight, .thin: return "Nunito-ExtraLight"
        case .light:             return "Nunito-Light"
        case .medium:            return "Nunito-Medium"
        case .semibold:          return "Nunito-SemiBold"
        case .bold:              return "Nunito-Bold"
        case .heavy:             return "Nunito-ExtraBold"
        case .black:             return "Nunito-Black"
        default:                 return "Nunito-Regular"
        }
    }
}

extension Font {
    /// Шрифт приложения под стиль текста.
    ///
    /// Через него идут все явные шрифты в интерфейсе. Системные начертания
    /// (скруглённое, с засечками, моноширинное) задаются одним `.fontDesign`
    /// на корне, а подключённый файл так задать нельзя: тот же `.fontDesign`
    /// подменяет его системным. Поэтому выбор шрифта решается здесь, в одном
    /// месте, а не двумя разными способами в разных концах приложения.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        guard let name = AppFont.customName(for: weight ?? .regular) else {
            let base = Font.system(style)
            return weight.map { base.weight($0) } ?? base
        }
        return .custom(name, size: Self.baseSize(style), relativeTo: style)
    }

    /// Шрифт фиксированного размера — для крупных чисел, которые верстаются
    /// под свой круг и не масштабируются вместе с системным размером текста.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let name = AppFont.customName(for: weight) else {
            return .system(size: size, weight: weight)
        }
        return .custom(name, fixedSize: size)
    }

    /// Размер стиля по умолчанию: от него шрифт масштабируется вместе
    /// с системным размером текста.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:  return 34
        case .title:       return 28
        case .title2:      return 22
        case .title3:      return 20
        case .headline:    return 17
        case .subheadline: return 15
        case .callout:     return 16
        case .footnote:    return 13
        case .caption:     return 12
        case .caption2:    return 11
        default:           return 17
        }
    }
}
