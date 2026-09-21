import SwiftUI

extension FoodCategory {
    /// Цвет категории на диаграмме состава.
    ///
    /// Подобраны так, чтобы читались по смыслу и не спорили между собой:
    /// мясное тёплое, рыба и молочное холодные, растительное зелёное,
    /// сладкое розовое. Соседние в круге категории обязаны различаться на
    /// взгляд — в этом весь смысл диаграммы.
    var color: Color {
        switch self {
        case .meat:      return Color(hex: 0xE2553D)
        case .fish:      return Color(hex: 0x3FA9D6)
        case .dairy:     return Color(hex: 0x6C8CFF)
        case .legumes:   return Color(hex: 0xC8A14A)
        case .grains:    return Color(hex: 0xE0A93B)
        case .produce:   return Color(hex: 0x4FBF6B)
        case .mushrooms: return Color(hex: 0x9A7B5F)
        case .fats:      return Color(hex: 0xC97F3A)
        case .sweets:    return Color(hex: 0xE070A8)
        case .drinks:    return Color(hex: 0x56C8C0)
        case .dishes:    return Color(hex: 0xA678E8)
        case .other:     return Color(hex: 0x8E8E93)
        }
    }
}
