import SwiftUI

/// Значки витаминов и минералов, которыми продукт заметно богат, — рядом с
/// макросами в строке.
///
/// Смысл в том, чтобы состав считывался, не открывая продукт: «Ca K» у творога
/// видно боковым зрением, а «кальций 83 мг на 100 г» приходится читать и
/// сравнивать с нормой в уме.
///
/// Цвет здесь не украшение, а единственное отличие. Натрий — потолок, а не
/// цель: «богат натрием» это предупреждение, и зелёным вместе с кальцием он
/// стоять не может, иначе значок читается как достоинство.
struct MicroTags: View {
    let nutrients: [Micronutrient]
    /// Больше трёх не показываем: дальше они съедают строку, а различать
    /// продукты по четвёртому значку всё равно не выходит.
    var limit: Int = 3
    var compact: Bool = true

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(nutrients.prefix(limit)) { nutrient in
                tag(nutrient.symbol, color: color(for: nutrient))
                    .accessibilityLabel(nutrient.title)
                    // Идентификатор не зависит от языка: тесты идут на английской
                    // локали, а подпись значка — химический символ.
                    .accessibilityIdentifier("microTag-\(nutrient.rawValue)")
            }
            if nutrients.count > limit {
                // Стрелка, а не плюс: плюс в этом приложении везде означает
                // «добавить», и в строке продукта читался бы как кнопка.
                overflowTag
                    .accessibilityLabel(Text("Ещё"))
            }
        }
    }

    private var overflowTag: some View {
        Image(systemName: "arrow.up")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func color(for nutrient: Micronutrient) -> Color {
        nutrient.isCeiling ? .orange : .green
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MicroTags(nutrients: [.calcium, .potassium, .vitaminB12])
        MicroTags(nutrients: [.iron, .magnesium, .zinc, .selenium])
        MicroTags(nutrients: [.sodium, .potassium])
    }
    .padding()
}
