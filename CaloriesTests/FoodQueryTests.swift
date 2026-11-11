import Testing
import Foundation
@testable import Calories

/// Разбор строки поиска: «творог 5% 180» — это продукт, жирность и вес, а не
/// три слова подряд. Ошибка здесь стоит дорого: быстрый выбор пишет в дневник
/// одним тапом, без экрана порции, где её можно было бы заметить.
@Suite struct FoodQueryTests {

    private func one(_ query: String) throws -> FoodQuery.Item {
        let items = FoodQuery.parse(query)
        return try #require(items.count == 1 ? items.first : nil,
                            "Запрос «\(query)» должен разобраться в одну позицию")
    }

    // MARK: - Количество

    @Test func explicitGramsComeFromThePhrase() throws {
        let item = try one("курица 200 г")
        #expect(item.name == "курица")
        #expect(item.grams == 200)
        #expect(item.units == nil)
    }

    @Test func percentStaysPartOfTheName() throws {
        let item = try one("творог 5% 180")
        #expect(item.name == "творог 5%")
        #expect(item.grams == 180)
        #expect(item.percent == 5)
    }

    @Test func kilogramsBecomeGrams() throws {
        let item = try one("творог 0,5 кг")
        #expect(item.name == "творог")
        #expect(item.grams == 500)
    }

    @Test func litersBecomeGrams() throws {
        #expect(try one("молоко 0,5 л").grams == 500)
        #expect(try one("йогурт 200 мл").grams == 200)
    }

    @Test func bareNumberBelowTwentyIsGrams() throws {
        let item = try one("яйцо 2")
        #expect(item.name == "яйцо")
        #expect(item.grams == 2)
        #expect(item.units == nil)
    }

    @Test func bareNumberAboveTwentyIsGrams() throws {
        let item = try one("овсянка 80")
        #expect(item.name == "овсянка")
        #expect(item.grams == 80)
    }

    @Test func decimalCommaIsGrams() throws {
        let item = try one("банан 1,5")
        #expect(item.name == "банан")
        #expect(item.grams == 1.5)
        #expect(item.units == nil)
    }

    /// Одна и та же цифра читается по месту: перед названием — штуки, после — граммы.
    ///
    /// «2 яйца» — два яйца, «яйцо 2» — два грамма. Раньше обе фразы давали
    /// граммы: правило про число после названия забрало и ведущее, и «2 яйца»
    /// записывались как три килокалории.
    @Test func aLeadingNumberIsPiecesAndATrailingOneIsGrams() throws {
        for (phrase, name, count) in [("2 яйца", "яйца", 2.0),
                                      ("3 банана", "банана", 3.0),
                                      ("1,5 банана", "банана", 1.5)] {
            let item = try one(phrase)
            #expect(item.name == name)
            #expect(item.units == count, "«\(phrase)» — \(count) шт")
            #expect(item.grams == nil, "«\(phrase)» не должно становиться граммами")
        }
        let trailing = try one("яйцо 2")
        #expect(trailing.grams == 2)
        #expect(trailing.units == nil)
    }

    /// Явная единица сильнее догадки «число больше двадцати».
    ///
    /// Догадка стояла раньше и забирала число, не глядя на то, что за ним:
    /// «пельмени 25 шт» становились двадцатью пятью граммами, а «шт»
    /// выбрасывалось как лишнее.
    @Test func anExplicitUnitBeatsTheLargeNumberGuess() throws {
        for (phrase, name, count) in [("пельмени 25 шт", "пельмени", 25.0),
                                      ("креветки 30 шт", "креветки", 30.0),
                                      ("орехи 40 штук", "орехи", 40.0)] {
            let item = try one(phrase)
            #expect(item.name == name)
            #expect(item.units == count, "«\(phrase)» — \(count) шт")
            #expect(item.grams == nil)
        }
        #expect(try one("мука 25 кг").grams == 25_000, "килограммы не должны терять множитель")
        #expect(try one("сыр 100 г").grams == 100)
    }

    /// Первой разбирается самая левая позиция.
    ///
    /// Остаток фразы разбирается дальше, как следующая позиция. Если искать
    /// количество по виду единицы, находится последнее — «200 мл», — а «300»
    /// остаётся в названии, и две позиции сливаются в «молоко 300 протеин».
    @Test func theLeftmostQuantityIsTakenFirst() throws {
        let milk = try #require(
            { let p = FoodQuery.parse("молоко 300 протеин 200 мл"); return p.count == 2 ? p : nil }(),
            "две позиции")
        #expect(milk[0].name == "молоко")
        #expect(milk[0].grams == 300)
        #expect(milk[1].name == "протеин")
        #expect(milk[1].grams == 200)

        let dumplings = try #require(
            { let p = FoodQuery.parse("молоко 300 пельмени 25 шт"); return p.count == 2 ? p : nil }(),
            "две позиции")
        #expect(dumplings[0].grams == 300)
        #expect(dumplings[1].name == "пельмени")
        #expect(dumplings[1].units == 25)
    }

    @Test func aNumberInsideANameIsNotAQuantity() throws {
        let item = try one("хлеб 5 злаков")
        #expect(item.name == "хлеб 5 злаков")
        #expect(item.hasQuantity == false)
    }

    @Test func numberWordsAreQuantity() throws {
        let item = try one("два яйца")
        #expect(item.name == "яйца")
        #expect(item.units == 2)
    }

    @Test func englishWordsWorkToo() throws {
        let eggs = try one("two eggs")
        #expect(eggs.name == "eggs")
        #expect(eggs.units == 2)

        let half = try one("half a banana")
        #expect(half.name == "banana")
        #expect(half.units == 0.5)
    }

    @Test func halfAttachedToTheNameIsStillHalf() throws {
        let item = try one("полбанана")
        #expect(item.name == "банана")
        #expect(item.units == 0.5)
    }

    @Test func fractionsWork() throws {
        #expect(try one("банан ½").units == 0.5)
        #expect(try one("1/2 банана").units == 0.5)
        #expect(try one("1 1/2 банана").units == 1.5)
    }

    @Test func portionsArePiecesWithTheFoodsOwnWeight() throws {
        let item = try one("2 порции творога")
        #expect(item.name == "творога")
        #expect(item.units == 2)
    }

    @Test func gramsAreResolvedByTheFoodsDefaultPortion() {
        #expect(FoodQuery.Item(name: "яйцо", units: 2).grams(defaultGrams: 55) == 110)
        #expect(FoodQuery.Item(name: "банан", units: 1.5).grams(defaultGrams: 120) == 180)
        #expect(FoodQuery.Item(name: "творог", grams: 180).grams(defaultGrams: 100) == 180)
        #expect(FoodQuery.Item(name: "творог").grams(defaultGrams: 100) == nil)
    }

    // MARK: - Несколько продуктов

    @Test func commaSeparatesProducts() throws {
        let items = FoodQuery.parse("творог 200, банан")
        #expect(items.count == 2)
        #expect(items[0].name == "творог")
        #expect(items[0].grams == 200)
        #expect(items[1].name == "банан")
        #expect(items[1].hasQuantity == false)
    }

    @Test func aNumericTailAfterCommaBelongsToTheSameProduct() throws {
        let items = FoodQuery.parse("творог 5%, 180 г")
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.name == "творог 5%")
        #expect(item.grams == 180)
    }

    @Test func twoProductsInOnePhraseAreSplitIntoTwoQuickAdds() throws {
        // `#require`, а не `#expect`: после проваленной проверки на число позиций
        // индекс `items[1]` ронял весь процесс, и один сбой прятал остальные.
        let items = try #require(
            { let parsed = FoodQuery.parse("молоко 300 протеин 40 г")
              return parsed.count == 2 ? parsed : nil }(),
            "«молоко 300 протеин 40 г» — две позиции")
        #expect(items[0].name == "молоко")
        #expect(items[0].grams == 300)
        #expect(items[1].name == "протеин")
        #expect(items[1].grams == 40)
    }

    @Test func aPhraseWithoutQuantityIsStillAName() throws {
        let item = try one("творог 9%")
        #expect(item.name == "творог 9%")
        #expect(item.percent == 9)
        #expect(item.hasQuantity == false)
    }

    @Test func aBareNumberIsNotAProduct() {
        #expect(FoodQuery.parse("180").isEmpty)
        #expect(FoodQuery.parse("2 кг").isEmpty)
    }

    // MARK: - Совпадение

    @Test func exactAndPrefixMatchesRankAboveTokenMatches() {
        #expect(FoodQuery.rank(query: "творог 5%", name: "Творог 5%") == 0)
        #expect(FoodQuery.rank(query: "творог", name: "Творог 5%") == 1)
        #expect(FoodQuery.rank(query: "5 творог", name: "Творог 5%") == 2)
    }

    @Test func percentIsAHardConstraint() {
        #expect(FoodQuery.rank(query: "творог 9%", name: "Творог 5%") == nil)
        #expect(FoodQuery.rank(query: "творог 5%", name: "Творог 5%") == 0)
    }

    /// Десятичный процент — одно число, а не два.
    ///
    /// Нормализация рвала «3,2» на «3» и «2», и «молоко 2%» находило «3,2%», а
    /// «молоко 5%» — «1,5%»: число из запроса совпадало с половиной чужого.
    /// Что «молоко 3%» находит «3,2%» — не закреплено намеренно: это
    /// отдельный вопрос, и решать его тестом, не решив, нельзя.
    @Test func aDecimalPercentIsOneNumber() {
        #expect(FoodQuery.rank(query: "молоко 2%", name: "Молоко 3,2%") == nil)
        #expect(FoodQuery.rank(query: "молоко 5%", name: "Молоко 1,5%") == nil)
        #expect(FoodQuery.rank(query: "молоко 3,2%", name: "Молоко 2,5%") == nil)
        #expect(FoodQuery.rank(query: "молоко 3,2%", name: "Молоко 3,2%") == 0)
        #expect(FoodQuery.rank(query: "молоко 3.2%", name: "Молоко 3,2%") == 0,
                "точка и запятая — одно и то же число")
    }

    @Test func endingsAndTyposStillFindTheFood() {
        #expect(FoodQuery.rank(query: "яйца", name: "Яйцо куриное") == 2)
        #expect(FoodQuery.rank(query: "банап", name: "Банан") == 2)
    }

    @Test func oneMissingWordIsForgivenOnlyInALongQuery() {
        #expect(FoodQuery.rank(query: "куриная грудка варёная", name: "Куриная грудка") == 3)
        #expect(FoodQuery.rank(query: "куриная котлета", name: "Куриная грудка") == nil)
    }

    @Test func producerIsSearchedToo() {
        #expect(FoodQuery.rank(query: "golden", name: "Пармезан", producer: "Golden") == 0)
        #expect(FoodQuery.rank(query: "gold", name: "Пармезан", producer: "Golden") == 1)
    }

    @Test func anyLanguageNameCanMatch() {
        let names = ["Cottage cheese 5%", "Творог 5%", "קוטג' 5%"]
        #expect(FoodQuery.rank(query: "творог 5%", names: names) == 0)
        #expect(FoodQuery.rank(query: "cottage cheese", names: names) == 1)
    }

    // MARK: - Early ranker (popularity from choice log)

    @Test func popularityScoreIsZeroWhenNeverShown() {
        let log = SearchEventLog(fileURL: URL(fileURLWithPath: "/tmp/test_popularity_never_shown.json"))
        try? FileManager.default.removeItem(at: log.fileURL)
        #expect(log.popularityScore(for: "творог 5%") == 0)
    }

    @Test func popularityScoreIsZeroWhenShownButNeverSelected() {
        let log = SearchEventLog(fileURL: URL(fileURLWithPath: "/tmp/test_popularity_shown.json"))
        try? FileManager.default.removeItem(at: log.fileURL)
        log.log(SearchEvent(
            id: UUID(),
            query: "творог",
            shown: [ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1)],
            selected: nil,
            selectedGrams: nil,
            timestamp: Date()
        ))
        #expect(log.popularityScore(for: "творог 5%") == 0)
    }

    @Test func popularityScoreIsOneWhenAlwaysSelected() {
        let log = SearchEventLog(fileURL: URL(fileURLWithPath: "/tmp/test_popularity_always.json"))
        try? FileManager.default.removeItem(at: log.fileURL)
        log.log(SearchEvent(
            id: UUID(),
            query: "творог",
            shown: [ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1)],
            selected: ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1),
            selectedGrams: 200,
            timestamp: Date()
        ))
        log.log(SearchEvent(
            id: UUID(),
            query: "творог",
            shown: [ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1)],
            selected: ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1),
            selectedGrams: 180,
            timestamp: Date()
        ))
        #expect(log.popularityScore(for: "творог 5%") == 1)
    }

    @Test func popularityScoreBetweenZeroAndOne() {
        let log = SearchEventLog(fileURL: URL(fileURLWithPath: "/tmp/test_popularity_mixed.json"))
        try? FileManager.default.removeItem(at: log.fileURL)
        // Показали 3 раза, выбрали 1 → score 0.333...
        for _ in 0..<3 {
            log.log(SearchEvent(
                id: UUID(),
                query: "творог",
                shown: [ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1)],
                selected: nil,
                selectedGrams: nil,
                timestamp: Date()
            ))
        }
        log.log(SearchEvent(
            id: UUID(),
            query: "творог",
            shown: [ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1)],
            selected: ShownItem(name: "творог 5%", percent: 5, source: "catalog", rank: 1),
            selectedGrams: 200,
            timestamp: Date()
        ))
        #expect(log.popularityScore(for: "творог 5%") == 0.25, "ожидалось 1/4 = 0.25")
    }
}
