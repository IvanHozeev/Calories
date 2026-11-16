import SwiftUI

/// Сваренное в холодильнике: блюдо, сколько осталось и какие по счёту сутки.
///
/// В «Рационе» блюдо с остатком раньше отличалось от остальных одной
/// подписью «осталось 2 порции» мелким серым. Но про сваренное важно другое —
/// сколько ему ещё стоять: полоска из четырёх суточных отрезков говорит это
/// без чисел, и последний, красный, — «лучше не есть».
struct FridgeBatchRow: View {
    let dish: Dish
    let state: DishBatch.State
    var now: Date = Date()
    var onAdd: () -> Void

    private var day: Int { state.dayNumber(now: now) }

    /// Цвет суток: до третьих — калорийный, на третьих — предупреждение,
    /// на четвёртых — красный, как любой промах.
    private func color(forDay index: Int) -> Color {
        switch index {
        case ..<3: return ProgressRing.kcalColors[0]
        case 3: return MacroKind.fat.color
        default: return ProgressRing.overColors[0]
        }
    }

    private var remainingText: String {
        if let servings = state.remainingServings, servings >= 0.5 {
            return PortionCount.left(servings)
        }
        return String(format: String(localized: "осталось %.0f г"), state.remainingGrams)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: dish.name)
                    .font(.app(.callout, weight: .semibold))
                Text(verbatim: String(format: String(localized: "%lld ккал на порцию · %lld г"),
                                      dish.servingCalories, Int(dish.servingGrams.rounded())))
                    .font(.app(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        ForEach(1...DishBatch.shelfLifeDays, id: \.self) { index in
                            Capsule()
                                .fill(index <= day ? color(forDay: day) : color(forDay: day).opacity(0.24))
                                .frame(width: 14, height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("\(remainingText) · день \(day) из \(DishBatch.shelfLifeDays)")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.16))
                    Image(systemName: "plus")
                        .font(.app(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(String(localized: "В приём пищи")) \(dish.name)"))
            .accessibilityIdentifier("fridgeAdd")
            .padding(.trailing, -6)
        }
        .padding(.vertical, 4)
    }
}
