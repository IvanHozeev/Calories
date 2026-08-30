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
    case system, rounded, serif, monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:     return String(localized: "Системный")
        case .rounded:    return String(localized: "Скруглённый")
        case .serif:      return String(localized: "С засечками")
        case .monospaced: return String(localized: "Моноширинный")
        }
    }



    var design: Font.Design {
        switch self {
        case .system:     return .default
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        }
    }
}
