import SwiftUI

// Цвета для типов модели — здесь, а не в самих типах.
//
// Дневник и план не должны знать про SwiftUI: `MacroKind` тянул цвет из
// `ProgressRing`, то есть модель зависела от вьюхи, и импорт SwiftUI ехал
// в файл с записями дневника. Цвет — способ показать, а не свойство макроса.

extension MacroKind {
    /// Цвета дуг кольца «Сегодня» — они же у тегов, полос и цифр БЖУ по всему
    /// приложению. Системные синий, оранжевый и фиолетовый рядом с кольцом
    /// читались как другие цвета.
    var color: Color {
        switch self {
        case .protein: return ProgressRing.proteinColors[0]
        case .fat: return ProgressRing.fatColors[0]
        case .carbs: return ProgressRing.carbColors[0]
        }
    }

    /// Цвет текста этого макроса на белом: тот же тон, что у дуги, но
    /// насыщеннее и чуть темнее — без примеси чёрного, которая гасит пастель
    /// в грязь. Контраст на белом не ниже 3 : 1 — для полужирного названия.
    var ink: Color {
        switch self {
        case .protein: return Color(hex: 0x0E9FCB)
        case .fat: return Color(hex: 0xEC5F37)
        case .carbs: return Color(hex: 0x8F5CF0)
        }
    }
}

extension Achievement {
    var tint: Color {
        switch kind {
        case .firstWeek:        return .orange
        case .disciplineMaster: return .yellow
        case .proteinMaster:    return .blue
        case .ironWill:         return .purple
        }
    }
}
