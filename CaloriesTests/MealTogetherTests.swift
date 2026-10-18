import Testing
import Foundation
@testable import Calories

/// Что человек кладёт вместе: пороги и порции.
///
/// Проверяется логика, а не экран: «дважды — уже привычка, один раз —
/// совпадение» и «порция берётся медианой» — это те решения, которые ломаются
/// незаметно и всплывают строкой, предлагающей съесть четыреста грамм протеина.
@Suite("Что обычно вместе")
struct MealTogetherTests {

    private func part(_ name: String, grams: Double? = nil, calories: Int = 100) -> EntryComponent {
        EntryComponent(name: name, calories: calories,
                       macros: Macros(protein: 10, fat: 1, carbs: 2), grams: grams)
    }

    @Test("Пара, встреченная дважды, предлагается")
    func suggestsRepeatedPair() {
        let history = [
            [part("Молоко"), part("Протеин")],
            [part("Молоко"), part("Протеин")]
        ]
        let found = MealPairs.suggestions(draft: ["Молоко"], history: history)
        #expect(found.map(\.name) == ["Протеин"])
        #expect(found.first?.together == 2)
    }

    @Test("Один раз вместе — это совпадение, а не привычка")
    func ignoresSinglePair() {
        let history = [[part("Молоко"), part("Банан")]]
        #expect(MealPairs.suggestions(draft: ["Молоко"], history: history).isEmpty)
    }

    @Test("То, что уже в приёме, второй раз не предлагается")
    func skipsWhatIsAlreadyThere() {
        let history = [
            [part("Молоко"), part("Протеин")],
            [part("Молоко"), part("Протеин")]
        ]
        let found = MealPairs.suggestions(draft: ["Молоко", "Протеин"], history: history)
        #expect(found.isEmpty)
    }

    @Test("Имя сравнивается без регистра и пробелов")
    func matchesNamesLoosely() {
        let history = [
            [part(" молоко "), part("Протеин")],
            [part("МОЛОКО"), part("Протеин")]
        ]
        #expect(MealPairs.suggestions(draft: ["Молоко"], history: history).first?.together == 2)
    }

    @Test("Порция — медиана, а не среднее")
    func usesMedianPortion() {
        // Одна запись на четыреста грамм рядом с тремя по тридцать: среднее
        // дало бы 122 г, которые человек никогда не ел.
        let history = [
            [part("Молоко"), part("Протеин", grams: 30)],
            [part("Молоко"), part("Протеин", grams: 30)],
            [part("Молоко"), part("Протеин", grams: 400)]
        ]
        #expect(MealPairs.suggestions(draft: ["Молоко"], history: history).first?.grams == 30)
    }

    @Test("Калории пересчитаны под предложенную порцию")
    func scalesCaloriesToSuggestedPortion() {
        // Последним съели двойную порцию; предлагаем обычную — и калории
        // должны быть от неё, иначе строка обещает одно, а кладёт другое.
        let history = [
            [part("Молоко"), part("Протеин", grams: 30, calories: 120)],
            [part("Молоко"), part("Протеин", grams: 30, calories: 120)],
            [part("Молоко"), part("Протеин", grams: 60, calories: 240)]
        ]
        let found = MealPairs.suggestions(draft: ["Молоко"], history: history).first
        #expect(found?.grams == 30)
        #expect(found?.calories == 120)
    }

    @Test("Чаще вместе — выше в списке")
    func ordersByHowOftenTogether() {
        let history = [
            [part("Паста"), part("Котлета")],
            [part("Паста"), part("Котлета")],
            [part("Паста"), part("Котлета")],
            [part("Паста"), part("Сыр")],
            [part("Паста"), part("Сыр")]
        ]
        #expect(MealPairs.suggestions(draft: ["Паста"], history: history).map(\.name)
                == ["Котлета", "Сыр"])
    }

    @Test("Приём, в котором нет ничего из черновика, в счёт не идёт")
    func ignoresUnrelatedMeals() {
        let history = [
            [part("Гречка"), part("Курица")],
            [part("Гречка"), part("Курица")]
        ]
        #expect(MealPairs.suggestions(draft: ["Молоко"], history: history).isEmpty)
    }

    @Test("Без черновика предлагать нечего")
    func emptyDraftSuggestsNothing() {
        let history = [
            [part("Молоко"), part("Протеин")],
            [part("Молоко"), part("Протеин")]
        ]
        #expect(MealPairs.suggestions(draft: [], history: history).isEmpty)
    }

    @Test("Показываем не больше трёх")
    func capsTheList() {
        var history: [[EntryComponent]] = []
        for name in ["А", "Б", "В", "Г", "Д"] {
            history.append([part("Молоко"), part(name)])
            history.append([part("Молоко"), part(name)])
        }
        #expect(MealPairs.suggestions(draft: ["Молоко"], history: history).count == MealPairs.limit)
    }
}
