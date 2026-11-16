import SwiftUI

/// Строка рецепта в «Рационе»: название, калории на порцию с весом и доли макросов.
///
/// Калории не стоят отдельным числом справа, как у продукта в `FoodRow`:
/// у рецепта главное — что это за блюдо, а число уходит в подпись, и справа
/// остаётся полоска долей белков, жиров и углеводов. Шеврон — от ссылки списка.
struct DishRow: View {
    let dish: Dish

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: dish.name)
                    .font(.app(.body))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(verbatim: String(format: String(localized: "%lld ккал на порцию · %lld г"),
                                      dish.servingCalories, Int(dish.servingGrams.rounded())))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            MacroShareBar(macros: dish.servingMacros, width: 38)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}
