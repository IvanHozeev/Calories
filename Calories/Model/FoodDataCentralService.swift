import Foundation

/// Поиск продуктов в USDA FoodData Central.
///
/// Второй источник рядом с Open Food Facts, и роли у них разные. OFF остаётся
/// только на штрихкодах: там он силён — брендовая упаковка со всего мира.
/// Текстовый поиск уходит сюда, потому что USDA даёт то, чего у OFF почти нет:
/// витамины и минералы.
///
/// Две вещи, о которых нужно знать снаружи.
///
/// Ключ. API требует ключ, выдаваемый на аккаунт, с лимитом порядка тысячи
/// запросов в час. Он читается из Info.plist по ключу FDC_API_KEY, а не зашит
/// в код: в исходниках ему не место, а в бинарнике он всё равно достаётся
/// любым желающим — без своего бэкенда это неизбежный размен.
///
/// Язык. База американская, названия в ней английские. Русский запрос почти
/// наверняка не найдёт ничего — это не поломка, а свойство источника.
enum FoodDataCentralService {
    enum ServiceError: LocalizedError {
        case missingAPIKey
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return String(localized: "Не задан ключ USDA FoodData Central.")
            case .badResponse:
                return String(localized: "База продуктов ответила неожиданно.")
            }
        }
    }

    private struct SearchResponse: Decodable {
        let foods: [Food]

        struct Food: Decodable {
            let description: String
            let foodNutrients: [Nutrient]?

            struct Nutrient: Decodable {
                let nutrientId: Int?
                let value: Double?
            }
        }
    }

    /// Идентификаторы энергии и макросов в USDA.
    private enum CoreNutrient {
        static let energyKcal = 1008
        static let protein = 1003
        static let fat = 1004
        static let carbs = 1005
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    static var apiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "FDC_API_KEY") as? String
        let trimmed = key?.trimmingCharacters(in: .whitespaces)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    static var isConfigured: Bool { apiKey != nil }

    static func search(query: String) async throws -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        guard let apiKey else { throw ServiceError.missingAPIKey }

        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "pageSize", value: "25"),
            // Foundation и SR Legacy — те наборы, где микронутриенты заполнены.
            // У брендовых чаще только то, что на этикетке, поэтому они последними.
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
        ]
        guard let url = components?.url else { throw ServiceError.badResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.foods.compactMap(item(from:))
    }

    private static func item(from food: SearchResponse.Food) -> FoodItem? {
        let name = food.description.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        var byID: [Int: Double] = [:]
        for nutrient in food.foodNutrients ?? [] {
            guard let id = nutrient.nutrientId, let value = nutrient.value else { continue }
            byID[id] = value
        }

        // Без калорийности продукт бесполезен: дневник считает именно её.
        guard let calories = byID[CoreNutrient.energyKcal] else { return nil }

        var micros: [Micronutrient: Double] = [:]
        for nutrient in Micronutrient.allCases {
            if let value = byID[nutrient.usdaNutrientID] { micros[nutrient] = value }
        }

        let item = FoodItem(
            name: name,
            caloriesPer100g: Int(calories.rounded()),
            protein: byID[CoreNutrient.protein] ?? 0,
            fat: byID[CoreNutrient.fat] ?? 0,
            carbs: byID[CoreNutrient.carbs] ?? 0
        )
        item.micronutrients = Micronutrients(micros)
        return item
    }
}
