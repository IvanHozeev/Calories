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

    @Test func bareNumberBelowTwentyIsAPieceCount() throws {
        let item = try one("яйцо 2")
        #expect(item.name == "яйцо")
        #expect(item.units == 2)
        #expect(item.grams == nil)
    }

    @Test func bareNumberAboveTwentyIsGrams() throws {
        let item = try one("овсянка 80")
        #expect(item.name == "овсянка")
        #expect(item.grams == 80)
    }

    @Test func decimalCommaIsNotASeparator() throws {
        let item = try one("банан 1,5")
        #expect(item.name == "банан")
        #expect(item.units == 1.5)
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
}
