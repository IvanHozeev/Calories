import Foundation

/// Выбирает, где искать продукт по названию.
///
/// Это не запасной вариант на случай поломки, а сама схема работы.
///
/// **Open Food Facts — источник для всех.** Ключа не требует, работает у любого
/// сразу после установки, знает брендовые товары со всего мира.
///
/// **USDA — только там, где прописан ключ**, то есть у разработчика. Он даёт
/// витамины и минералы, которых у OFF почти нет, но требует ключ с лимитом
/// на ключ, а не на пользователя: один общий ключ в релизе выжгли бы за минуты.
/// Требовать же от каждого регистрации в USDA ради поиска творога — не вариант.
///
/// Когда появится свой бэкенд, ключ переедет туда, и USDA станет доступен всем.
enum FoodSearch {
    /// Знает ли приложение про микронутриенты в найденном.
    static var providesMicronutrients: Bool { FoodDataCentralService.isConfigured }

    static func search(query: String) async throws -> [FoodItem] {
        if FoodDataCentralService.isConfigured {
            return try await FoodDataCentralService.search(query: query)
        }
        return try await OpenFoodService.search(query: query)
    }
}
