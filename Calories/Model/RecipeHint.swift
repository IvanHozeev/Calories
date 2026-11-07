import Foundation

/// «Кажется, ты готовишь вот это».
///
/// Вторая половина связи продукта и рецепта. Продукт уже знает свои рецепты;
/// здесь приложение узнаёт их по тому, что человек кладёт в приём: набралось
/// две позиции из одного рецепта и больше половины его веса — значит, скорее
/// всего, готовится он.
///
/// Считается по именам, как и всё остальное вокруг составов: имя — то, что
/// действительно лежит и в рецепте, и в записи дневника.
enum RecipeHint {

    /// Рецепт, похожий на то, что собрано в черновике.
    struct Match: Identifiable, Equatable {
        let dish: Dish
        /// Сколько позиций рецепта уже в черновике.
        let covered: Int
        /// Какую долю веса рецепта они составляют, 0…1.
        let share: Double

        var id: UUID { dish.id }

        static func == (left: Match, right: Match) -> Bool {
            left.dish.id == right.dish.id && left.covered == right.covered
        }
    }

    /// Из скольких совпавших позиций подсказка имеет смысл.
    ///
    /// Две. По одной совпадают все рецепты сразу: масло есть в каждом втором,
    /// и подсказка превратилась бы в список всего, что человек когда-либо
    /// готовил.
    static let minimumCovered = 2

    /// И какую долю веса рецепта они должны покрывать.
    ///
    /// Половину. Соль и масло — это две позиции, но три процента веса: по ним
    /// «готовит борщ» сказать нельзя. Доля считается по весу, а не по числу
    /// позиций, потому что в рецепте из десяти строк восемь — приправы.
    static let minimumShare = 0.5

    /// Сколько подсказок показывать разом.
    ///
    /// Одну. Подсказка — это догадка, и список догадок читается как «мы не
    /// знаем»; лучшая из них либо верна, либо нет.
    static let limit = 1

    /// Рецепты, похожие на собранное.
    ///
    /// - Parameters:
    ///   - draft: имена того, что уже в приёме.
    ///   - dishes: все рецепты человека.
    static func matches(draft: [String], dishes: [Dish]) -> [Match] {
        let names = Set(draft.map { $0.folded })
        guard !names.isEmpty else { return [] }

        return dishes
            .compactMap { dish -> Match? in
                // Сам рецепт уже в приёме — говорить нечего: человек его и
                // добавил, а подсказка предложила бы добавить второй раз.
                guard !names.contains(dish.name.folded) else { return nil }

                let parts = dish.ingredients
                let total = parts.reduce(0.0) { $0 + $1.grams }
                guard total > 0 else { return nil }

                let found = parts.filter { names.contains($0.foodName.folded) }
                guard found.count >= minimumCovered else { return nil }

                let share = found.reduce(0.0) { $0 + $1.grams } / total
                guard share >= minimumShare else { return nil }

                return Match(dish: dish, covered: found.count, share: share)
            }
            // Сначала те, что совпали плотнее; при равной доле — где совпало
            // больше позиций.
            .sorted { left, right in
                left.share == right.share ? left.covered > right.covered : left.share > right.share
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Чего из рецепта ещё нет в приёме — это и дописывается по нажатию.
    static func missing(from dish: Dish, draft: [String]) -> [DishIngredient] {
        let names = Set(draft.map { $0.folded })
        return dish.ingredients.filter { !names.contains($0.foodName.folded) }
    }
}

private extension String {
    /// Имя для сравнения: регистр и крайние пробелы роли не играют.
    var folded: String {
        trimmingCharacters(in: .whitespaces).lowercased()
    }
}
