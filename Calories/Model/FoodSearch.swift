import Foundation

/// Выбирает, где искать продукт по названию.
///
/// USDA — основной источник: только оттуда приходят витамины и минералы. Но ему
/// нужен ключ, и на устройстве, где ключ не прописан, поиск раньше молча
/// возвращал пустоту — то есть выглядел сломанным. Пустой результат хуже
/// худшего источника, поэтому без ключа спрашиваем Open Food Facts.
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
