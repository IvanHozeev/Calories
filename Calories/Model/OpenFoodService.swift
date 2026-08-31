import Foundation

/// Open Food Facts. Оставлен только на штрихкодах: там он вне конкуренции —
/// брендовая упаковка со всего мира, включая то, что лежит в местном магазине.
/// Текстовый поиск ушёл в USDA, потому что оттуда приходят ещё и микронутриенты,
/// которых здесь почти никогда нет.
enum OpenFoodService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// Продукт по штрихкоду. nil означает «не нашли» — для сканера это обычный
    /// исход, а не ошибка: половины местных товаров в базе просто нет.
    static func product(barcode: String) async -> BarcodeProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,nutriments") else {
            return nil
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["status"] as? Int) == 1,
                  let productDict = json["product"] as? [String: Any] else { return nil }

            let name = (productDict["product_name"] as? String ?? "")
                .trimmingCharacters(in: .whitespaces)
            let nutriments = productDict["nutriments"] as? [String: Any] ?? [:]
            let kcal = nutriments["energy-kcal_100g"] as? Double
                    ?? nutriments["energy-kcal"] as? Double
                    ?? 0
            // Без калорийности продукт бесполезен: дневник считает именно её.
            guard kcal > 0 else { return nil }

            return BarcodeProduct(
                name: name.isEmpty ? String(format: String(localized: "Продукт %@"), barcode) : name,
                caloriesPer100g: Int(kcal.rounded()),
                protein: nutriments["proteins_100g"] as? Double ?? 0,
                fat: nutriments["fat_100g"] as? Double ?? 0,
                carbs: nutriments["carbohydrates_100g"] as? Double ?? 0
            )
        } catch {
            return nil
        }
    }
}
