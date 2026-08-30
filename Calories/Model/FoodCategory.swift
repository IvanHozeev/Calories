import Foundation

/// Категория продукта. Нужна для навигации по своему списку: когда продуктов
/// становится несколько десятков, искать глазами дольше, чем печатать.
///
/// Хранится строкой, а не индексом: порядок в перечислении со временем меняется,
/// а по индексу «Рыба» однажды тихо превратилась бы в «Молочное» у всех подряд.
enum FoodCategory: String, CaseIterable, Identifiable {
    case meat, fish, dairy, grains, produce, fats, sweets, drinks, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meat:    return String(localized: "Мясо и птица")
        case .fish:    return String(localized: "Рыба и морепродукты")
        case .dairy:   return String(localized: "Молочное и яйца")
        case .grains:  return String(localized: "Крупы и хлеб")
        case .produce: return String(localized: "Овощи и фрукты")
        case .fats:    return String(localized: "Орехи и масла")
        case .sweets:  return String(localized: "Сладкое и снеки")
        case .drinks:  return String(localized: "Напитки")
        case .other:   return String(localized: "Другое")
        }
    }

    var icon: String {
        switch self {
        case .meat:    return "fork.knife"
        case .fish:    return "fish"
        case .dairy:   return "carton"
        case .grains:  return "birthday.cake"
        case .produce: return "carrot"
        case .fats:    return "drop"
        case .sweets:  return "candybarphone"
        case .drinks:  return "cup.and.saucer"
        case .other:   return "square.grid.2x2"
        }
    }
}
