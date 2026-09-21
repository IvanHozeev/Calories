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
