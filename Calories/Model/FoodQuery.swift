import Foundation

/// Разбор строки поиска на продукт и количество.
///
/// Человек ищет еду так, как говорит: «творог 5% 180», «два яйца», «молоко
/// 0,5 л». Обычный поиск по названию видит во всём этом одну длинную строку и
/// находит пустоту — продукт называется «Творог 5%», а не «Творог 5% 180».
///
/// Здесь количество отделяется от названия, а процент остаётся в нём: «творог
/// 5%» и «творог 9%» — разные продукты, и путать их нельзя. Разбор
/// намеренно не знает про базу продуктов: он не решает, что такое «яйцо», он
/// только говорит «две штуки». Вес штуки знает сам продукт.
nonisolated enum FoodQuery {

    /// Продукт и количество из одной фразы.
    struct Item: Equatable, Hashable, Sendable {
        /// Название без количества, но с процентом: «творог 5%».
        var name: String
        /// Явный вес: «180», «180 г», «0,5 кг», «200 мл».
        var grams: Double?
        /// Сколько штук или порций: «2 яйца», «полбанана». Вес штуки знает
        /// продукт, поэтому здесь хранится количество, а не граммы.
        var units: Double?
        /// Жирность, если она названа. В названии она остаётся, а здесь лежит
        /// отдельно — для проверок и для будущей подстановки.
        var percent: Double?

        var hasQuantity: Bool { grams != nil || units != nil }

        /// Вес порции: явный, а если названо количество — по весу одной штуки.
        ///
        /// `defaultGrams` — вес одной штуки у продукта. У яйца это 55 г, у
        /// хлеба 30 г; у продукта без своей порции — сотня граммов.
        func grams(defaultGrams: Double) -> Double? {
            if let grams, grams > 0 { return grams }
            if let units, units > 0 {
                let one = defaultGrams > 0 ? defaultGrams : 100
                return units * one
            }
            return nil
        }
    }

    /// Разбирает фразу на продукты. «Творог 200, банан» — две позиции: запятую
    /// человек ставит между ними так же, как в списке покупок.
    ///
    /// Пустые названия не возвращаются: «180» — это количество без продукта, и
    /// подставлять его не к чему.
    static func parse(_ query: String) -> [Item] {
        split(query).flatMap(parseSingle)
    }

    /// Насколько название подходит под запрос: меньше — лучше.
    ///
    /// 0 — совпало целиком, 1 — начинается с запроса, 2 — совпали все слова,
    /// 3 — не хватило одного слова из трёх и больше. `nil` — не совпадение.
    ///
    /// Цифры в запросе — жёсткое условие: «творог 9%» не должен находить
    /// «творог 5%». Слова сравниваются с учётом окончаний и одной опечатки:
    /// «яйца» находит «яйцо», «банап» — «банан».
    static func rank(query: String, name: String, producer: String? = nil) -> Int? {
        rank(query: query, names: [name], producer: producer)
    }

    /// То же, но по всем названиям продукта: русскому, английскому, переводу
    /// интерфейса и синонимам. Каталог ищет сразу на двух языках, и выбор
    /// лучшего совпадения обязан делать так же.
    static func rank(query: String, names: [String], producer: String? = nil) -> Int? {
        let needle = FoodCatalog.normalize(query)
        guard !needle.isEmpty else { return nil }
        let producer = producer.map(FoodCatalog.normalize)
        var best: Int?
        for name in names {
            guard let rank = rank(needle: needle,
                                  name: FoodCatalog.normalize(name),
                                  producer: producer)
            else { continue }
            best = min(best ?? rank, rank)
            if best == 0 { break }
        }
        return best
    }

    /// Проверяет, что в одном из названий продукта указан заданный процент
    /// жирности: «молоко 3%» не должно находить «молоко 1.5%».
    static func nameContainsPercent(_ names: [String], percent: Double) -> Bool {
        for name in names {
            guard let match = firstMatch(percentRegex, in: name),
                  let value = number(match.groups[0]),
                  abs(value - percent) < 0.001
            else { continue }
            return true
        }
        return false
    }

    // MARK: - Разбор

    private static let volumePattern = #"(\d+(?:[.,]\d+)?)\s*(мл|ml|миллилитр(?:а|ов)?|millilit(?:er|re)s?|литр(?:а|ов)?|lit(?:er|re)s?|л|l)(?![\p{L}\p{N}])"#
    private static let weightPattern = #"(\d+(?:[.,]\d+)?)\s*(килограмм(?:а|ов)?|кг|kg|грамм(?:а|ов)?|гр|grams?|г|g)(?![\p{L}\p{N}])"#
    private static let countPattern = #"(\d+(?:[.,]\d+)?)\s*(шт\.?|штук(?:а|и)?|штуки|pieces?|pcs?|порци(?:я|и|ю|й)|servings?)(?![\p{L}\p{N}])"#
    private static let percentPattern = #"(?<![\p{L}\p{N}])(\d+(?:[.,]\d+)?)\s*%"#
    private static let mixedFractionPattern = #"(?<![\p{L}\p{N}])(\d+)\s+(\d+)\s*/\s*(\d+)(?![\p{L}\p{N}])"#
    private static let fractionPattern = #"(?<![\p{L}\p{N}])(\d+)\s*/\s*(\d+)(?![\p{L}\p{N}])"#
    private static let glyphFractionPattern = #"[½¼¾⅓⅔⅛]"#
    /// Два знака и больше: «80» — это граммы, а «5» чаще жирность, чем вес.
    private static let largeNumberPattern = #"(?<![\p{L}\p{N}])(\d{2,}(?:[.,]\d+)?)(?!\s*%)(?![\p{L}\p{N}])"#
    private static let leadingNumberPattern = #"^\s*(\d+(?:[.,]\d+)?)\s+"#
    private static let trailingNumberPattern = #"(?:^|\s)(\d+(?:[.,]\d+)?)\s*$"#

    /// Скомпилированные регулярки — один раз, а не на каждое нажатие клавиши.
    private static let volumeRegex = try! NSRegularExpression(pattern: volumePattern, options: [.caseInsensitive])
    private static let weightRegex = try! NSRegularExpression(pattern: weightPattern, options: [.caseInsensitive])
    private static let countRegex = try! NSRegularExpression(pattern: countPattern, options: [.caseInsensitive])
    private static let percentRegex = try! NSRegularExpression(pattern: percentPattern, options: [.caseInsensitive])
    private static let mixedFractionRegex = try! NSRegularExpression(pattern: mixedFractionPattern, options: [.caseInsensitive])
    private static let fractionRegex = try! NSRegularExpression(pattern: fractionPattern, options: [.caseInsensitive])
    private static let glyphFractionRegex = try! NSRegularExpression(pattern: glyphFractionPattern, options: [.caseInsensitive])
    private static let largeNumberRegex = try! NSRegularExpression(pattern: largeNumberPattern, options: [.caseInsensitive])
    private static let leadingNumberRegex = try! NSRegularExpression(pattern: leadingNumberPattern, options: [.caseInsensitive])
    private static let trailingNumberRegex = try! NSRegularExpression(pattern: trailingNumberPattern, options: [.caseInsensitive])
    private static let splitRegex = try! NSRegularExpression(pattern: #"\s*,(?!\d)\s*|\s*[;+&]\s*|\s+и\s+"#, options: [.caseInsensitive])
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#, options: [])
    private static let spaceBeforeCommaRegex = try! NSRegularExpression(pattern: #"\s+([,.])"#, options: [])

    private static func parseSingle(_ raw: String) -> [Item] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var percent: Double?
        if let match = firstMatch(percentRegex, in: text), let value = number(match.groups[0]) {
            percent = value
        }

        var grams: Double?
        var units: Double?
        var extractedRange: Range<String.Index>?

        if let match = firstMatch(volumeRegex, in: text),
           let value = number(match.groups[0]) {
            grams = value * scale(for: match.groups[1])
            extractedRange = match.range
        } else if let large = largeNumber(in: text) {
            grams = large.value
            extractedRange = large.range
        } else if let match = firstMatch(weightRegex, in: text),
                  let value = number(match.groups[0]) {
            grams = value * scale(for: match.groups[1])
            extractedRange = match.range
        } else if let match = firstMatch(countRegex, in: text),
                  let value = number(match.groups[0]) {
            units = value
            extractedRange = match.range
        } else if let fraction = fractionQuantity(in: text) {
            units = fraction.value
            extractedRange = fraction.range
        } else if let word = wordQuantity(in: text) {
            units = word.value
            text = word.remaining
        } else if let bare = bareNumber(in: text) {
            if bare.value > 20 {
                grams = bare.value
            } else {
                units = bare.value
            }
            extractedRange = bare.range
        }

        var result: [Item] = []

        if let range = extractedRange {
            // Текст до количества — название первой позиции,
            // текст после — потенциальная вторая позиция.
            let beforeName = cleanedName(String(text[text.startIndex..<range.lowerBound]))
            let afterText = String(text[range.upperBound..<text.endIndex])

            if !beforeName.isEmpty {
                result.append(Item(name: beforeName, grams: grams, units: units, percent: percent))
                result.append(contentsOf: parseSingle(afterText))
            } else if grams != nil || units != nil {
                // Количество без названия до него — приклеиваем к первой позиции после.
                var afterItems = parseSingle(afterText)
                if let first = afterItems.first {
                    afterItems[0] = Item(name: first.name, grams: grams, units: units, percent: percent)
                }
                result.append(contentsOf: afterItems)
            } else {
                result.append(contentsOf: parseSingle(afterText))
            }
        } else if text != raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            // wordQuantity уже изменил text, остаток — название.
            let name = cleanedName(text)
            if !name.isEmpty {
                result.append(Item(name: name, grams: nil, units: units, percent: percent))
            }
        } else {
            let name = cleanedName(text)
            if !name.isEmpty {
                result.append(Item(name: name, grams: grams, units: units, percent: percent))
            }
        }

        // Убираем мусор: единицы измерения без названия («г», «кг», «мл»).
        result = result.filter { !$0.name.isEmpty && !isUnitOnly($0.name) }

        return result
    }

    /// Запятая разделяет позиции, но десятичная запятая — нет: «банан 1,5» это
    /// один продукт. Куски без букв приклеиваются к предыдущему: в «творог 5%,
    /// 180 г» запятая стоит внутри одной фразы, а не между продуктами.
    private static func split(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let whole = trimmed as NSString
        var parts: [String] = []
        var cursor = 0
        for match in splitRegex.matches(in: trimmed,
                                        range: NSRange(location: 0, length: whole.length)) {
            let start = whole.substring(with: NSRange(location: cursor,
                                                      length: match.range.location - cursor))
            parts.append(start)
            cursor = match.range.location + match.range.length
        }
        parts.append(whole.substring(from: cursor))

        var merged: [String] = []
        for part in parts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where !part.isEmpty {
            if !merged.isEmpty, isQuantityOnly(part) {
                merged[merged.count - 1] += " " + part
            } else {
                merged.append(part)
            }
        }
        return merged
    }

    /// Кусок без продукта: «180 г», «2 кг». Он относится к предыдущему
    /// названию, а не к новой позиции списка.
    private static let quantityOnlyRegex = try! NSRegularExpression(
        pattern: #"^\d+(?:[.,]\d+)?\s*(?:г|кг|гр|грамм|килограмм|литр|литра|литров|мл|шт|штук|штуки|порци|%|g|kg|ml|l|lb|oz)\s*$"#,
        options: [.caseInsensitive]
    )

    private static func isQuantityOnly(_ part: String) -> Bool {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return quantityOnlyRegex.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        ) != nil
    }

    /// Единица измерения без названия — не продукт: «г», «кг», «мл».
    private static func isUnitOnly(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["г", "кг", "гр", "грамм", "килограмм", "литр", "литра", "литров",
                "мл", "шт", "штук", "штуки", "порция", "порции",
                "g", "kg", "ml", "l", "lb", "oz"].contains(trimmed)
    }

    private static func fractionQuantity(
        in text: String
    ) -> (value: Double, range: Range<String.Index>)? {
        if let match = firstMatch(mixedFractionRegex, in: text),
           let whole = number(match.groups[0]),
           let numerator = number(match.groups[1]),
           let denominator = number(match.groups[2]),
           denominator > 0 {
            return (whole + numerator / denominator, match.range)
        }
        if let match = firstMatch(fractionRegex, in: text),
           let numerator = number(match.groups[0]),
           let denominator = number(match.groups[1]),
           denominator > 0 {
            return (numerator / denominator, match.range)
        }
        if let match = firstMatch(glyphFractionRegex, in: text),
           let value = glyphFractions[text[match.range.lowerBound]] {
            return (value, match.range)
        }
        return nil
    }

    private static func largeNumber(
        in text: String
    ) -> (value: Double, range: Range<String.Index>)? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in largeNumberRegex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let captured = match.range(at: 1)
            guard let captureRange = Range(captured, in: text),
                  let value = number(String(text[captureRange])),
                  value > 20
            else { continue }
            return (value, matchRange)
        }
        return nil
    }

    private static func bareNumber(
        in text: String
    ) -> (value: Double, range: Range<String.Index>)? {
        if let match = firstMatch(leadingNumberRegex, in: text),
           let value = number(match.groups[0]) {
            return (value, match.range)
        }
        if let match = firstMatch(trailingNumberRegex, in: text),
           let value = number(match.groups[0]) {
            return (value, match.range)
        }
        return nil
    }

    /// Количество словом: «два яйца», «half a banana», «полбанана».
    private static let wordQuantities: [String: Double] = [
        "один": 1, "одна": 1, "одно": 1,
        "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
        "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10,
        "полтора": 1.5, "полторы": 1.5,
        "пол": 0.5, "половина": 0.5, "половинка": 0.5,
        "четверть": 0.25, "треть": 1.0 / 3.0,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "half": 0.5, "quarter": 0.25,
        "אחד": 1, "אחת": 1, "שניים": 2, "שתיים": 2, "שתי": 2,
        "שלוש": 3, "שלושה": 3, "ארבע": 4, "חצי": 0.5,
        "واحد": 1, "اثنان": 2, "اثنين": 2, "ثلاثة": 3, "نصف": 0.5,
    ]

    private static func wordQuantity(
        in text: String
    ) -> (value: Double, remaining: String)? {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }

        func lower(_ token: String) -> String {
            token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()"))
                .lowercased()
        }

        if let value = wordQuantities[lower(tokens[0])] {
            tokens.removeFirst()
            // «half a banana» — артикль не часть названия.
            if let article = tokens.first?.lowercased(), ["a", "an"].contains(article) {
                tokens.removeFirst()
            }
            return (value, tokens.joined(separator: " "))
        }

        // «полбанана» пишут одним словом.
        let first = lower(tokens[0])
        if first.count > 3, first.hasPrefix("пол") {
            let rest = String(first.dropFirst(3))
            if rest.count >= 3, rest.allSatisfy({ $0.isLetter }) {
                tokens[0] = rest
                return (0.5, tokens.joined(separator: " "))
            }
        }

        if tokens.count > 1, let value = wordQuantities[lower(tokens[tokens.count - 1])] {
            tokens.removeLast()
            return (value, tokens.joined(separator: " "))
        }
        return nil
    }

    private static let glyphFractions: [Character: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75,
        "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0, "⅛": 0.125,
    ]

    private static func scale(for unit: String) -> Double {
        switch unit.lowercased() {
        case "кг", "kg", "килограмм", "килограмма", "килограммов",
             "литр", "литра", "литров", "liter", "liters", "litre", "litres",
             "л", "l":
            return 1000
        default:
            return 1
        }
    }

    private static func number(_ string: String) -> Double? {
        string.replacingOccurrences(of: ",", with: ".").decimalValue
    }

    private static func cleanedName(_ text: String) -> String {
        var result = text.replacingOccurrences(of: " +", with: " ",
                                               options: .regularExpression)
        result = result.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ",;+-"))
        )
        result = result.replacingOccurrences(of: " %", with: "%")
        result = result.replacingOccurrences(of: #"\s+([,.])"#, with: "$1",
                                             options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(
        _ regex: NSRegularExpression,
        in text: String
    ) -> (range: Range<String.Index>, groups: [String])? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text)
        else { return nil }
        var groups: [String] = []
        if match.numberOfRanges > 1 {
            for index in 1..<match.numberOfRanges {
                if let groupRange = Range(match.range(at: index), in: text) {
                    groups.append(String(text[groupRange]))
                } else {
                    groups.append("")
                }
            }
        }
        return (matchRange, groups)
    }

    // MARK: - Совпадение

    private static func rank(needle: String, name: String, producer: String?) -> Int? {
        guard !name.isEmpty else { return nil }
        if name == needle { return 0 }
        if name.hasPrefix(needle) { return 1 }
        if let producer, !producer.isEmpty {
            if producer == needle { return 0 }
            if producer.hasPrefix(needle) { return 1 }
        }

        let queryTokens = needle.split(separator: " ").map(String.init)
        let nameTokens = (name.split(separator: " ").map(String.init))
            + (producer?.split(separator: " ").map(String.init) ?? [])
        guard !queryTokens.isEmpty else { return nil }

        var missing = 0
        var softCount = 0
        for token in queryTokens {
            let isHard = token.contains(where: { $0.isNumber })
            if isHard {
                // Процент и вес — не синонимы и не опечатки. «5» совпадает
                // только с «5», но не с «50».
                guard nameTokens.contains(token) else { return nil }
                continue
            }
            softCount += 1
            if nameTokens.contains(where: { tokenMatches($0, token) }) { continue }
            missing += 1
        }

        if missing == 0 { return 2 }
        // Одно пропущенное слово прощаем, только когда слов достаточно, чтобы
        // не спутать «куриную грудку» с «куриной котлетой».
        if softCount >= 3, missing == 1 { return 3 }
        return nil
    }

    private static func tokenMatches(_ nameToken: String, _ queryToken: String) -> Bool {
        if nameToken == queryToken { return true }
        let shortest = min(nameToken.count, queryToken.count)
        if shortest >= 3,
           nameToken.hasPrefix(queryToken) || queryToken.hasPrefix(nameToken) {
            return true
        }
        if shortest >= 4,
           stemmed(nameToken) == stemmed(queryToken) {
            return true
        }
        if shortest >= 4, isOneEditApart(nameToken, queryToken) {
            return true
        }
        return false
    }

    /// Грубое отсечение окончаний: «яйца» и «яйцо» — одно слово, «молока» и
    /// «молоко» — тоже. Полноценный стеммер здесь не нужен и был бы опасен:
    /// он склеивает «курицу» с «куриным», а это разные продукты.
    static func stemmed(_ word: String) -> String {
        let value = FoodCatalog.normalize(word)
        guard value.count > 3 else { return value }
        for suffix in ["ами", "ями", "ов", "ев", "ей", "ые", "ие", "ая",
                       "ое", "ах", "ях", "ам", "ям", "ом", "ем", "ий",
                       "ый", "ой", "ую", "юю", "es", "s"] {
            if value.hasSuffix(suffix), value.count - suffix.count >= 3 {
                return String(value.dropLast(suffix.count))
            }
        }
        for suffix in ["а", "я", "ы", "и", "у", "ю", "е", "о", "ь"] {
            if value.hasSuffix(suffix), value.count >= 4 {
                return String(value.dropLast())
            }
        }
        return value
    }

    private static func isOneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= 1 else { return false }
        var i = 0
        var j = 0
        var edits = 0
        while i < left.count, j < right.count {
            if left[i] == right[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if left.count > right.count {
                i += 1
            } else if left.count < right.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }
        if i < left.count || j < right.count { edits += 1 }
        return edits <= 1
    }
}
