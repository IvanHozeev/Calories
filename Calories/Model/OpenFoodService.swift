import Foundation

/// Open Food Facts. Оставлен только на штрихкодах: там он вне конкуренции —
/// брендовая упаковка со всего мира, включая то, что лежит в местном магазине.
/// Текстовый поиск ушёл в USDA, потому что оттуда приходят ещё и микронутриенты,
/// которых здесь почти никогда нет.
enum OpenFoodService {
    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            String(localized: "Источник временно недоступен.")
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        // Open Food Facts просит представляться: без User-Agent он режет запросы.
        config.httpAdditionalHeaders = ["User-Agent": "Calories iOS (github.com/IvanHozeev/Calories)"]
        return URLSession(configuration: config)
    }()

    private struct SearchResponse: Decodable {
        let products: [Product]

        struct Product: Decodable {
            let productName: String?
            let nutriments: Nutriments?

            struct Nutriments: Decodable {
                let energyKcal100g: Double?
                let proteins100g: Double?
                let fat100g: Double?
                let carbohydrates100g: Double?

                enum CodingKeys: String, CodingKey {
                    case energyKcal100g = "energy-kcal_100g"
                    case proteins100g = "proteins_100g"
                    case fat100g = "fat_100g"
                    case carbohydrates100g = "carbohydrates_100g"
                }
            }

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case nutriments
            }
        }
    }

    /// Текстовый поиск. Основным источником стал USDA — он знает микронутриенты, —
    /// но ему нужен ключ, которого на устройстве может не быть. Тогда ищем здесь:
    /// без витаминов, зато работает у всех и без настройки.
    static func search(query: String) async throws -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=25")
        else { return [] }

        let (data, response) = try await session.data(from: url)
        // База периодически отвечает 503 и отдаёт HTML вместо JSON. Молчаливый
        // пустой список в этом случае врёт: искать не «нечего», а негде.
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ServiceError.unavailable
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.products.compactMap { product in
            let name = (product.productName ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let kcal = product.nutriments?.energyKcal100g, kcal > 0 else { return nil }
            return FoodItem(
                name: name,
                caloriesPer100g: Int(kcal.rounded()),
                protein: product.nutriments?.proteins100g ?? 0,
                fat: product.nutriments?.fat100g ?? 0,
                carbs: product.nutriments?.carbohydrates100g ?? 0
            )
        }
    }

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
