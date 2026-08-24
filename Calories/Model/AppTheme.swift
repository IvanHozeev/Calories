import SwiftUI

/// Выбор оформления. Системный режим — не то же самое, что светлая тема:
/// он следует за настройкой iOS, включая автоматическое переключение по расписанию.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "Как в системе")
        case .light:  return String(localized: "Светлая")
        case .dark:   return String(localized: "Тёмная")
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// nil означает «не навязывать», то есть следовать системе.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
