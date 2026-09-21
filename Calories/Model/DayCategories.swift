import Foundation

/// Из чего собран рацион дня — по категориям продуктов, а не по макросам.
///
/// Белки-жиры-углеводы говорят, как день устроен химически, но не отвечают на
/// вопрос, ради которого на состав смотрят: чего в рационе нет. «Мало белка»
/// и «за день ни одного овоща» — разные новости, и вторую по макросам не
/// увидеть никак.
enum DayCategories {
    struct Part: Equatable, Identifiable {
        /// Категория продукта; `nil` — про эту еду неизвестно, из чего она.
        let category: FoodCategory?
        let calories: Int
        let share: Double

        var id: String { category?.rawValue ?? "unknown" }
    }

    /// Доли категорий по калориям, от большей к меньшей.
    ///
    /// Неизвестное не прячется и не растворяется по остальным: приёмы,
    /// записанные до того, как приложение стало хранить состав, — это честная
    /// дыра в данных, и она должна быть видна как дыра.
    static func split(_ items: [(category: FoodCategory?, calories: Int)]) -> [Part] {
        let total = items.reduce(0) { $0 + max(0, $1.calories) }
        guard total > 0 else { return [] }

        var sums: [FoodCategory?: Int] = [:]
        for item in items where item.calories > 0 {
            sums[item.category, default: 0] += item.calories
        }
        return sums
            .map { Part(category: $0.key, calories: $0.value, share: Double($0.value) / Double(total)) }
            // Неизвестное — всегда последним, каким бы большим оно ни было:
            // это не часть рациона, а то, чего мы про него не знаем.
            .sorted {
                if ($0.category == nil) != ($1.category == nil) { return $1.category == nil }
                return $0.calories > $1.calories
            }
    }
}
