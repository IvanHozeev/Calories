import Foundation

/// Что это за рецепт: салат, суп, горячее, десерт, напиток.
///
/// Не категория продукта — у того она про полку в магазине («Мясо и птица»,
/// «Крупы и хлеб»), а здесь про место за столом. Борщ и салат из тех же
/// овощей лежат на одной полке и готовятся по-разному; собирая обед, человек
/// думает «что на первое», а не «из чего оно».
///
/// Пять видов и «другое». Больше дробить не стоит: закуска, гарнир и соус
/// нужны поварской книге, а не тому, кто вечером ищет, что сварить.
enum DishKind: String, Codable, CaseIterable, Identifiable {
    case salad, soup, main, dessert, drink, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salad:   return String(localized: "Салат")
        case .soup:    return String(localized: "Суп")
        // «Горячее», а не «второе»: второе бывает только там, где есть
        // первое, а горячее понятно и само по себе.
        case .main:    return String(localized: "Горячее")
        case .dessert: return String(localized: "Десерт")
        case .drink:   return String(localized: "Напиток")
        case .other:   return String(localized: "Другое")
        }
    }

    /// Значок вида. Символы системы те же, что у категорий продуктов, —
    /// рядом в списках они не должны выглядеть из разных наборов.
    var icon: String {
        switch self {
        case .salad:   return "leaf"
        case .soup:    return "takeoutbag.and.cup.and.straw"
        case .main:    return "fork.knife"
        case .dessert: return "birthday.cake"
        case .drink:   return "cup.and.saucer"
        case .other:   return "square.grid.2x2"
        }
    }
}
