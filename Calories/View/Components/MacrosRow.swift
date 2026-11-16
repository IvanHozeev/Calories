import SwiftUI

struct MacrosRow: View {
    let macros: Macros

    /// Макрос, который округляется до нуля, не показываем: «0 г» у воды и
    /// газировки — это строки о том, чего нет. Остаются те, что есть; а когда
    /// нет ни одного, ряд не занимает места вовсе.
    private func shown(_ value: Double) -> Bool { value.rounded() > 0 }

    var body: some View {
        HStack(spacing: 20) {
            if shown(macros.protein) {
                macroItem(title: "Белки", value: macros.protein, color: MacroKind.protein.color)
            }
            if shown(macros.fat) {
                macroItem(title: "Жиры", value: macros.fat, color: MacroKind.fat.color)
            }
            if shown(macros.carbs) {
                macroItem(title: "Углеводы", value: macros.carbs, color: MacroKind.carbs.color)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func macroItem(title: LocalizedStringKey, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            // Число чёрное в светлой теме и цветное в тёмной: голубой и
            // персиковый на белом читаются хуже, а цвет макроса остаётся
            // точкой у названия — так же, как в плитках на «Сегодня».
            Text(formatted(value))
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? color : Color.primary)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.0f \(String(localized: "г"))", value)
    }
}
