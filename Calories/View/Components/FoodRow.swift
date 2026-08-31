import SwiftUI

/// Строка продукта или блюда в любом списке выбора. Одна на все экраны: раньше
/// в AddEntryView и MyFoodView лежали свои копии с рассыпанной строкой «Б12 Ж22 У41»
/// и калориями серым шрифтом на втором плане.
struct FoodRow: View {
    let name: String
    let calories: Int
    /// Порция, к которой относятся цифры: «100 г», «250 г».
    let portion: String
    let macros: Macros
    /// Подпись слева от порции — например, число ингредиентов у блюда.
    var detail: String? = nil
    /// Значок категории. Не украшение: в списке из шести десятков строк он
    /// даёт зацепку для глаза, по которой продукт находится быстрее, чем по тексту.
    var icon: String? = nil

    private var hasMacros: Bool {
        macros.protein > 0 || macros.fat > 0 || macros.carbs > 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .lineLimit(2)

                // Та же строка подписей, что и в дневнике: ячейки продукта
                // должны читаться одинаково, где бы они ни стояли.
                HStack(spacing: 6) {
                    if let detail {
                        Text(verbatim: detail)
                        Text(verbatim: "·")
                    }
                    Text(verbatim: portion)
                    if let icon {
                        Text(verbatim: "·")
                        Image(systemName: icon)
                            .accessibilityHidden(true)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if hasMacros {
                    MacroTags(macros: macros, compact: true)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(calories)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("ккал")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
