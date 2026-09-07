import Foundation

/// Продукт из встроенного каталога.
///
/// Отдельный тип, а не `FoodItem`, по двум причинам. `FoodItem` — модель
/// SwiftData, и держать в памяти две тысячи её объектов ради того, чтобы
/// человек выбрал один, незачем. И названия здесь лежат сразу на двух языках:
/// каталог собирается скриптом из данных USDA, а не пишется в коде, поэтому
/// прогонять его через строковый каталог Xcode нечем и не нужно.
nonisolated struct CatalogFood: Codable, Identifiable, Hashable, Sendable {
    /// Идентификатор продукта в USDA FoodData Central — стабильный ключ,
    /// по которому пересборка каталога не перемешает продукты между собой.
    let id: Int
    /// Русское название. Необязательное: каталог собирается из USDA, где названия
    /// английские, и русское появляется только там, где переведено уверенно.
    /// Полупереведённое «Beef, фарш, raw» хуже честного английского.
    let ru: String?
    let en: String
    let kcal: Int
    let protein: Double
    let fat: Double
    let carbs: Double
    let category: String
    /// Порция по умолчанию, если у продукта она осмысленная: яйцо весит 50 г,
    /// и предлагать «100 г яйца» — значит заставлять считать в уме.
    let grams: Double?
    /// Микронутриенты на 100 г. Необязательны: у части продуктов их в источнике
    /// просто нет, и нули там означали бы «померили и получили ноль».
    let micro: [String: Double]?

    /// Ключи короткие: на двух тысячах позиций разница в размере файла
    /// заметная, а читают его не глазами.
    private enum CodingKeys: String, CodingKey {
        case id = "i", ru, en, kcal = "k", protein = "p", fat = "f", carbs = "c"
        case category = "cat", grams = "g", micro = "m"
    }

    var foodCategory: FoodCategory { FoodCategory(rawValue: category) ?? .other }

    /// Название на языке интерфейса.
    ///
    /// Каталог знает русский и английский. Для остальных шести языков честнее
    /// показать английское название, чем машинный перевод, по которому продукт
    /// потом не найдёшь поиском.
    ///
    /// Но у части продуктов перевод уже есть: они жили литералами в коде, и их
    /// названия переведены на все семь языков в `Localizable.xcstrings`. Ключ
    /// там — русский текст, поэтому его и спрашиваем: терять готовый перевод
    /// только потому, что данные переехали из кода в файл, глупо.
    var localizedName: String {
        guard let ru, !ru.isEmpty else { return en }
        if FoodCatalog.prefersRussian { return ru }
        let translated = Bundle.main.localizedString(forKey: ru, value: "", table: nil)
        return translated.isEmpty || translated == ru ? en : translated
    }

    var macrosPer100g: Macros {
        Macros(protein: protein, fat: fat, carbs: carbs)
    }

    var micronutrients: Micronutrients {
        guard let micro else { return Micronutrients() }
        var values: [Micronutrient: Double] = [:]
        for (key, value) in micro {
            guard let nutrient = Micronutrient(rawValue: key) else { continue }
            values[nutrient] = value
        }
        return Micronutrients(values)
    }
}

