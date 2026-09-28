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
    /// Какая доля веса имеет известный состав. Есть только у блюд: их состав
    /// считается по рецепту из продуктов каталога, и часть ингредиентов может
    /// быть без данных. У продукта состав либо есть целиком, либо его нет.
    let microCoverage: Double?
    /// Названия того же продукта на других языках — для поиска, не для показа.
    ///
    /// Дневник ведут на языке упаковки: у израильского товара с каталогом не
    /// совпадает ни одно слово, и «אבקת חלבון» не находило ничего. Синонимы
    /// живут в `Tools/food_aliases.txt` и в каталог попадают сборкой.
    let aliases: [String]?

    /// Ключи короткие: на двух тысячах позиций разница в размере файла
    /// заметная, а читают его не глазами.
    private enum CodingKeys: String, CodingKey {
        case id = "i", ru, en, kcal = "k", protein = "p", fat = "f", carbs = "c"
        case category = "cat", grams = "g", micro = "m", microCoverage = "mc"
        case aliases = "a"
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

    /// Состав по отображаемому названию — собирается один раз.
    ///
    /// У `FoodItem` то же свойство разбирает JSON при каждом обращении, а
    /// каталог держит его уже разобранным. Через этот словарь строки списков
    /// получают состав, не платя разбором за каждую перерисовку.
    static let nutrientProfilesByName: [String: NutrientProfile] = Dictionary(
        index.compactMap { entry -> (String, NutrientProfile)? in
            let micronutrients = entry.food.micronutrients
            guard !micronutrients.isEmpty else { return nil }
            return (entry.food.localizedName,
                    NutrientProfile(per100g: micronutrients,
                                    coverage: entry.food.microCoverage ?? 1))
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
            let names = Set(([food.ru, food.en, food.localizedName] + (food.aliases ?? []).map(Optional.some))
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

    /// Слова, которые про еду ничего не говорят.
    ///
    /// Брендовое название состоит из них почти целиком, и поиск по такому слову
    /// приводит куда угодно: «Pro 40 Protein Drink» находился по «drink».
    private static let noiseWords: Set<String> = [
        "pro", "go", "free", "sugar", "drink", "extra", "soft", "bar", "new",
        "light", "lite", "zero", "max", "plus", "original", "classic", "mix",
        "taste", "flavor", "flavour", "style", "premium", "гр", "мой", "моя",
        "мое", "мои", "дома", "свой", "своя",
    ]

    /// Кто из каталога может одолжить витамины продукту с такими цифрами.
    ///
    /// Два правила, и оба выучены на ошибках.
    ///
    /// Слова берём все, а не самое длинное: длинное слово — это чаще всего
    /// бренд («Gold Standard», «Pastavita»), а еда названа коротким. Из всех
    /// слов выбираем то, что дало лучшее совпадение, и при равенстве
    /// предпочитаем длинное — оно говорит больше.
    ///
    /// И совпадения по названию мало. «Овсяное молоко без сахара» на 52 ккал
    /// получало состав «Печенья овсяного» на 590, «Фасоль в томате» — сухой
    /// фасоли втрое калорийнее. Поэтому донор обязан быть похож по
    /// калорийности и по раскладке макросов: витамины берутся у того же
    /// вещества, а не у однокоренного слова.
    static func donors(forName name: String, caloriesPer100g: Int,
                       macrosPer100g: Macros, category: FoodCategory = .other,
                       limit: Int = 3) -> [CatalogFood] {
        let normalized = normalize(name)
        // Обогащённому продукту донора по классу быть не может: премикс — это
        // решение завода, а не свойство еды.
        guard !isFortified(normalized) else { return [] }
        let words = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 && !noiseWords.contains($0) && Int($0) == nil }
        guard !words.isEmpty else { return [] }

        var scored: [(rank: Int, length: Int, shortest: Int, food: CatalogFood)] = []
        for entry in index where !entry.food.micronutrients.isEmpty {
            var best: (rank: Int, length: Int)?
            for word in words {
                guard let rank = rank(entry: entry, needle: word) else { continue }
                let candidate = (rank: rank, length: -word.count)
                if best == nil || candidate < best! { best = candidate }
            }
            guard let best, fits(calories: caloriesPer100g, macros: macrosPer100g,
                                 category: category, donor: entry.food)
            else { continue }
            scored.append((best.rank, best.length, entry.names.map(\.count).min() ?? 0, entry.food))
        }
        scored.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.length != $1.length { return $0.length < $1.length }
            if $0.shortest != $1.shortest { return $0.shortest < $1.shortest }
            return $0.food.id < $1.food.id
        }
        return scored.prefix(limit).map(\.food)
    }

    /// Та же ли это еда по цифрам.
    ///
    /// Калорийность — грубое сито: у похожих продуктов она расходится на
    /// проценты, у случайно совпавших — в разы. Раскладка макросов ловит
    /// остальное: сравниваем доли калорий, а не граммы, потому что жир даёт
    /// вдвое больше энергии и на граммах выглядел бы наравне с углеводами.
    ///
    /// Своей калорийности может и не быть — тогда сита нет: у продукта,
    /// заведённого без чисел, и витамины взять не с чем.
    static func fits(calories: Int, macros: Macros, category: FoodCategory = .other,
                     donor: CatalogFood,
                     caloriesTolerance: Double = 0.25,
                     macroTolerance: Double = 0.5) -> Bool {
        // Всю работу делает категория, а не узость допусков. На выгрузке USDA
        // (4016 продуктов с полным составом) пары, похожие только по калориям и
        // макросам, расходились по железу и кальцию в 2.0–2.3 раза; стоит
        // потребовать ту же категорию — 1.4–1.7. Дальнейшее сужение допусков до
        // 15% и 0.25 улучшает это на пять сотых, но выбрасывает половину
        // подходящих пар: на моих продуктах предложений осталось пять из
        // тринадцати. Поэтому категория обязательна, а допуски широкие.
        //
        // Неизвестную категорию («прочее») ни с чем не сверяем: она ничего
        // не утверждает.
        if category != .other, donor.foodCategory != category { return false }
        if calories > 0,
           abs(Double(donor.kcal - calories)) / Double(calories) > caloriesTolerance {
            return false
        }
        guard let own = macroShares(macros), let theirs = macroShares(donor.macrosPer100g)
        else { return true }
        let distance = abs(own.protein - theirs.protein)
            + abs(own.fat - theirs.fat)
            + abs(own.carbs - theirs.carbs)
        return distance <= macroTolerance
    }

    /// Доли калорий по макросам. Пусто, когда макросов нет вовсе.
    private static func macroShares(_ macros: Macros) -> Macros? {
        let total = macros.protein * MacroTargets.kcalPerProteinGram
            + macros.fat * MacroTargets.kcalPerFatGram
            + macros.carbs * MacroTargets.kcalPerCarbGram
        guard total > 0 else { return nil }
        return Macros(protein: macros.protein * MacroTargets.kcalPerProteinGram / total,
                      fat: macros.fat * MacroTargets.kcalPerFatGram / total,
                      carbs: macros.carbs * MacroTargets.kcalPerCarbGram / total)
    }

    /// Обогащённый продукт: витамины в нём из премикса.
    ///
    /// Слова с упаковки на трёх языках, которыми это объявляют. У таких
    /// продуктов витамина A по данным USDA в восемь раз больше обычного, а
    /// витамина D в одиннадцать, — то есть класс про них не знает ничего.
    static func isFortified(_ normalizedName: String) -> Bool {
        ["enriched", "fortified", "обогащ", "витаминизир", "מועשר"]
            .contains { normalizedName.contains($0) }
    }

    /// Продукты каталога, у которых есть витамины, — для выбора донора руками.
    ///
    /// Без проверки по цифрам: человек знает про свою еду больше, чем мы, и
    /// если он выбрал этот продукт, спорить не о чем. Калорийность донора
    /// показываем рядом, чтобы выбор был зрячим.
    static func vitaminSources(matching query: String, limit: Int = 6) -> [CatalogFood] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }
        return search(needle, limit: limit * 4).filter { !$0.micronutrients.isEmpty }.prefix(limit).map { $0 }
    }

    private static func rank(entry: Entry, needle: String) -> Int? {
        if entry.names.contains(needle) { return 0 }
        if entry.names.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if entry.tokens.contains(where: { $0.hasPrefix(needle) }) { return 2 }
        if entry.names.contains(where: { $0.contains(needle) }) { return 3 }
        return nil
    }
}
