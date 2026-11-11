import Testing
import Foundation
@testable import Calories

/// Поиск по каталогу: форма слова не обязана совпасть с названием буква в букву.
///
/// «2 яйца» не находили «Яйцо куриное», а «2 яйцо» находили: поиск сравнивал
/// буквально, а быстрое добавление берёт кандидатов именно из него.
@Suite struct CatalogSearchTests {

    private func russianNames(_ query: String) -> [String] {
        FoodCatalog.search(query).compactMap(\.ru)
    }

    @Test func aPluralFindsTheSingular() {
        #expect(russianNames("яйца").contains("Яйцо куриное"), "«яйца» не находят «Яйцо куриное»")
        #expect(russianNames("яйцо").contains("Яйцо куриное"))
    }

    @Test func everyWordOfTheQueryMustMatchByStem() {
        #expect(russianNames("яйца куриные").contains("Яйцо куриное"))
        #expect(!russianNames("яйца куриные").contains("Яйцо варёное"),
                "второе слово запроса не совпало, продукт не должен находиться")
    }

    /// Ярус форм слова — запасной: он ничего не добавляет к тому, что нашлось
    /// буквально, кроме как после него.
    @Test func aStemMatchDoesNotPullInUnrelatedFoods() {
        let found = russianNames("яйца")
        #expect(!found.isEmpty)
        #expect(!found.contains("Баклажан"))
        #expect(!found.contains("Яичница"), "«яичница» — другое слово, не форма «яйца»")
    }

    @Test func aLiteralMatchStaysAheadOfAFormMatch() {
        // «яйцо» совпадает буквально с обоими яйцами; форма «яйца» — только с ними
        // по основе, и ни та, ни другая не обгоняет буквальное.
        let literal = russianNames("яйцо")
        #expect(literal.first?.hasPrefix("Яйцо") == true)
    }
}
