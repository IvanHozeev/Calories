import Foundation

enum OpenFoodService {
    private struct Response: Decodable {
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

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    static func search(query: String) async throws -> [FoodItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=25") else {
            return []
        }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.products.compactMap { product in
            guard let name = product.productName?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty,
                  let kcal = product.nutriments?.energyKcal100g,
                  kcal > 0, kcal < 10_000 else { return nil }
            return FoodItem(
                name: name,
                caloriesPer100g: Int(kcal.rounded()),
                protein: max(0, product.nutriments?.proteins100g ?? 0),
                fat: max(0, product.nutriments?.fat100g ?? 0),
                carbs: max(0, product.nutriments?.carbohydrates100g ?? 0)
            )
        }
    }
}
