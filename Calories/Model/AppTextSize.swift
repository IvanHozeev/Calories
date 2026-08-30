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

/// Применяет выбранный размер, а на «обычном» пропускает системный без изменений.
///
/// Ветвиться здесь нельзя. Раньше на «обычном» возвращался просто `content`, а
/// иначе `content.dynamicTypeSize(...)` — для SwiftUI это две структурно разные
/// ветки, и при пересечении границы всё дерево пересоздавалось вместе со стеком
/// навигации: экран выбрасывало назад прямо во время перетаскивания ползунка.
/// Поэтому модификатор применяется всегда, а «не вмешиваться» выражается тем,
/// что наверх уходит тот же размер, который пришёл из системы.
struct AppTextSizeModifier: ViewModifier {
    let size: AppTextSize
    @Environment(\.dynamicTypeSize) private var systemSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(size.override ?? systemSize)
    }
}
