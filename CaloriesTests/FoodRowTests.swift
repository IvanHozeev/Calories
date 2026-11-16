import Testing
import Foundation
@testable import Calories

/// Строка продукта: из чего калории (полоска долей) и порция по «+».
struct MacroShareBarTests {
    @Test func noMacrosNoBar() {
        #expect(MacroShareBar.shares(.zero).isEmpty)
    }

    /// Доли идут в порядке «белки, жиры, углеводы» и складываются в единицу.
    @Test func sharesAreInOrderAndSumToOne() {
        let shares = MacroShareBar.shares(Macros(protein: 20, fat: 10, carbs: 30))
        #expect(shares.map(\.kind) == [.protein, .fat, .carbs])
        #expect(abs(shares.reduce(0) { $0 + $1.share } - 1) < 1e-9)
    }

    /// По калориям, а не по граммам: десять граммов жира весят как двадцать
    /// два с половиной белка — иначе масло выглядело бы почти нейтральным.
    @Test func fatCountsNineKilocaloriesPerGram() {
        let shares = MacroShareBar.shares(Macros(protein: 10, fat: 10, carbs: 0))
        let fat = shares.first { $0.kind == .fat }?.share ?? 0
        #expect(abs(fat - 90.0 / 130.0) < 1e-9)
    }

    /// Нулевые макросы отрезка не дают: белок без жира и углеводов — один отрезок.
    @Test func zeroMacrosAreSkipped() {
        let shares = MacroShareBar.shares(Macros(protein: 25, fat: 0, carbs: 0))
        #expect(shares.count == 1)
        #expect(shares.first?.kind == .protein)
    }
}

struct QuickAddItemTests {
    private func food(kcal: Int = 110, defaultGrams: Double = 100) -> FoodItem {
        FoodItem(name: "Курица", caloriesPer100g: kcal, protein: 23, fat: 2, carbs: 0,
                 defaultGrams: defaultGrams)
    }

    /// Обычная порция главнее порции продукта: человек ест её, а не ту, что
    /// записана в каталоге.
    @Test func theUsualPortionComesFirst() {
        let item = AddEntryView.quickItem(for: food(defaultGrams: 150), usualGrams: 180)
        #expect(item.grams == 180)
        #expect(item.calories == 198)
        #expect(item.pieces == nil)
    }

    @Test func withoutAUsualPortionTheFoodsOwnIsUsed() {
        let item = AddEntryView.quickItem(for: food(defaultGrams: 150), usualGrams: nil)
        #expect(item.grams == 150)
        #expect(item.calories == 165)
    }

    @Test func withoutAnyPortionItIsAHundredGrams() {
        let item = AddEntryView.quickItem(for: food(defaultGrams: 0), usualGrams: nil)
        #expect(item.grams == 100)
        #expect(item.calories == 110)
    }

    @Test func theMacrosFollowTheGrams() {
        let item = AddEntryView.quickItem(for: food(), usualGrams: 200)
        #expect(abs(item.macros.protein - 46) < 1e-9)
    }

    /// Продукт «на штуку»: одна штука, граммов нет, числа — на штуку.
    @Test func aPerPieceFoodIsOnePiece() {
        let shake = food(kcal: 320)
        shake.isPerUnit = true
        let item = AddEntryView.quickItem(for: shake, usualGrams: 150)
        #expect(item.pieces == 1)
        #expect(item.grams == nil)
        #expect(item.calories == 320)
    }
}

/// Значок встаёт рядом с последним словом названия — а значит, последнее слово
/// должно быть настоящим, даже если в имени лишние пробелы.
struct FoodNameSplitTests {
    @Test func splitsOffTheLastWord() {
        let split = FoodRow.splitName("Протеин со вкусом печенья")
        #expect(split.head == "Протеин со вкусом")
        #expect(split.last == "печенья")
    }

    /// Пробел на конце раньше давал пустое последнее слово, и значок
    /// оставался один на отдельной строке.
    @Test func trailingAndDoubledSpacesDoNotMakeEmptyWords() {
        let split = FoodRow.splitName("Корнишоны  маринованные ")
        #expect(split.head == "Корнишоны")
        #expect(split.last == "маринованные")
    }

    @Test func aSingleWordHasNoHead() {
        let split = FoodRow.splitName("Пармезан")
        #expect(split.head.isEmpty)
        #expect(split.last == "Пармезан")
    }
}
