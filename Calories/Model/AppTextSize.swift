import SwiftUI

/// Размер текста в приложении.
///
/// «Обычный» намеренно не задаёт ничего: тогда работает системная настройка
/// размера. Если бы этот вариант жёстко ставил `.large`, человеку, который
/// выкрутил крупный шрифт по зрению, приложение молча сделало бы мельче —
/// то есть сломало бы ровно то, ради чего он эту настройку менял.
enum AppTextSize: Int, CaseIterable, Identifiable {
    case small = 0, normal, large, extraLarge

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .small:      return String(localized: "Мелкий")
        case .normal:     return String(localized: "Обычный")
        case .large:      return String(localized: "Крупный")
        case .extraLarge: return String(localized: "Очень крупный")
        }
    }

    /// nil — не вмешиваться, оставить системный размер.
    var override: DynamicTypeSize? {
        switch self {
        case .small:      return .small
        case .normal:     return nil
        case .large:      return .xLarge
        case .extraLarge: return .xxxLarge
        }
    }
}

/// Применяет выбранный размер, а на «обычном» не делает ничего.
struct AppTextSizeModifier: ViewModifier {
    let size: AppTextSize

    func body(content: Content) -> some View {
        if let override = size.override {
            content.dynamicTypeSize(override)
        } else {
            content
        }
    }
}
