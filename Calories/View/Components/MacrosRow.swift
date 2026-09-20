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

    private func macroItem(title: LocalizedStringKey, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(formatted(value))
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.0f \(String(localized: "г"))", value)
    }
}
