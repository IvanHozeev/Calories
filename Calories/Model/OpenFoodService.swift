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

    /// Что из состава Open Food Facts умеет отдавать и в каком поле.
    ///
    /// Значения в полях `*_100g` нормализованы в граммы — натрий 0.0428
    /// означает 42.8 мг, — а мы храним минералы в миллиграммах, а витамины A,
    /// D, B12, фолаты и селен в микрограммах. Отсюда множители.
    private static let offNutrients: [(key: String, nutrient: Micronutrient)] = [
        ("fiber_100g", .fiber),
        ("vitamin-a_100g", .vitaminA), ("vitamin-c_100g", .vitaminC),
        ("vitamin-d_100g", .vitaminD), ("vitamin-e_100g", .vitaminE),
        ("vitamin-b6_100g", .vitaminB6), ("vitamin-b12_100g", .vitaminB12),
        ("vitamin-b9_100g", .folate), ("folates_100g", .folate),
        ("calcium_100g", .calcium), ("iron_100g", .iron),
        ("magnesium_100g", .magnesium), ("zinc_100g", .zinc),
        ("potassium_100g", .potassium), ("sodium_100g", .sodium),
        ("selenium_100g", .selenium),
    ]

    /// Состав с этикетки: всё, что производитель указал.
    ///
    /// Раньше отсюда забиралась одна клетчатка, хотя в ответе часто лежат
    /// натрий, кальций, железо, витамины C и D — их на упаковке указывают по
    /// закону. Это данные с этикетки, то есть измерение, а не оценка.
    ///
    /// Нули не берём. В Open Food Facts ноль чаще значит «импортёр заполнил
    /// поле», а не «в продукте этого нет»: у соуса из помидоров витамин A
    /// стоит нулём, хотя каротин там есть. Пустое место честнее нуля — на нуле
    /// день насчитал бы дефицит там, где данных нет.
    static func micronutrients(from nutriments: [String: Any]) -> Micronutrients {
        var result = Micronutrients()
        for (key, nutrient) in offNutrients {
            guard result[nutrient] == nil,
                  let grams = nutriments[key] as? Double, grams > 0 else { continue }
            let amount = nutrient == .fiber ? grams : grams * nutrient.gramsMultiplier
            // Заведомая чушь бывает: у части товаров состав вписан в граммах
            // на порцию или перепутана единица, и тогда «кальций 40 000 мг»
            // приезжает как правда.
            guard amount <= nutrient.plausibleMaximumPer100g else { continue }
            result = result.setting(nutrient, to: amount)
        }
        // Соль на упаковке пишут чаще натрия: это одно и то же вещество,
        // пересчитанное по массе хлорида натрия.
        if result[.sodium] == nil, let salt = nutriments["salt_100g"] as? Double, salt > 0 {
            result = result.setting(.sodium, to: salt / 2.5 * 1000)
        }
        return result
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
        return try parseSearch(data)
    }

    /// Разбор ответа поиска — отдельно от запроса, чтобы его можно было
    /// проверить тестом: у сетевого метода проверяема только подпись.
    ///
    /// Разбираем словарём, а не типом: набор веществ у товаров разный, и
    /// перечислять полтора десятка необязательных полей в `Codable` значит
    /// писать одно и то же трижды — здесь, в штрихкоде и в ключах.
    static func parseSearch(_ data: Data) throws -> [FoodItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]]
        else { throw ServiceError.unavailable }
        return products.compactMap { product -> FoodItem? in
            let name = (product["product_name"] as? String ?? "")
                .trimmingCharacters(in: .whitespaces)
            let nutriments = product["nutriments"] as? [String: Any] ?? [:]
            let kcal = nutriments["energy-kcal_100g"] as? Double ?? 0
            guard !name.isEmpty, kcal > 0 else { return nil }
            let item = FoodItem(
                name: name,
                caloriesPer100g: Int(kcal.rounded()),
                protein: nutriments["proteins_100g"] as? Double ?? 0,
                fat: nutriments["fat_100g"] as? Double ?? 0,
                carbs: nutriments["carbohydrates_100g"] as? Double ?? 0
            )
            let micronutrients = micronutrients(from: nutriments)
            if !micronutrients.isEmpty { item.micronutrients = micronutrients }
            return item
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
            return parseProduct(data, barcode: barcode)
        } catch {
            return nil
        }
    }

    /// Разбор ответа по штрихкоду.
    ///
    /// Состав забирается так же, как в поиске, — всё, что указал производитель.
    static func parseProduct(_ data: Data, barcode: String) -> BarcodeProduct? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
            carbs: nutriments["carbohydrates_100g"] as? Double ?? 0,
            micronutrients: micronutrients(from: nutriments)
        )
    }
}

/// Продукт, найденный по штрихкоду.
///
/// Живёт рядом с источником, а не во вьюхе сканера: его же разбирает и
/// проверяет тест, а вьюха только показывает.
struct BarcodeProduct {
    let name: String
    let caloriesPer100g: Int
    let protein: Double
    let fat: Double
    let carbs: Double
    var micronutrients: Micronutrients = Micronutrients()
}
