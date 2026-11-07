import SwiftUI

/// «Кажется, ты готовишь: Борщ» — строка над собираемым приёмом.
///
/// Догадка, а не утверждение, и написана так же: предлагает, а не
/// исправляет. Нажатие дописывает недостающие продукты рецепта в приём —
/// именно дописывает, а не заменяет собранное: человек мог положить вдвое
/// больше картофеля, и его вес важнее рецептного.
struct RecipeHintRow: View {
    let match: RecipeHint.Match
    var onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 8) {
                Image(systemName: match.dish.dishKind.icon)
                    .font(.app(.footnote))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Кажется, ты готовишь")
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                    Text(verbatim: match.dish.name)
                        .font(.app(.subheadline, weight: .semibold))
                }
                Spacer(minLength: 0)
                // Что сделает нажатие, сказано словом, а не стрелкой:
                // стрелка в списке означает переход, а здесь ничего не
                // открывается — состав дописывается на месте.
                Text("Дополнить")
                    .font(.app(.caption, weight: .semibold))
            }
            .foregroundStyle(MacroKind.carbs.color)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recipeHint")
    }
}
