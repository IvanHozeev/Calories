import SwiftUI

struct MacrosRow: View {
    let macros: Macros

    var body: some View {
        HStack(spacing: 20) {
            macroItem(title: "Белки", value: macros.protein, color: MacroKind.protein.color)
            macroItem(title: "Жиры", value: macros.fat, color: MacroKind.fat.color)
            macroItem(title: "Углеводы", value: macros.carbs, color: MacroKind.carbs.color)
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
