import Foundation

/// Распознавание еды на фотографии через Gemini.
///
/// Зачем облачная модель, а не модель на устройстве: локальная знает сотню
/// западных блюд и видит одно блюдо на снимке. За праздничным столом или в
/// ресторане это бесполезно — там на тарелке три вещи сразу, и ни одной из
/// них нет в списке из ста. Облачная разбирает тарелку и даёт прикидку веса.
///
/// Ключ живёт в настройках отладки, как и ключ USDA: лимит бесплатного тарифа
/// считается на ключ, а не на пользователя, поэтому общий ключ в релизе
/// сожгли бы за минуты. Появится бэкенд — переедет туда и станет доступно всем.
enum GeminiVisionService {
    enum ServiceError: LocalizedError {
        case missingAPIKey
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return String(localized: "Не задан ключ Gemini.")
            case .badResponse(let detail):
                return detail
            }
        }
    }

    static var apiKey: String? {
        let stored = UserDefaults.standard.string(forKey: "gemini_api_key")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty == false) ? stored : nil
    }

    static var isConfigured: Bool { apiKey != nil }

    /// Google выводит модели из обращения и в ответе на запрос к снятой прямо
    /// называет замену. Поэтому имя вынесено сюда: обновление — правка одной
    /// строки, а не поиск по файлу.
    private static let model = "gemini-3.6-flash"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Разбор фотографии заметно дольше обычного запроса — десять секунд мало.
        config.timeoutIntervalForRequest = 40
        return URLSession(configuration: config)
    }()

    /// Язык, на котором просим назвать блюда. Берём язык приложения, а не
    /// системы: в приложении язык можно переключить, и названия должны совпадать
    /// с тем, что человек видит вокруг. Иначе в русском дневнике заводятся
    /// «pan-seared tofu» — их потом ни найти поиском, ни узнать через месяц.
    private static var answerLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        // Название языка по-английски: так модель понимает его надёжнее всего.
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    /// Просим строгий JSON: свободный текст пришлось бы разбирать регулярками,
    /// а они ломаются от любой смены формулировки в ответе.
    private static var prompt: String {
        """
    You are helping someone log a meal in a calorie diary. Look at the photo and \
    list every distinct food or drink you can see.

    For each item estimate the portion actually shown on the plate, not a standard \
    serving. Give weight in grams and nutrition for that weight, not per 100 g.

    Be honest about uncertainty: if you cannot tell what something is, leave it out \
    rather than guessing a name. If the photo has no food at all, return an empty list.

    Write every name in \(answerLanguage), using the words someone would use for \
    that food in daily speech — these names go straight into the person's diary.

    Respond with JSON only, matching this shape:
    {"items":[{"name":"string","grams":number,"calories":number,\
    "protein":number,"fat":number,"carbs":number}]}
    """
    }

    private struct Response: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        struct APIError: Decodable { let message: String? }
        let candidates: [Candidate]?
        let error: APIError?
    }

    private struct Recognized: Decodable {
        struct Item: Decodable {
            let name: String
            let grams: Double?
            let calories: Double?
            let protein: Double?
            let fat: Double?
            let carbs: Double?
        }
        let items: [Item]
    }

    /// Что модель увидела на фото. Порядок сохраняем — обычно она перечисляет
    /// от крупного к мелкому, и это удобный порядок для черновика.
    static func recognize(imageData: Data) async throws -> [MealItem] {
        guard let apiKey else { throw ServiceError.missingAPIKey }

        var request = URLRequest(url: try endpoint(apiKey: apiKey))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Ключи AI Studio передаются параметром, а токены доступа — заголовком.
        // Поддерживаем оба: по одному взгляду не всегда понятно, что тебе выдали.
        if !apiKey.hasPrefix("AIza") {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg",
                                     "data": imageData.base64EncodedString()]],
                ]
            ]],
            "generationConfig": ["responseMimeType": "application/json"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        if let message = decoded.error?.message {
            throw ServiceError.badResponse(message)
        }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(String(localized: "Распознавание недоступно."))
        }
        guard let text = decoded.candidates?.first?.content?.parts?.compactMap(\.text).joined(),
              let payload = text.data(using: .utf8),
              let recognized = try? JSONDecoder().decode(Recognized.self, from: payload) else {
            throw ServiceError.badResponse(String(localized: "Не удалось разобрать ответ."))
        }

        return recognized.items.compactMap(mealItem(from:))
    }

    private static func endpoint(apiKey: String) throws -> URL {
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )
        if apiKey.hasPrefix("AIza") {
            components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }
        guard let url = components?.url else {
            throw ServiceError.badResponse(String(localized: "Распознавание недоступно."))
        }
        return url
    }

    private static func mealItem(from item: Recognized.Item) -> MealItem? {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Без названия и калорий строка бесполезна: править нечего и считать нечего.
        guard !name.isEmpty, let calories = item.calories, calories > 0 else { return nil }
        return MealItem(
            name: name,
            calories: Int(calories.rounded()),
            macros: Macros(protein: item.protein ?? 0,
                           fat: item.fat ?? 0,
                           carbs: item.carbs ?? 0),
            grams: item.grams
        )
    }
}