/// Встроенный каталог продуктов: одинаковый у всех, работает без сети и без ключа.
///
/// Это ответ на перекос в источниках еды. Open Food Facts знает брендовые товары,
/// но требует сети и плохо отвечает на «гречка»; USDA знает состав, но требует
/// ключ, который нельзя раздать всем. Каталог закрывает то, что человек вводит
/// каждый день, и делает это мгновенно и офлайн.
nonisolated enum FoodCatalog {
    /// Ищем сразу по русскому и английскому названию независимо от языка
    /// интерфейса: человек с русским интерфейсом набирает «chicken» так же
    /// часто, как «курица», и не находить продукт из-за этого — глупо.
    private struct Entry: Sendable {
        let food: CatalogFood
        let names: [String]
        let tokens: [String]
    }

    static var prefersRussian: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    }

    static var all: [CatalogFood] { index.map(\.food) }

    static var isEmpty: Bool { index.isEmpty }

    /// Микронутриенты по отображаемому названию — собираются один раз.
    ///
    /// У `FoodItem` то же свойство разбирает JSON при каждом обращении, а
    /// каталог держит их уже разобранными. Через этот словарь строки списков
    /// получают состав, не платя разбором за каждую перерисовку.
    static let micronutrientsByName: [String: Micronutrients] = Dictionary(
        index.compactMap { entry in
            let micronutrients = entry.food.micronutrients
            return micronutrients.isEmpty ? nil : (entry.food.localizedName, micronutrients)
        },
        uniquingKeysWith: { first, _ in first }
    )

    private static let index: [Entry] = load()

    private static func load() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "FoodCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let foods = try? JSONDecoder().decode([CatalogFood].self, from: data)
        else {
            // Пустой каталог — это отсутствующий раздел «База», а не падение:
            // приложение остаётся рабочим. Пропажу файла из бандла ловит тест
            // `catalogIsInTheBundle`, и ловит внятно — падением одного теста,
            // а не обвалом всего прогона на старте.
            return []
        }
        // Порядок — алфавитный по тому названию, которое человек видит.
        // Каталог приходит отсортированным по идентификаторам, а это для
        // списка на экране случайный порядок: пролистать его глазами нельзя.
        return foods
            .sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
            .map { food in
            // В индекс идут оба названия и то, что человек видит на экране:
            // француз ищет по французскому названию, а русский с тем же успехом
            // набирает и «курица», и «chicken».
            let names = Set([food.ru, food.en, food.localizedName]
                .compactMap { $0 }
                .map(normalize)
                .filter { !$0.isEmpty })
                .sorted()
            return Entry(food: food,
                         names: names,
                         tokens: names.flatMap { $0.split(separator: " ").map(String.init) })
        }
    }

    /// Приводит строку к виду, в котором сравнение не зависит от регистра,
    /// диакритики и «ё». Без этого «Ёгурт», «йогурт» и «Yogurt» — три разных
    /// продукта для поиска, хотя для человека это один.
    static func normalize(_ string: String) -> String {
        let folded = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var result = ""
        result.reserveCapacity(folded.count)
        var lastWasSpace = true
        for character in folded {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Поиск по каталогу.
    ///
    /// Ранг важнее полноты: по запросу «мол» человек ждёт «Молоко», а не
    /// «Сгущённое молоко с сахаром», хотя формально подходят оба. Поэтому
    /// точное совпадение идёт раньше начала названия, начало — раньше начала
    /// слова, и только потом вхождение в середину.
    static func search(_ query: String, limit: Int = 60) -> [CatalogFood] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return Array(all.prefix(limit)) }

        var ranked: [(rank: Int, length: Int, food: CatalogFood)] = []
        for entry in index {
            guard let rank = rank(entry: entry, needle: needle) else { continue }
            ranked.append((rank, entry.names.map(\.count).min() ?? 0, entry.food))
        }
        ranked.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.food.id < $1.food.id
        }
        return ranked.prefix(limit).map(\.food)
    }

    /// Что из каталога похоже на продукт с таким названием.
    ///
    /// Ищем по самому длинному слову, а не по строке целиком: своё название
    /// почти всегда шире каталожного — «Творог мой», «Spinach mine», — и поиск
    /// по всей строке не находит ничего. Длинное слово выбрано потому, что оно
    /// и есть сам продукт, а короткое — уточнение вроде «мой» или «дома».
    static func candidates(forName name: String, limit: Int = 3) -> [CatalogFood] {
        let words = normalize(name)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
        guard let key = words.max(by: { $0.count < $1.count }) else { return [] }
        return search(key, limit: limit).filter { !$0.micronutrients.isEmpty }
    }

    private static func rank(entry: Entry, needle: String) -> Int? {
        if entry.names.contains(needle) { return 0 }
        if entry.names.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if entry.tokens.contains(where: { $0.hasPrefix(needle) }) { return 2 }
        if entry.names.contains(where: { $0.contains(needle) }) { return 3 }
        return nil
    }
}
